import Foundation

public struct GoldMoveID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// 动作力度。来自 Sprint 3 §2「默认力度：Light / Gentle。除明确的肌肉等长动作外，不追求深压」。
public enum MovementIntensity: String, Codable, Sendable, CaseIterable {
    /// 无手部压力（表情肌动作、呼吸）
    case none
    case veryLight
    case light
    /// 轻至中轻，不造成明显变形（掌根 effleurage）
    case lightToModerate
}

/// 是否需要工具。
///
/// Sprint 3 §9 明确：Gua Sha / Roller **不得**作为免费核心操的必要条件。
/// 校验器会拦截「工具动作出现在 morning routine」。
public enum ToolRequirement: String, Codable, Sendable, CaseIterable {
    case none
    case facialRoller
    case guaSha

    public var isTool: Bool { self != .none }
}

/// 证据等级。
///
/// Sprint 3 §1：「不把研究中出现过的动作等同于已被单独证明有效；证据只决定优先级与风险边界。」
/// 所以这个字段**只用于排序与风险判断**，不得用于任何对外功效表述。
public enum EvidenceLevel: String, Codable, Sendable, CaseIterable {
    /// 传统/专业实践成熟，但缺少直接研究
    case classicPractice
    /// 有相近方向的研究，但徒手应用属间接证据
    case indirect
    /// 出现在已发表的整套方案里，方案级结果，单动作效应未知
    case protocolLevel
    /// 有随机对照试验（样本仍小）
    case randomisedTrial
    /// 辅助/仪式性动作，不以外观为目的
    case supportive
}

/// 目标区域。用于覆盖度检查与营销主题匹配（文档二 §4）。
public enum FaceRegion: String, Codable, Sendable, CaseIterable {
    case wholeFace
    case forehead
    case glabella
    case temple
    case eyeArea
    case midface
    case cheek
    case perioral
    case jawline
    case neck
}

/// 专业文档原文。**逐字保留中文，不做翻译。**
///
/// 为什么保留原文：安全相关的措辞（禁忌、停止信号、力度）经翻译会引入偏差，
/// 而 Expert Gate 审的就是这些。用户看到的是英文字段，专家审的是这里的原文，
/// 两者并存，谁也不覆盖谁。
public struct GoldMoveSource: Codable, Hashable, Sendable {
    /// 出处，例如 "Sprint 3 v0.3 · GM-02"
    public var documentRef: String
    public var titleZh: String
    public var evidenceZh: String?
    public var startingPositionZh: String?
    public var instructionZh: String?
    public var durationZh: String?
    public var intensityZh: String?
    public var stopSignalsZh: String?
    public var usageZh: String?
    public var researchNoteZh: String?

    public init(
        documentRef: String,
        titleZh: String,
        evidenceZh: String? = nil,
        startingPositionZh: String? = nil,
        instructionZh: String? = nil,
        durationZh: String? = nil,
        intensityZh: String? = nil,
        stopSignalsZh: String? = nil,
        usageZh: String? = nil,
        researchNoteZh: String? = nil
    ) {
        self.documentRef = documentRef
        self.titleZh = titleZh
        self.evidenceZh = evidenceZh
        self.startingPositionZh = startingPositionZh
        self.instructionZh = instructionZh
        self.durationZh = durationZh
        self.intensityZh = intensityZh
        self.stopSignalsZh = stopSignalsZh
        self.usageZh = usageZh
        self.researchNoteZh = researchNoteZh
    }
}

/// Gold Motion Library 的一条动作（文档二 §4）。
///
/// **动作是资产，routine 只是时间线。**
/// 同一个动作会在多个 routine 里出现（Prototype A 里 GM-11 出现两次，
/// GM-02 三套原型都用），内联会产生重复与漂移。
///
/// 文档二 §2 的第一条不可破坏原则：
/// 「教学动作的唯一真源必须是经过 Evidence Engine + Expert Gate 审核的 Gold Move」。
/// 这个类型就是那个真源；Coach 视频、AR 模板、营销素材都从这里派生。
public struct GoldMove: Codable, Hashable, Sendable, Identifiable {
    public var id: GoldMoveID

    // MARK: 用户可见（英文）
    public var title: String
    public var shortCue: String
    public var voiceCue: String?
    /// ⚠️ 这是专业文档「停止/禁忌信号」的英文表述，属**翻译**。
    /// Expert Gate 必须对照 `source.stopSignalsZh` 复核。
    public var safetyNote: String?

    // MARK: 分类与安全
    public var region: FaceRegion
    public var defaultDurationSeconds: Double
    public var side: BodySide
    public var intensity: MovementIntensity
    public var requiresTool: ToolRequirement
    public var evidenceLevel: EvidenceLevel
    /// 允许出现在哪些 routine 类型里（文档二 §4「允许使用的 Routine」）。
    public var allowedRoutineTypes: [RoutineType]

    // MARK: AR
    public var movement: MovementSpec

    // MARK: 溯源
    public var source: GoldMoveSource
    public var reviewStatus: ContentReviewStatus
    public var version: String

    public init(
        id: GoldMoveID,
        title: String,
        shortCue: String,
        voiceCue: String? = nil,
        safetyNote: String? = nil,
        region: FaceRegion,
        defaultDurationSeconds: Double,
        side: BodySide = .none,
        intensity: MovementIntensity = .light,
        requiresTool: ToolRequirement = .none,
        evidenceLevel: EvidenceLevel = .classicPractice,
        allowedRoutineTypes: [RoutineType] = [.morning, .evening, .quick],
        movement: MovementSpec = MovementSpec(),
        source: GoldMoveSource,
        reviewStatus: ContentReviewStatus = .draft,
        version: String = "0.3.0-draft"
    ) {
        self.id = id
        self.title = title
        self.shortCue = shortCue
        self.voiceCue = voiceCue
        self.safetyNote = safetyNote
        self.region = region
        self.defaultDurationSeconds = defaultDurationSeconds
        self.side = side
        self.intensity = intensity
        self.requiresTool = requiresTool
        self.evidenceLevel = evidenceLevel
        self.allowedRoutineTypes = allowedRoutineTypes
        self.movement = movement
        self.source = source
        self.reviewStatus = reviewStatus
        self.version = version
    }

    /// 展开成播放器要用的 RoutineStep。
    ///
    /// routine 可以覆盖时长与左右侧（Sprint 3 的原型表里同一动作在不同位置时长不同），
    /// 其余一律来自动作库 —— 保证「一个动作真源」。
    public func makeStep(
        stepID: RoutineStepID,
        durationSeconds: Double? = nil,
        side overrideSide: BodySide? = nil
    ) -> RoutineStep {
        RoutineStep(
            id: stepID,
            title: title,
            mediaAsset: "coach_" + id.rawValue.lowercased().replacingOccurrences(of: "-", with: "_"),
            durationSeconds: durationSeconds ?? defaultDurationSeconds,
            side: overrideSide ?? side,
            shortCue: shortCue,
            voiceCue: voiceCue,
            hapticCue: nil,
            movement: movement,
            safetyNote: safetyNote,
            evidenceRef: source.documentRef,
            sourceMoveID: id,
            reviewStatus: reviewStatus,
            version: version
        )
    }
}
