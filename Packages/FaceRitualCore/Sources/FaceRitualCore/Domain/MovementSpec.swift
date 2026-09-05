import Foundation

/// 路径几何 —— 全部以**脸部归一化单位**表达（1.0 == 瞳距）。
/// 绝不出现屏幕像素。见 ARCHITECTURE.md §2 FaceFrame。
public struct PathGeometry: Hashable, Codable, Sendable {
    /// 控制点，表达在 start→end 的局部坐标系里：
    /// `along` = 沿 start→end 方向的比例（0 = start，1 = end）
    /// `perpendicular` = 垂直偏移，单位为瞳距（正 = 朝 FaceFrame 的 +y，即脸的下方）
    public var controlOffsets: [PathControlOffset]
    /// circle / arc 用，单位为瞳距。
    public var radius: Double?
    /// circle / arc 的扫掠角度（度）。circle 默认 360。
    public var sweepDegrees: Double?
    /// 圆周方向。屏幕镜像不改变解剖学方向，渲染层负责换算。
    public var clockwise: Bool

    public init(
        controlOffsets: [PathControlOffset] = [],
        radius: Double? = nil,
        sweepDegrees: Double? = nil,
        clockwise: Bool = true
    ) {
        self.controlOffsets = controlOffsets
        self.radius = radius
        self.sweepDegrees = sweepDegrees
        self.clockwise = clockwise
    }

    public static let straight = PathGeometry()
}

public struct PathControlOffset: Hashable, Codable, Sendable {
    public var along: Double
    public var perpendicular: Double

    public init(along: Double, perpendicular: Double) {
        self.along = along
        self.perpendicular = perpendicular
    }
}

/// 规格 §9 Movement Specification V2。
/// **同一份 MovementSpec 同时驱动 Coach 与 AR**（规格 §4「一个动作真源」）。
public struct MovementSpec: Hashable, Codable, Sendable {
    public var startAnchorID: FaceAnchorID?
    public var endAnchorID: FaceAnchorID?
    public var pathType: PathType
    public var pathGeometry: PathGeometry
    public var direction: MovementDirection
    public var gestureHint: GestureHint
    /// 每分钟循环次数；nil = 由 duration/repetitions 推导。
    public var tempoCyclesPerMinute: Double?
    public var repetitions: Int
    public var holdSeconds: Double
    public var overlayAssets: [String]
    public var occlusionPolicy: OcclusionPolicy
    public var trackingSupport: TrackingSupport
    public var version: String

    public init(
        startAnchorID: FaceAnchorID? = nil,
        endAnchorID: FaceAnchorID? = nil,
        pathType: PathType = .line,
        pathGeometry: PathGeometry = .straight,
        direction: MovementDirection = .none,
        gestureHint: GestureHint = .none,
        tempoCyclesPerMinute: Double? = nil,
        repetitions: Int = 1,
        holdSeconds: Double = 0,
        overlayAssets: [String] = [],
        occlusionPolicy: OcclusionPolicy = .continueGuidance,
        trackingSupport: TrackingSupport = .guidanceOnly,
        version: String = "0.0.1-mock"
    ) {
        self.startAnchorID = startAnchorID
        self.endAnchorID = endAnchorID
        self.pathType = pathType
        self.pathGeometry = pathGeometry
        self.direction = direction
        self.gestureHint = gestureHint
        self.tempoCyclesPerMinute = tempoCyclesPerMinute
        self.repetitions = repetitions
        self.holdSeconds = holdSeconds
        self.overlayAssets = overlayAssets
        self.occlusionPolicy = occlusionPolicy
        self.trackingSupport = trackingSupport
        self.version = version
    }

    /// AR overlay 是否有可渲染内容。press/hold 只需要起点。
    public var isARRenderable: Bool {
        guard startAnchorID != nil else { return false }
        switch pathType {
        case .press, .hold, .circle:
            return true
        case .line, .curve, .arc:
            return endAnchorID != nil
        }
    }

    /// 单次循环时长（秒）。用于移动光点的节奏。
    public func cycleDuration(fallbackTotalSeconds: Double) -> Double {
        if let tempo = tempoCyclesPerMinute, tempo > 0 {
            return 60.0 / tempo
        }
        let reps = max(1, repetitions)
        return max(0.4, fallbackTotalSeconds / Double(reps))
    }
}
