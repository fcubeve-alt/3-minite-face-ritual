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
    /// 表情肌动作，**没有手部接触**，因此没有路径可画。
    /// Sprint 3 里的 GM-01 呼吸、GM-09 鼓气、GM-10 元音、GM-16 噘嘴都属于这类。
    /// AR 模式下只显示提示与计时，可选地高亮 `focusAnchors` 指定的区域。
    case expression
    /// 轻拍。跨多个区域、没有单一轨迹（GM-15 全脸轻拍）。
    /// 用 `focusAnchors` 列出要点到的区域。
    case tap

    /// 是否需要在脸上画一条轨迹。
    public var drawsPath: Bool {
        switch self {
        case .line, .curve, .arc, .circle: return true
        case .press, .hold, .expression, .tap: return false
        }
    }

    /// 是否需要 startAnchor。表情动作没有接触点，可以没有。
    public var requiresStartAnchor: Bool {
        self != .expression
    }
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
