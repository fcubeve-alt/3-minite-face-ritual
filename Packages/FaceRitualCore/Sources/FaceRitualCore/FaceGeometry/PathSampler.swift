import Foundation

/// 采样后的运动路径。视图坐标，可直接绘制。
///
/// `point(atProgress:)` 按**弧长**参数化，保证移动光点匀速 ——
/// 否则贝塞尔/圆弧上的光点会忽快忽慢，节奏提示就失真了。
public struct MotionPath: Sendable, Hashable {
    public let kind: PathType
    public let points: [Point2D]
    public let cumulativeLengths: [Double]
    public let totalLength: Double
    /// circle / arc 的圆心（视图坐标），用于绘制 ↻ 标记。
    public let center: Point2D?
    public let isClosed: Bool

    public init(kind: PathType, points: [Point2D], center: Point2D? = nil, isClosed: Bool = false) {
        self.kind = kind
        self.points = points
        self.center = center
        self.isClosed = isClosed

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(points.count)
        var total = 0.0
        if points.count > 1 {
            for index in 1..<points.count {
                total += points[index - 1].distance(to: points[index])
                cumulative.append(total)
            }
        }
        self.cumulativeLengths = cumulative
        self.totalLength = total
    }

    public var start: Point2D { points.first ?? .zero }
    public var end: Point2D { points.last ?? .zero }

    /// t ∈ [0, 1]，弧长均匀。
    public func point(atProgress t: Double) -> Point2D {
        guard points.count > 1, totalLength > 1e-9 else { return start }
        let target = clamp(t, 0, 1) * totalLength
        var low = 0
        var high = cumulativeLengths.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if cumulativeLengths[mid] <= target { low = mid } else { high = mid }
        }
        let segmentLength = cumulativeLengths[high] - cumulativeLengths[low]
        guard segmentLength > 1e-9 else { return points[low] }
        let localT = (target - cumulativeLengths[low]) / segmentLength
        return points[low].lerp(to: points[high], t: localT)
    }

    /// 该进度处的切线方向，用于画方向箭头。
    public func tangent(atProgress t: Double) -> Vector2D {
        guard points.count > 1 else { return Vector2D(dx: 1, dy: 0) }
        let epsilon = 0.01
        let a = point(atProgress: max(0, t - epsilon))
        let b = point(atProgress: min(1, t + epsilon))
        let vector = b - a
        return vector.length > 1e-9 ? vector.normalized : Vector2D(dx: 1, dy: 0)
    }
}

/// 把 `MovementSpec` + 已解析的起终点 变成可绘制路径。
///
/// 全部运算先在**脸部局部坐标系**里完成，最后一步才映射到视图坐标 ——
/// 这样路径形状对距离、脸型和头部倾斜天然不变。
public struct PathSampler: Sendable {

    public static let defaultSampleCount = 72

    public init() {}

    public func makePath(
        movement: MovementSpec,
        start: Point2D,
        end: Point2D?,
        frame: FaceFrame,
        sampleCount: Int = PathSampler.defaultSampleCount
    ) -> MotionPath {
        let startLocal = frame.toLocal(view: start)
        let endLocal = end.map { frame.toLocal(view: $0) }
        let samples = max(2, sampleCount)

        switch movement.pathType {
        case .press, .hold:
            return MotionPath(kind: movement.pathType, points: [start])

        case .expression:
            // 表情肌动作没有手部接触 —— 脸上没有任何轨迹可画。
            // 返回空路径而不是伪造一个点：AR 模式下这一段本来就该退化为
            // 「提示 + 计时」，画个假光点会让人以为要用手去碰那个位置。
            return MotionPath(kind: .expression, points: [])

        case .tap:
            // 轻拍跨多个区域，没有单一轨迹。
            // 每个区域各自成为一个 overlay（见 ARGuidanceController），
            // 这里只负责单个区域的标记点。
            return MotionPath(kind: .tap, points: [start])

        case .line:
            guard let endLocal else { return MotionPath(kind: .press, points: [start]) }
            let localPoints = sampleLine(from: startLocal, to: endLocal, count: samples)
            return MotionPath(kind: .line, points: localPoints.map { frame.toView(local: $0) })

        case .curve:
            guard let endLocal else { return MotionPath(kind: .press, points: [start]) }
            let localPoints = sampleCurve(
                from: startLocal,
                to: endLocal,
                controls: movement.pathGeometry.controlOffsets,
                count: samples
            )
            return MotionPath(kind: .curve, points: localPoints.map { frame.toView(local: $0) })

        case .arc:
            guard let endLocal else { return MotionPath(kind: .press, points: [start]) }
            let sagitta = movement.pathGeometry.controlOffsets.first?.perpendicular ?? 0.15
            let result = sampleArc(from: startLocal, to: endLocal, sagitta: sagitta, count: samples)
            return MotionPath(
                kind: .arc,
                points: result.points.map { frame.toView(local: $0) },
                center: result.center.map { frame.toView(local: $0) }
            )

        case .circle:
            let radius = movement.pathGeometry.radius ?? 0.35
            let sweep = movement.pathGeometry.sweepDegrees ?? 360
            let localPoints = sampleCircle(
                center: startLocal,
                radius: radius,
                sweepDegrees: sweep,
                clockwise: movement.pathGeometry.clockwise,
                count: samples
            )
            return MotionPath(
                kind: .circle,
                points: localPoints.map { frame.toView(local: $0) },
                center: frame.toView(local: startLocal),
                isClosed: abs(sweep) >= 359.5
            )
        }
    }

    // MARK: - 局部坐标采样

    func sampleLine(from a: Point2D, to b: Point2D, count: Int) -> [Point2D] {
        (0..<count).map { index in
            a.lerp(to: b, t: Double(index) / Double(count - 1))
        }
    }

    /// 控制点表达在 start→end 的局部框架里：
    /// `along` 沿轴向比例，`perpendicular` 垂直偏移（归一化单位）。
    /// 1 个控制点 → 二次贝塞尔；2 个 → 三次；0 个 → 退化为直线。
    func sampleCurve(
        from a: Point2D,
        to b: Point2D,
        controls: [PathControlOffset],
        count: Int
    ) -> [Point2D] {
        let axis = b - a
        let length = axis.length
        guard length > 1e-9, controls.isEmpty == false else {
            return sampleLine(from: a, to: b, count: count)
        }
        let unit = axis.normalized
        let normal = unit.rotatedClockwise90

        func controlPoint(_ offset: PathControlOffset) -> Point2D {
            a + (unit * (offset.along * length)) + (normal * offset.perpendicular)
        }

        if controls.count == 1 {
            let c = controlPoint(controls[0])
            return (0..<count).map { index in
                quadraticBezier(a, c, b, t: Double(index) / Double(count - 1))
            }
        }
        let c1 = controlPoint(controls[0])
        let c2 = controlPoint(controls[1])
        return (0..<count).map { index in
            cubicBezier(a, c1, c2, b, t: Double(index) / Double(count - 1))
        }
    }

    /// 经过 (start, 弦中点抬起 sagitta, end) 三点的真实圆弧。
    /// 三点共线时退化为直线。
    func sampleArc(
        from a: Point2D,
        to b: Point2D,
        sagitta: Double,
        count: Int
    ) -> (points: [Point2D], center: Point2D?) {
        let axis = b - a
        let length = axis.length
        guard length > 1e-9, abs(sagitta) > 1e-6 else {
            return (sampleLine(from: a, to: b, count: count), nil)
        }
        let normal = axis.normalized.rotatedClockwise90
        let mid = a.lerp(to: b, t: 0.5) + (normal * sagitta)

        guard let center = circumcenter(a, mid, b) else {
            return (sampleLine(from: a, to: b, count: count), nil)
        }
        let radius = center.distance(to: a)
        let angleA = (a - center).angle
        let angleMid = (mid - center).angle
        let angleB = (b - center).angle

        // 选择经过 mid 的那条弧。
        var sweep = normalizeAngle(angleB - angleA)
        let sweepToMid = normalizeAngle(angleMid - angleA)
        if sweepToMid > sweep { sweep -= 2 * Double.pi }

        let points = (0..<count).map { index -> Point2D in
            let t = Double(index) / Double(count - 1)
            let angle = angleA + sweep * t
            return Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        return (points, center)
    }

    func sampleCircle(
        center: Point2D,
        radius: Double,
        sweepDegrees: Double,
        clockwise: Bool,
        count: Int
    ) -> [Point2D] {
        let sweep = sweepDegrees * Double.pi / 180 * (clockwise ? 1 : -1)
        // 从脸的正上方起笔，动作看起来最自然。
        let startAngle = -Double.pi / 2
        return (0..<count).map { index -> Point2D in
            let t = Double(index) / Double(count - 1)
            let angle = startAngle + sweep * t
            return Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    // MARK: - 数学helpers

    func quadraticBezier(_ p0: Point2D, _ p1: Point2D, _ p2: Point2D, t: Double) -> Point2D {
        let mt = 1 - t
        let x = mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x
        let y = mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        return Point2D(x: x, y: y)
    }

    func cubicBezier(_ p0: Point2D, _ p1: Point2D, _ p2: Point2D, _ p3: Point2D, t: Double) -> Point2D {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return Point2D(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    func circumcenter(_ a: Point2D, _ b: Point2D, _ c: Point2D) -> Point2D? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-9 else { return nil }
        let sa = a.x * a.x + a.y * a.y
        let sb = b.x * b.x + b.y * b.y
        let sc = c.x * c.x + c.y * c.y
        let ux = (sa * (b.y - c.y) + sb * (c.y - a.y) + sc * (a.y - b.y)) / d
        let uy = (sa * (c.x - b.x) + sb * (a.x - c.x) + sc * (b.x - a.x)) / d
        return Point2D(x: ux, y: uy)
    }

    /// 归一化到 [0, 2π)。
    func normalizeAngle(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: 2 * Double.pi)
        if result < 0 { result += 2 * Double.pi }
        return result
    }
}
