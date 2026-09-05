import Foundation

/// 规格 §8：目标位置**必须**相对用户自己的 landmarks 与脸部比例计算，
/// 不得写成固定屏幕像素。本类型就是那条规则的载体。
///
/// 第一阶段只建 3–5 个测试 anchor，目的不是医学准确性，
/// 而是验证「不同用户脸上目标位置能否稳定跟随 Face Geometry」。
/// 正式穴位定义由 Owner + 专业资料审核后替换 `anchors.json`，代码无需改动。
public struct FaceAnchor: Hashable, Codable, Sendable, Identifiable {
    public var id: FaceAnchorID
    public var name: String
    /// 解剖学左右。`.left` / `.right` 的 anchor 可通过 `mirroredToOppositeSide()` 自动生成对侧。
    public var side: BodySide
    public var rule: AnchorGeometryRule
    /// 允许误差半径，单位为瞳距（归一化）。用于 overlay 的容差圈显示。
    public var toleranceRadius: Double
    public var poseConstraints: PoseConstraints
    /// 低于该置信度不显示该 anchor。
    public var confidenceThreshold: Double
    public var evidenceRef: String?
    public var safetyNote: String?
    public var reviewStatus: ContentReviewStatus
    public var version: String

    public init(
        id: FaceAnchorID,
        name: String,
        side: BodySide = .none,
        rule: AnchorGeometryRule,
        toleranceRadius: Double = 0.12,
        poseConstraints: PoseConstraints = .default,
        confidenceThreshold: Double = 0.5,
        evidenceRef: String? = nil,
        safetyNote: String? = nil,
        reviewStatus: ContentReviewStatus = .mockUnreviewed,
        version: String = "0.0.1-mock"
    ) {
        self.id = id
        self.name = name
        self.side = side
        self.rule = rule
        self.toleranceRadius = toleranceRadius
        self.poseConstraints = poseConstraints
        self.confidenceThreshold = confidenceThreshold
        self.evidenceRef = evidenceRef
        self.safetyNote = safetyNote
        self.reviewStatus = reviewStatus
        self.version = version
    }

    /// 生成镜像 anchor（left ⇄ right），ID 后缀替换。
    /// 内容作者只写一侧，另一侧由系统推导，避免两侧定义漂移。
    public func mirroredToOppositeSide() -> FaceAnchor? {
        let oppositeSide: BodySide
        switch side {
        case .left: oppositeSide = .right
        case .right: oppositeSide = .left
        default: return nil
        }
        var copy = self
        copy.side = oppositeSide
        copy.rule = rule.mirrored()
        copy.id = FaceAnchorID(rawValue: FaceAnchor.mirroredIdentifier(id.rawValue))
        copy.name = FaceAnchor.mirroredIdentifier(name)
        return copy
    }

    static func mirroredIdentifier(_ raw: String) -> String {
        if raw.contains("left") { return raw.replacingOccurrences(of: "left", with: "right") }
        if raw.contains("right") { return raw.replacingOccurrences(of: "right", with: "left") }
        if raw.contains("Left") { return raw.replacingOccurrences(of: "Left", with: "Right") }
        if raw.contains("Right") { return raw.replacingOccurrences(of: "Right", with: "Left") }
        return raw
    }
}

/// 姿态适用范围。超出即认为该 anchor 当前不可靠（规格 §8「适用姿态」）。
public struct PoseConstraints: Hashable, Codable, Sendable {
    public var maxYawDegrees: Double
    public var maxPitchDegrees: Double
    public var maxRollDegrees: Double

    public init(maxYawDegrees: Double = 25, maxPitchDegrees: Double = 25, maxRollDegrees: Double = 30) {
        self.maxYawDegrees = maxYawDegrees
        self.maxPitchDegrees = maxPitchDegrees
        self.maxRollDegrees = maxRollDegrees
    }

    public static let `default` = PoseConstraints()

    public func allows(_ pose: HeadPose) -> Bool {
        abs(pose.yawDegrees) <= maxYawDegrees
            && abs(pose.pitchDegrees) <= maxPitchDegrees
            && abs(pose.rollDegrees) <= maxRollDegrees
    }
}

public struct WeightedLandmark: Hashable, Codable, Sendable {
    public var landmark: SemanticLandmark
    public var weight: Double

    public init(landmark: SemanticLandmark, weight: Double) {
        self.landmark = landmark
        self.weight = weight
    }
}

/// 几何规则 —— 组合式，可嵌套。
/// JSON 形态是人工可读可写的（带 `type` 判别字段），因为 Owner 与专业人员会直接编辑它。
public indirect enum AnchorGeometryRule: Hashable, Sendable {
    /// 直接取某个语义 landmark。
    case landmark(SemanticLandmark)
    /// 两个规则的中点。
    case midpoint(AnchorGeometryRule, AnchorGeometryRule)
    /// 线性插值，t ∈ [0, 1]。
    case lerp(from: AnchorGeometryRule, to: AnchorGeometryRule, t: Double)
    /// 加权平均（重心坐标）。权重自动归一化。
    case weighted([WeightedLandmark])
    /// 在 FaceFrame 局部坐标系中相对某个基准偏移，单位为瞳距。
    /// dx > 0 朝用户的右侧，dy > 0 朝脸的下方。
    case offset(base: AnchorGeometryRule, dx: Double, dy: Double)

    /// 左右镜像：所有 landmark 换成对侧，dx 取反。
    public func mirrored() -> AnchorGeometryRule {
        switch self {
        case let .landmark(mark):
            return .landmark(mark.mirrored)
        case let .midpoint(a, b):
            return .midpoint(a.mirrored(), b.mirrored())
        case let .lerp(from, to, t):
            return .lerp(from: from.mirrored(), to: to.mirrored(), t: t)
        case let .weighted(items):
            return .weighted(items.map { WeightedLandmark(landmark: $0.landmark.mirrored, weight: $0.weight) })
        case let .offset(base, dx, dy):
            return .offset(base: base.mirrored(), dx: -dx, dy: dy)
        }
    }

    /// 该规则引用到的全部 landmark，用于置信度评估与内容校验。
    public var referencedLandmarks: Set<SemanticLandmark> {
        switch self {
        case let .landmark(mark):
            return [mark]
        case let .midpoint(a, b):
            return a.referencedLandmarks.union(b.referencedLandmarks)
        case let .lerp(from, to, _):
            return from.referencedLandmarks.union(to.referencedLandmarks)
        case let .weighted(items):
            return Set(items.map(\.landmark))
        case let .offset(base, _, _):
            return base.referencedLandmarks
        }
    }
}

// MARK: - 人工可读的 JSON 编解码

extension AnchorGeometryRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, a, b, from, to, t, items, base, dx, dy
    }

    private enum Kind: String, Codable {
        case landmark, midpoint, lerp, weighted, offset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .landmark:
            self = .landmark(try container.decode(SemanticLandmark.self, forKey: .id))
        case .midpoint:
            self = .midpoint(
                try container.decode(AnchorGeometryRule.self, forKey: .a),
                try container.decode(AnchorGeometryRule.self, forKey: .b)
            )
        case .lerp:
            self = .lerp(
                from: try container.decode(AnchorGeometryRule.self, forKey: .from),
                to: try container.decode(AnchorGeometryRule.self, forKey: .to),
                t: try container.decode(Double.self, forKey: .t)
            )
        case .weighted:
            self = .weighted(try container.decode([WeightedLandmark].self, forKey: .items))
        case .offset:
            self = .offset(
                base: try container.decode(AnchorGeometryRule.self, forKey: .base),
                dx: try container.decodeIfPresent(Double.self, forKey: .dx) ?? 0,
                dy: try container.decodeIfPresent(Double.self, forKey: .dy) ?? 0
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .landmark(mark):
            try container.encode(Kind.landmark, forKey: .type)
            try container.encode(mark, forKey: .id)
        case let .midpoint(a, b):
            try container.encode(Kind.midpoint, forKey: .type)
            try container.encode(a, forKey: .a)
            try container.encode(b, forKey: .b)
        case let .lerp(from, to, t):
            try container.encode(Kind.lerp, forKey: .type)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(t, forKey: .t)
        case let .weighted(items):
            try container.encode(Kind.weighted, forKey: .type)
            try container.encode(items, forKey: .items)
        case let .offset(base, dx, dy):
            try container.encode(Kind.offset, forKey: .type)
            try container.encode(base, forKey: .base)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        }
    }
}
