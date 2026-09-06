import Foundation

/// 宽容解码。
///
/// 内容 JSON 会被 Owner 和专业人员**手工编辑**，所以：
/// 1. 缺省字段一律用合理默认值，而不是解码失败；
/// 2. 未来新增字段不会让旧内容包直接崩掉。
/// 编码方向保留合成实现（写出完整字段，便于 diff 审阅）。
private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

extension PathGeometry {
    enum CodingKeys: String, CodingKey {
        case controlOffsets, radius, sweepDegrees, clockwise
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            controlOffsets: try container.value(.controlOffsets, default: [PathControlOffset]()),
            radius: try container.decodeIfPresent(Double.self, forKey: .radius),
            sweepDegrees: try container.decodeIfPresent(Double.self, forKey: .sweepDegrees),
            clockwise: try container.value(.clockwise, default: true)
        )
    }
}

extension MovementSpec {
    enum CodingKeys: String, CodingKey {
        case startAnchorID = "startAnchor"
        case endAnchorID = "endAnchor"
        case pathType, pathGeometry, direction, gestureHint
        case tempoCyclesPerMinute = "tempo"
        case repetitions, holdSeconds, overlayAssets
        case focusAnchorIDs = "focusAnchors"
        case occlusionPolicy, trackingSupport, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startAnchorID: try container.decodeIfPresent(FaceAnchorID.self, forKey: .startAnchorID),
            endAnchorID: try container.decodeIfPresent(FaceAnchorID.self, forKey: .endAnchorID),
            pathType: try container.value(.pathType, default: PathType.line),
            pathGeometry: try container.value(.pathGeometry, default: PathGeometry.straight),
            direction: try container.value(.direction, default: MovementDirection.none),
            gestureHint: try container.value(.gestureHint, default: GestureHint.none),
            tempoCyclesPerMinute: try container.decodeIfPresent(Double.self, forKey: .tempoCyclesPerMinute),
            repetitions: try container.value(.repetitions, default: 1),
            holdSeconds: try container.value(.holdSeconds, default: 0),
            overlayAssets: try container.value(.overlayAssets, default: [String]()),
            focusAnchorIDs: try container.value(.focusAnchorIDs, default: [FaceAnchorID]()),
            occlusionPolicy: try container.value(.occlusionPolicy, default: OcclusionPolicy.continueGuidance),
            trackingSupport: try container.value(.trackingSupport, default: TrackingSupport.guidanceOnly),
            version: try container.value(.version, default: "0.0.1-mock")
        )
    }
}

extension RoutineStep {
    enum CodingKeys: String, CodingKey {
        case id, title, mediaAsset, durationSeconds, side, shortCue, voiceCue, hapticCue
        case movement, safetyNote, evidenceRef, reviewStatus, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(RoutineStepID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            mediaAsset: try container.decodeIfPresent(String.self, forKey: .mediaAsset),
            durationSeconds: try container.decode(Double.self, forKey: .durationSeconds),
            side: try container.value(.side, default: BodySide.none),
            shortCue: try container.value(.shortCue, default: ""),
            voiceCue: try container.decodeIfPresent(String.self, forKey: .voiceCue),
            hapticCue: try container.decodeIfPresent(String.self, forKey: .hapticCue),
            movement: try container.value(.movement, default: MovementSpec()),
            safetyNote: try container.decodeIfPresent(String.self, forKey: .safetyNote),
            evidenceRef: try container.decodeIfPresent(String.self, forKey: .evidenceRef),
            reviewStatus: try container.value(.reviewStatus, default: ContentReviewStatus.mockUnreviewed),
            version: try container.value(.version, default: "0.0.1-mock")
        )
    }
}

extension Routine {
    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, type, isPremium, steps, safetyNote, reviewStatus, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(RoutineID.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            subtitle: try container.decodeIfPresent(String.self, forKey: .subtitle),
            type: try container.decode(RoutineType.self, forKey: .type),
            isPremium: try container.value(.isPremium, default: false),
            steps: try container.value(.steps, default: [RoutineStep]()),
            safetyNote: try container.decodeIfPresent(String.self, forKey: .safetyNote),
            reviewStatus: try container.value(.reviewStatus, default: ContentReviewStatus.mockUnreviewed),
            version: try container.value(.version, default: "0.0.1-mock")
        )
    }
}

extension PoseConstraints {
    enum CodingKeys: String, CodingKey {
        case maxYawDegrees, maxPitchDegrees, maxRollDegrees
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxYawDegrees: try container.value(.maxYawDegrees, default: 25),
            maxPitchDegrees: try container.value(.maxPitchDegrees, default: 25),
            maxRollDegrees: try container.value(.maxRollDegrees, default: 30)
        )
    }
}

extension FaceAnchor {
    enum CodingKeys: String, CodingKey {
        case id, name, side, rule, toleranceRadius, poseConstraints
        case confidenceThreshold, evidenceRef, safetyNote, reviewStatus, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(FaceAnchorID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            side: try container.value(.side, default: BodySide.none),
            rule: try container.decode(AnchorGeometryRule.self, forKey: .rule),
            toleranceRadius: try container.value(.toleranceRadius, default: 0.12),
            poseConstraints: try container.value(.poseConstraints, default: PoseConstraints.default),
            confidenceThreshold: try container.value(.confidenceThreshold, default: 0.5),
            evidenceRef: try container.decodeIfPresent(String.self, forKey: .evidenceRef),
            safetyNote: try container.decodeIfPresent(String.self, forKey: .safetyNote),
            reviewStatus: try container.value(.reviewStatus, default: ContentReviewStatus.mockUnreviewed),
            version: try container.value(.version, default: "0.0.1-mock")
        )
    }
}
