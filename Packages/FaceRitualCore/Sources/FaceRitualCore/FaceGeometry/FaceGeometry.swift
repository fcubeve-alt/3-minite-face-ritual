import Foundation

/// Provider 输出的中立结果。规格 §7 链路的第三环。
public struct FaceGeometry: Sendable {
    public var providerID: String
    /// 单调时钟时间戳（秒），用于测 latency 与滤波。
    public var timestamp: TimeInterval
    public var trackingState: FaceTrackingState
    public var pose: HeadPose
    public var landmarks: [SemanticLandmark: LandmarkSample]
    /// 视图坐标下的脸部包围盒。
    public var boundingBox: Rect2D
    /// 渲染视图尺寸（points）。
    public var viewSize: Size2D
    /// 预览是否水平镜像（AR Mirror 默认 true，像真镜子）。
    public var isMirrored: Bool
    public var overallConfidence: Double

    public init(
        providerID: String,
        timestamp: TimeInterval,
        trackingState: FaceTrackingState,
        pose: HeadPose = .neutral,
        landmarks: [SemanticLandmark: LandmarkSample] = [:],
        boundingBox: Rect2D = .zero,
        viewSize: Size2D = .zero,
        isMirrored: Bool = true,
        overallConfidence: Double = 0
    ) {
        self.providerID = providerID
        self.timestamp = timestamp
        self.trackingState = trackingState
        self.pose = pose
        self.landmarks = landmarks
        self.boundingBox = boundingBox
        self.viewSize = viewSize
        self.isMirrored = isMirrored
        self.overallConfidence = overallConfidence
    }

    public static func notDetected(
        providerID: String,
        timestamp: TimeInterval,
        viewSize: Size2D
    ) -> FaceGeometry {
        FaceGeometry(
            providerID: providerID,
            timestamp: timestamp,
            trackingState: .notDetected,
            viewSize: viewSize
        )
    }

    public func point(_ landmark: SemanticLandmark) -> Point2D? {
        landmarks[landmark]?.point
    }

    /// 是否具备构建 FaceFrame 的最小条件。
    public var isUsable: Bool {
        SemanticLandmark.required.allSatisfy { landmarks[$0] != nil }
    }

    /// 瞳距（points）—— 所有脸部归一化单位的基准。
    public var interocularDistance: Double {
        guard let l = point(.leftEyeCenter), let r = point(.rightEyeCenter) else { return 0 }
        return l.distance(to: r)
    }

    /// 脸在画面里的高度占比，用于「离太远 / 离太近」提示。
    public var faceHeightRatio: Double {
        guard viewSize.height > 0 else { return 0 }
        return boundingBox.size.height / viewSize.height
    }

    public var meanLandmarkConfidence: Double {
        guard landmarks.isEmpty == false else { return 0 }
        var total = 0.0
        for sample in landmarks.values { total += sample.confidence }
        return total / Double(landmarks.count)
    }

    public var occludedLandmarkRatio: Double {
        guard landmarks.isEmpty == false else { return 0 }
        var occluded = 0
        for sample in landmarks.values where sample.isOccluded { occluded += 1 }
        return Double(occluded) / Double(landmarks.count)
    }
}
