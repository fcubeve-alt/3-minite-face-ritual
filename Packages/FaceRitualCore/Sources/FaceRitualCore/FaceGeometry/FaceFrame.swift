import Foundation

/// 脸部局部坐标系。ARCHITECTURE.md §2 的核心。
///
/// - origin  = 双眼中点
/// - xAxis   = 左眼 → 右眼 的单位向量（自动吸收 roll）
/// - yAxis   = xAxis 顺时针 90°（脸的「下方」）
/// - scale   = 瞳距（points），即 1 个归一化单位
///
/// 因此同一份 anchors.json 在不同脸型 / 距离 / 头部倾斜下都成立。
/// 这正是 M1 里程碑要验证的东西。
public struct FaceFrame: Sendable, Hashable {
    public let origin: Point2D
    public let xAxis: Vector2D
    public let yAxis: Vector2D
    public let scale: Double

    public init(origin: Point2D, xAxis: Vector2D, yAxis: Vector2D, scale: Double) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.scale = scale
    }

    /// 瞳距小于该值时归一化误差被放大到不可用，直接判为无法建立坐标系。
    public static let minimumInterocularPoints: Double = 12

    /// 从 FaceGeometry 构建。缺少必需 landmark 或脸太小时返回 nil。
    public init?(geometry: FaceGeometry) {
        guard
            let leftEye = geometry.point(.leftEyeCenter),
            let rightEye = geometry.point(.rightEyeCenter)
        else { return nil }

        let interocular = leftEye.distance(to: rightEye)
        guard interocular >= FaceFrame.minimumInterocularPoints else { return nil }

        let axisX = (rightEye - leftEye).normalized
        self.origin = leftEye.lerp(to: rightEye, t: 0.5)
        self.xAxis = axisX
        self.yAxis = axisX.rotatedClockwise90
        self.scale = interocular
    }

    /// 脸部局部坐标（归一化单位）→ 视图坐标。
    public func toView(local: Point2D) -> Point2D {
        origin + (xAxis * (local.x * scale)) + (yAxis * (local.y * scale))
    }

    /// 视图坐标 → 脸部局部坐标（归一化单位）。
    public func toLocal(view point: Point2D) -> Point2D {
        let delta = point - origin
        return Point2D(
            x: (delta.dx * xAxis.dx + delta.dy * xAxis.dy) / scale,
            y: (delta.dx * yAxis.dx + delta.dy * yAxis.dy) / scale
        )
    }

    /// 归一化长度 → 视图像素长度。
    public func toViewLength(_ normalized: Double) -> Double {
        normalized * scale
    }

    /// 脸部局部方向向量 → 视图方向向量（未归一化长度）。
    public func toViewDirection(local: Vector2D) -> Vector2D {
        (xAxis * local.dx) + (yAxis * local.dy)
    }
}
