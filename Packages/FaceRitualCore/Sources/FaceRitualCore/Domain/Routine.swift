import Foundation

/// 规格 §16。一个 RoutineStep 同时承载 Coach 媒体与 AR MovementSpec —— 单一动作真源。
public struct RoutineStep: Hashable, Codable, Sendable, Identifiable {
    public var id: RoutineStepID
    public var title: String
    /// Coach 模式的媒体资源名（视频/动画/Lottie）。M1 阶段为占位资源。
    public var mediaAsset: String?
    public var durationSeconds: Double
    public var side: BodySide
    /// 屏幕上的一行短提示。
    public var shortCue: String
    public var voiceCue: String?
    public var hapticCue: String?
    public var movement: MovementSpec
    public var safetyNote: String?
    public var evidenceRef: String?
    /// 这一步是从动作库里的哪个 Gold Move 展开来的。
    ///
    /// 存在的理由是校验：力度、工具要求、允许的 routine 类型这些约束长在
    /// `GoldMove` 上，而校验器拿到的是展开后的 `Routine`。
    /// 没有这个字段就只能去解析 step id 的字符串前缀 —— 一改命名规则就静默失效。
    public var sourceMoveID: GoldMoveID?
    public var reviewStatus: ContentReviewStatus
    public var version: String

    public init(
        id: RoutineStepID,
        title: String,
        mediaAsset: String? = nil,
        durationSeconds: Double,
        side: BodySide = .none,
        shortCue: String,
        voiceCue: String? = nil,
        hapticCue: String? = nil,
        movement: MovementSpec = MovementSpec(),
        safetyNote: String? = nil,
        evidenceRef: String? = nil,
        sourceMoveID: GoldMoveID? = nil,
        reviewStatus: ContentReviewStatus = .mockUnreviewed,
        version: String = "0.0.1-mock"
    ) {
        self.id = id
        self.title = title
        self.mediaAsset = mediaAsset
        self.durationSeconds = durationSeconds
        self.side = side
        self.shortCue = shortCue
        self.voiceCue = voiceCue
        self.hapticCue = hapticCue
        self.movement = movement
        self.safetyNote = safetyNote
        self.evidenceRef = evidenceRef
        self.sourceMoveID = sourceMoveID
        self.reviewStatus = reviewStatus
        self.version = version
    }
}

public struct Routine: Hashable, Codable, Sendable, Identifiable {
    public var id: RoutineID
    public var title: String
    public var subtitle: String?
    public var type: RoutineType
    public var isPremium: Bool
    public var steps: [RoutineStep]
    public var safetyNote: String?
    public var reviewStatus: ContentReviewStatus
    public var version: String

    public init(
        id: RoutineID,
        title: String,
        subtitle: String? = nil,
        type: RoutineType,
        isPremium: Bool,
        steps: [RoutineStep],
        safetyNote: String? = nil,
        reviewStatus: ContentReviewStatus = .mockUnreviewed,
        version: String = "0.0.1-mock"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.isPremium = isPremium
        self.steps = steps
        self.safetyNote = safetyNote
        self.reviewStatus = reviewStatus
        self.version = version
    }

    /// 实际总时长由 steps 求和得出 —— 不信任任何声明字段，避免 UI 与播放器不一致。
    public var totalDurationSeconds: Double {
        steps.reduce(0) { $0 + $1.durationSeconds }
    }

    public var formattedDuration: String {
        let total = Int(totalDurationSeconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public var usesARGuidance: Bool {
        steps.contains { $0.movement.isARRenderable }
    }
}

/// 内容包元信息，随 JSON 一起版本化。
public struct ContentMeta: Hashable, Codable, Sendable {
    public var schemaVersion: Int
    public var contentVersion: String
    public var reviewStatus: ContentReviewStatus
    public var note: String?

    public init(schemaVersion: Int, contentVersion: String, reviewStatus: ContentReviewStatus, note: String? = nil) {
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.reviewStatus = reviewStatus
        self.note = note
    }
}

/// 当前 JSON schema 版本。解码时不匹配即报错，防止旧内容包静默错配。
///
/// v2（Sprint 3 v0.3 + Video Factory v0.2）：
/// - 新增 `moves.json`（Gold Motion Library），routine 改为引用动作而非内联
/// - MovementSpec 增加 `expression` / `tap` 两种 pathType 与 `focusAnchors`
/// - GoldMove 携带力度、工具要求、证据等级、停止信号与中文原文溯源
public enum ContentSchema {
    public static let currentVersion = 2
}
