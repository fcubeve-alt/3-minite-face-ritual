import Foundation

/// 规格 §10 的能力边界，落成类型。
///
/// **注意这里只有三态，没有 correct / incorrect。**
/// 领域模型中根本不存在「用户做对了没有」这个概念 ——
/// 手遮住脸时，单目摄像头看不到接触点，也测不到压力，
/// 所以我们只描述「导航还准不准」，绝不描述「你做得对不对」。
public enum GuidanceQuality: String, Sendable, Codable {
    /// 正常导航。
    case good
    /// 定位仍可用但已退化（低置信度 / 姿态偏大 / 部分遮挡）：降低不透明度 + 轻提示。
    case degraded
    /// 已失去可用定位：按 occlusionPolicy 处理，但**不中断 routine**。
    case lost
}

/// 用户可见的提示原因。文案由 App 层本地化，Core 只给语义。
public enum GuidanceHint: String, Sendable, Codable {
    case none
    case faceNotFound
    case moveCloser
    case moveFurther
    case centerFace
    case reduceHeadTurn
    case handCoveringFace
    case holdStill
}

public struct GuidanceAssessment: Sendable, Hashable {
    public let quality: GuidanceQuality
    public let hint: GuidanceHint
    /// 用于 overlay 淡入淡出，0…1。
    public let overlayOpacity: Double
    /// 是否应把 overlay 冻结在上一帧的可信位置。
    public let shouldFreezeOverlay: Bool

    public init(quality: GuidanceQuality, hint: GuidanceHint, overlayOpacity: Double, shouldFreezeOverlay: Bool) {
        self.quality = quality
        self.hint = hint
        self.overlayOpacity = overlayOpacity
        self.shouldFreezeOverlay = shouldFreezeOverlay
    }
}

public struct GuidanceThresholds: Sendable, Hashable {
    /// 脸高度占画面比例的可用区间。
    public var minFaceHeightRatio: Double
    public var maxFaceHeightRatio: Double
    /// 平均 landmark 置信度门槛。
    public var degradedConfidence: Double
    public var lostConfidence: Double
    /// 遮挡 landmark 比例门槛。
    public var degradedOcclusionRatio: Double
    public var lostOcclusionRatio: Double
    /// 头部姿态门槛（度）。
    public var degradedPoseAngle: Double
    public var lostPoseAngle: Double

    public init(
        minFaceHeightRatio: Double = 0.18,
        maxFaceHeightRatio: Double = 0.92,
        degradedConfidence: Double = 0.55,
        lostConfidence: Double = 0.30,
        degradedOcclusionRatio: Double = 0.20,
        lostOcclusionRatio: Double = 0.50,
        degradedPoseAngle: Double = 22,
        lostPoseAngle: Double = 38
    ) {
        self.minFaceHeightRatio = minFaceHeightRatio
        self.maxFaceHeightRatio = maxFaceHeightRatio
        self.degradedConfidence = degradedConfidence
        self.lostConfidence = lostConfidence
        self.degradedOcclusionRatio = degradedOcclusionRatio
        self.lostOcclusionRatio = lostOcclusionRatio
        self.degradedPoseAngle = degradedPoseAngle
        self.lostPoseAngle = lostPoseAngle
    }

    public static let `default` = GuidanceThresholds()
}

public struct GuidanceQualityEvaluator: Sendable {
    public var thresholds: GuidanceThresholds

    public init(thresholds: GuidanceThresholds = .default) {
        self.thresholds = thresholds
    }

    public func assess(
        geometry: FaceGeometry,
        frame: FaceFrame?,
        policy: OcclusionPolicy
    ) -> GuidanceAssessment {
        guard geometry.trackingState != .notDetected else {
            return GuidanceAssessment(
                quality: .lost,
                hint: .faceNotFound,
                overlayOpacity: 0,
                shouldFreezeOverlay: policy != .pauseTracking
            )
        }
        guard geometry.isUsable, frame != nil else {
            return GuidanceAssessment(
                quality: .lost,
                hint: .centerFace,
                overlayOpacity: 0,
                shouldFreezeOverlay: policy != .pauseTracking
            )
        }

        let confidence = geometry.meanLandmarkConfidence
        let occlusion = geometry.occludedLandmarkRatio
        let pose = geometry.pose.maxAbsoluteAngle
        let heightRatio = geometry.faceHeightRatio

        // 先判 lost。
        if confidence < thresholds.lostConfidence {
            return lostAssessment(hint: .holdStill, policy: policy)
        }
        if occlusion > thresholds.lostOcclusionRatio {
            return lostAssessment(hint: .handCoveringFace, policy: policy)
        }
        if pose > thresholds.lostPoseAngle {
            return lostAssessment(hint: .reduceHeadTurn, policy: policy)
        }
        if heightRatio > 0, heightRatio < thresholds.minFaceHeightRatio {
            return lostAssessment(hint: .moveCloser, policy: policy)
        }

        // 再判 degraded。
        if heightRatio > thresholds.maxFaceHeightRatio {
            return GuidanceAssessment(quality: .degraded, hint: .moveFurther, overlayOpacity: 0.55, shouldFreezeOverlay: false)
        }
        if occlusion > thresholds.degradedOcclusionRatio {
            return GuidanceAssessment(quality: .degraded, hint: .handCoveringFace, overlayOpacity: 0.6, shouldFreezeOverlay: false)
        }
        if pose > thresholds.degradedPoseAngle {
            return GuidanceAssessment(quality: .degraded, hint: .reduceHeadTurn, overlayOpacity: 0.6, shouldFreezeOverlay: false)
        }
        if confidence < thresholds.degradedConfidence {
            return GuidanceAssessment(quality: .degraded, hint: .holdStill, overlayOpacity: 0.6, shouldFreezeOverlay: false)
        }

        return GuidanceAssessment(quality: .good, hint: .none, overlayOpacity: 1.0, shouldFreezeOverlay: false)
    }

    private func lostAssessment(hint: GuidanceHint, policy: OcclusionPolicy) -> GuidanceAssessment {
        switch policy {
        case .continueGuidance:
            // 手遮脸是正常按摩动作 —— 保留最后可信 overlay，继续计时与语音。
            return GuidanceAssessment(quality: .lost, hint: hint, overlayOpacity: 0.35, shouldFreezeOverlay: true)
        case .freezeOverlay:
            return GuidanceAssessment(quality: .lost, hint: hint, overlayOpacity: 0.25, shouldFreezeOverlay: true)
        case .pauseTracking:
            return GuidanceAssessment(quality: .lost, hint: hint, overlayOpacity: 0, shouldFreezeOverlay: false)
        }
    }
}

/// Face Lock 状态机。需要连续 N 帧稳定才判定为 locked，避免闪烁。
public struct FaceLockTracker: Sendable {
    public private(set) var state: FaceTrackingState = .notDetected
    public private(set) var lockLossCount: Int = 0
    /// 首次成功 Face Lock 的耗时（秒）—— 规格 §17 的核心 AR 指标。
    public private(set) var timeToFirstLock: TimeInterval?

    private var consecutiveGoodFrames = 0
    private var consecutiveBadFrames = 0
    private var sessionStart: TimeInterval?
    private var hasLockedOnce = false

    public var requiredGoodFrames: Int
    public var requiredBadFrames: Int

    public init(requiredGoodFrames: Int = 8, requiredBadFrames: Int = 12) {
        self.requiredGoodFrames = requiredGoodFrames
        self.requiredBadFrames = requiredBadFrames
    }

    public mutating func start(at timestamp: TimeInterval) {
        sessionStart = timestamp
        state = .notDetected
        consecutiveGoodFrames = 0
        consecutiveBadFrames = 0
    }

    /// 返回 true 表示本帧发生了 locked → 非 locked 的跌落（用于上报 faceLockLost）。
    @discardableResult
    public mutating func update(assessment: GuidanceAssessment, timestamp: TimeInterval) -> Bool {
        let isGood = assessment.quality == .good
        if isGood {
            consecutiveGoodFrames += 1
            consecutiveBadFrames = 0
        } else {
            consecutiveBadFrames += 1
            consecutiveGoodFrames = 0
        }

        let previousState = state
        if consecutiveGoodFrames >= requiredGoodFrames {
            state = .locked
            if hasLockedOnce == false {
                hasLockedOnce = true
                if let start = sessionStart { timeToFirstLock = timestamp - start }
            }
        } else if consecutiveBadFrames >= requiredBadFrames {
            state = assessment.quality == .lost ? .notDetected : .degraded
        } else if state == .notDetected {
            state = .acquiring
        }

        if previousState == .locked && state != .locked {
            lockLossCount += 1
            return true
        }
        return false
    }
}
