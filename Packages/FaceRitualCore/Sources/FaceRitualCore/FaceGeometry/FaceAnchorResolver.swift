import Foundation

/// 解析后的 anchor —— 同时给出视图坐标与脸部局部坐标。
public struct ResolvedAnchor: Hashable, Sendable {
    public let id: FaceAnchorID
    public let side: BodySide
    /// 视图坐标（points），可直接绘制。
    public let viewPoint: Point2D
    /// 脸部局部坐标（归一化单位），用于路径运算。
    public let localPoint: Point2D
    /// 由所引用 landmark 的最低置信度决定。
    public let confidence: Double
    /// 头部姿态是否仍在该 anchor 的适用范围内。
    public let isWithinPoseConstraints: Bool
    /// 容差半径，已换算成视图像素。
    public let toleranceRadiusPoints: Double
    /// 所引用 landmark 中是否有被 provider 判定为遮挡的。
    public let hasOccludedReference: Bool

    /// 是否达到显示门槛。注意：这**不是**「用户做对了」的判断（规格 §10）。
    public var meetsDisplayThreshold: Bool {
        isWithinPoseConstraints && confidence > 0
    }
}

public enum AnchorResolutionError: Error, Equatable {
    case missingLandmark(SemanticLandmark)
    case emptyWeightedRule
}

/// 规则求值器。纯函数，可完整单元测试（见 golden vector 测试）。
public struct FaceAnchorResolver: Sendable {

    public init() {}

    public func resolve(
        _ anchor: FaceAnchor,
        geometry: FaceGeometry,
        frame: FaceFrame
    ) -> Result<ResolvedAnchor, AnchorResolutionError> {
        let viewPoint: Point2D
        do {
            viewPoint = try evaluate(anchor.rule, geometry: geometry, frame: frame)
        } catch let error as AnchorResolutionError {
            return .failure(error)
        } catch {
            return .failure(.emptyWeightedRule)
        }

        let referenced = anchor.rule.referencedLandmarks
        var minConfidence = 1.0
        var occluded = false
        for mark in referenced {
            guard let sample = geometry.landmarks[mark] else {
                return .failure(.missingLandmark(mark))
            }
            minConfidence = min(minConfidence, sample.confidence)
            if sample.isOccluded { occluded = true }
        }
        if referenced.isEmpty { minConfidence = 0 }

        let resolved = ResolvedAnchor(
            id: anchor.id,
            side: anchor.side,
            viewPoint: viewPoint,
            localPoint: frame.toLocal(view: viewPoint),
            confidence: minConfidence,
            isWithinPoseConstraints: anchor.poseConstraints.allows(geometry.pose),
            toleranceRadiusPoints: frame.toViewLength(anchor.toleranceRadius),
            hasOccludedReference: occluded
        )
        return .success(resolved)
    }

    /// 求值到**视图坐标**。
    func evaluate(
        _ rule: AnchorGeometryRule,
        geometry: FaceGeometry,
        frame: FaceFrame
    ) throws -> Point2D {
        switch rule {
        case let .landmark(mark):
            guard let sample = geometry.landmarks[mark] else {
                throw AnchorResolutionError.missingLandmark(mark)
            }
            return sample.point

        case let .midpoint(a, b):
            let pa = try evaluate(a, geometry: geometry, frame: frame)
            let pb = try evaluate(b, geometry: geometry, frame: frame)
            return pa.lerp(to: pb, t: 0.5)

        case let .lerp(from, to, t):
            let pa = try evaluate(from, geometry: geometry, frame: frame)
            let pb = try evaluate(to, geometry: geometry, frame: frame)
            return pa.lerp(to: pb, t: clamp(t, 0, 1))

        case let .weighted(items):
            guard items.isEmpty == false else { throw AnchorResolutionError.emptyWeightedRule }
            var totalWeight = 0.0
            for item in items { totalWeight += item.weight }
            guard abs(totalWeight) > 1e-9 else { throw AnchorResolutionError.emptyWeightedRule }
            var x = 0.0
            var y = 0.0
            for item in items {
                guard let sample = geometry.landmarks[item.landmark] else {
                    throw AnchorResolutionError.missingLandmark(item.landmark)
                }
                let w = item.weight / totalWeight
                x += sample.point.x * w
                y += sample.point.y * w
            }
            return Point2D(x: x, y: y)

        case let .offset(base, dx, dy):
            let basePoint = try evaluate(base, geometry: geometry, frame: frame)
            // dx > 0 朝用户的右侧 —— xAxis 由「左眼 → 右眼」定义，天然满足。
            let displacement = frame.toViewDirection(local: Vector2D(dx: dx, dy: dy)) * frame.scale
            return basePoint + displacement
        }
    }
}
