import Foundation

/// Provider 中立的语义 landmark 集合。
///
/// **这是「业务层不绑定 HRFFA」的关键类型。**
/// 每个 provider（Vision / HRFFA / ARKit / Mock）负责把自己的原生编号映射到这里；
/// Core 与所有内容 JSON 只认这些名字，永远看不到 68 点索引或 1220 顶点号。
///
/// 左右一律为**解剖学**左右（用户自己的左右），与屏幕镜像无关。
public enum SemanticLandmark: String, Codable, Sendable, CaseIterable {
    // 眼
    case leftEyeOuter, leftEyeInner, leftEyeUpper, leftEyeLower, leftEyeCenter
    case rightEyeOuter, rightEyeInner, rightEyeUpper, rightEyeLower, rightEyeCenter
    // 眉
    case leftBrowInner, leftBrowOuter, leftBrowPeak
    case rightBrowInner, rightBrowOuter, rightBrowPeak
    case glabella          // 眉心
    // 鼻
    case noseBridgeTop, noseBridgeMid, noseTip, subnasale
    case leftNoseAla, rightNoseAla
    // 口
    case mouthLeftCorner, mouthRightCorner, upperLipCenter, lowerLipCenter
    // 轮廓
    case chinCenter, leftJawAngle, rightJawAngle
    case leftCheekbone, rightCheekbone
    case leftTemple, rightTemple
    case foreheadCenter

    /// 该点属于哪一侧；用于 anchor 的左右镜像。
    public var side: BodySide {
        let name = rawValue
        if name.hasPrefix("left") { return .left }
        if name.hasPrefix("right") { return .right }
        return .none
    }

    /// 对侧对应点。中线点（如 glabella）返回自身。
    public var mirrored: SemanticLandmark {
        let name = rawValue
        if name.hasPrefix("left") {
            let suffix = String(name.dropFirst(4))
            return SemanticLandmark(rawValue: "right" + suffix) ?? self
        }
        if name.hasPrefix("right") {
            let suffix = String(name.dropFirst(5))
            return SemanticLandmark(rawValue: "left" + suffix) ?? self
        }
        return self
    }

    /// FaceFrame 与置信度评估所必需的最小集合。
    /// Provider 若无法提供全部，`FaceGeometry.isUsable` 为 false，AR 停留在 acquiring。
    public static let required: [SemanticLandmark] = [
        .leftEyeCenter, .rightEyeCenter, .noseTip, .chinCenter
    ]
}

public struct LandmarkSample: Hashable, Codable, Sendable {
    /// **视图坐标**（points，原点左上）。投影由 provider 完成，Core 不做 3D。
    public var point: Point2D
    public var confidence: Double
    /// Provider 的遮挡猜测。缺省 false —— 我们不假装能看穿手指。
    public var isOccluded: Bool

    public init(point: Point2D, confidence: Double = 1.0, isOccluded: Bool = false) {
        self.point = point
        self.confidence = confidence
        self.isOccluded = isOccluded
    }
}

public struct HeadPose: Hashable, Codable, Sendable {
    public var yawDegrees: Double
    public var pitchDegrees: Double
    public var rollDegrees: Double

    public init(yawDegrees: Double = 0, pitchDegrees: Double = 0, rollDegrees: Double = 0) {
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
        self.rollDegrees = rollDegrees
    }

    public static let neutral = HeadPose()

    public var maxAbsoluteAngle: Double {
        max(abs(yawDegrees), max(abs(pitchDegrees), abs(rollDegrees)))
    }
}

public enum FaceTrackingState: String, Codable, Sendable {
    case notDetected
    case acquiring
    case locked
    case degraded
}
