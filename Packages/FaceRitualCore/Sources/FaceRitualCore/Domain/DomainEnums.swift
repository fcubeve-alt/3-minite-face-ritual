import Foundation

public enum RoutineType: String, Codable, Sendable, CaseIterable {
    case morning
    case evening
    case quick
}

/// 解剖学左右（用户自己的左右），**不是**屏幕左右。
/// 屏幕侧由 `FaceGeometry.isMirrored` 决定，业务层不关心。
public enum BodySide: String, Codable, Sendable, CaseIterable {
    case none
    case left
    case right
    case both
    /// 播放时展开成 left → right 两段（见 `PlaybackPlan`）。
    case leftThenRight
}

public enum PathType: String, Codable, Sendable, CaseIterable {
    case line
    case curve
    case arc
    case circle
    case press
    case hold
}

public enum MovementDirection: String, Codable, Sendable, CaseIterable {
    case none
    case upward
    case downward
    case inward
    case outward
    case clockwise
    case counterClockwise
}

public enum GestureHint: String, Codable, Sendable, CaseIterable {
    case none
    case singleFinger
    case twoFinger
    case fingertips
    case palm
    case tool
}

/// 规格 §10：只有逐个动作验证达标的才可能升到 experimental，MVP 全部 guidanceOnly。
public enum TrackingSupport: String, Codable, Sendable, CaseIterable {
    case none
    case guidanceOnly
    case observableCorrectionExperimental
}

/// 规格 §4「识别失败不得阻塞 routine」。
public enum OcclusionPolicy: String, Codable, Sendable, CaseIterable {
    /// 继续计时与语音，overlay 冻结在最后可信位置。手遮脸时的默认选择。
    case continueGuidance
    /// 冻结 overlay，但仍然计时。
    case freezeOverlay
    /// 暂停脸部跟踪更新（不暂停 routine）。
    case pauseTracking
}

/// 内容审核状态。Mock 内容永远不可能被误当成正式内容发布。
public enum ContentReviewStatus: String, Codable, Sendable, CaseIterable {
    case mockUnreviewed = "mock_unreviewed"
    case draft
    case expertReviewed = "expert_reviewed"

    public var isPublishable: Bool { self == .expertReviewed }
}
