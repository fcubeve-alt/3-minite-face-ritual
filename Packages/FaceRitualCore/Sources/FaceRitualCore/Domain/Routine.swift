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
public enum ContentSchema {
    public static let currentVersion = 1
}
