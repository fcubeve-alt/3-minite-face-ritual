import Combine
import SwiftUI
import UIKit
import FaceRitualCore

/// 一条待绘制的运动轨迹。渲染器只认这个结构，不认 provider、不认 anchor 规则。
/// overlay 的绘制方式。
///
/// 不是所有动作都有轨迹：表情肌动作（GM-01 呼吸、GM-09 鼓气、GM-10 元音）
/// 根本不用手，全脸轻拍（GM-15）跨多个区域也没有单一路线。
/// 这类动作只标出「注意这一带」，不画 ● → ◎。
enum OverlayStyle {
    /// 有轨迹：● 起点 / 路径 / 方向 / 移动光点 / ◎ 终点。
    case path
    /// 只标区域：柔和的呼吸圈。多个区域时按 `sequence` 轮流点亮。
    case focusRegion
}

struct MotionOverlay: Identifiable {
    let id: String
    let start: Point2D
    let end: Point2D?
    let path: MotionPath
    let toleranceRadius: Double
    let gesture: GestureHint
    let direction: MovementDirection
    let side: BodySide
    var style: OverlayStyle = .path
    /// focusRegion 用：这是第几个区域、共几个。用来让高亮按顺序流动，
    /// 而不是所有区域同时闪 —— 后者看上去像报错。
    var sequence: (index: Int, count: Int)?
}

/// 交给 Overlay Renderer 的一帧。
struct ARGuidanceFrame {
    var quality: GuidanceQuality = .lost
    var hint: GuidanceHint = .faceNotFound
    var overlayOpacity: Double = 0
    var overlays: [MotionOverlay] = []
    /// 循环内的相位 0…1，驱动移动光点。
    var cyclePhase: Double = 0
    var isFrozen: Bool = false
    /// Debug 用：语义 landmark 与脸部坐标轴。
    var debugLandmarks: [SemanticLandmark: Point2D] = [:]
    var debugFrame: FaceFrame?

    static let idle = ARGuidanceFrame()
}

/// 把 provider 输出的 `FaceGeometry` 和播放器的当前动作，
/// 合成为可直接绘制的一帧。
///
/// 这是规格 §7 链路的下半段：
/// FaceGeometry → FaceFrame → AnchorResolver → PathSampler → （交给 Renderer）
///
/// 它**不做**任何「用户做得对不对」的判断（规格 §10）。
///
/// 线程约定：所有 provider 都保证在主线程回调 `onGeometry`，
/// 因此本类的全部状态变更都发生在主线程。刻意不加 `@MainActor` ——
/// 加了之后 provider 的 nonisolated 回调闭包就无法直接调用这里的方法。
final class ARGuidanceController: ObservableObject {

    @Published private(set) var guidanceFrame: ARGuidanceFrame = .idle
    @Published private(set) var trackingState: FaceTrackingState = .notDetected
    @Published private(set) var providerDescriptor: FaceProviderDescriptor
    @Published private(set) var currentFPS: Double = 0
    @Published private(set) var lastError: String?
    /// 连续处于 lost 状态的秒数（用帧时间戳算，不另起时钟）。
    /// UI 用它决定何时**建议**退回 Coach —— 偶发丢失是正常的（手会遮脸），
    /// 一丢就打断用户是错的。
    @Published private(set) var continuousLostSeconds: Double = 0
    /// 请求的 provider 不可用时的回落说明，用于 UI 提示与 analytics。
    @Published private(set) var fallbackNotice: String?

    private var provider: FaceAlignmentProvider
    private let anchors: [FaceAnchorID: FaceAnchor]
    private let resolver = FaceAnchorResolver()
    private let sampler = PathSampler()
    private let evaluator = GuidanceQualityEvaluator()
    private let performance = PerformanceMonitor()

    private var smoother = FaceGeometrySmoother()
    private var lockTracker = FaceLockTracker()
    /// 最后一帧「可信」的 overlay。遮挡时冻结在这里，而不是让它消失。
    private var lastGoodOverlays: [MotionOverlay] = []

    private var lostSince: TimeInterval?
    private var currentMovement: MovementSpec?
    private var currentSide: BodySide = .none
    private var mirroredMovement: MovementSpec?
    private var viewSize: CGSize = .zero
    private var isRunning = false

    var onFaceLockLost: ((GuidanceHint) -> Void)?
    var onFaceLockAcquired: ((Double) -> Void)?

    /// 跨会话累计。切后台再回来会重启 provider 并新建 lockTracker，
    /// 只读当前 tracker 会把之前的丢锁次数清零 —— 那是 POC 报告要的数据，不能丢。
    private var lockLossBeforeRestart = 0

    var lockLossCount: Int { lockLossBeforeRestart + lockTracker.lockLossCount }
    /// 只记录**整场会话**的首次锁定耗时（规格 §17 的核心 AR 指标）。
    /// 切后台再回来重新锁上不算「首次」，否则这个数字会被后台切换污染。
    private var firstLockSeconds: Double?

    var timeToFirstLock: Double? { firstLockSeconds }
    var performanceSummary: String {
        performance.summaryLine(
            providerID: providerDescriptor.id,
            lockLossCount: lockLossCount,
            timeToFirstLock: firstLockSeconds
        )
    }
    var performanceMonitor: PerformanceMonitor { performance }

    init(anchors: [FaceAnchorID: FaceAnchor], preferredProvider: FaceAlignmentProviderKind) {
        self.anchors = anchors
        let result = FaceAlignmentProviderFactory.makeFirstAvailable(preferring: preferredProvider)
        self.provider = result.provider
        self.providerDescriptor = result.provider.descriptor

        if let requested = result.fellBackFrom {
            let reason = FaceAlignmentProviderFactory.make(requested).unavailableReason ?? "不可用"
            fallbackNotice = "\(requested.displayName) 不可用（\(reason)），已回落到 \(result.provider.descriptor.displayName)。"
        }
    }

    // MARK: - 生命周期

    func start(viewSize: CGSize, isMirrored: Bool, targetFrameRate: Int = 30) {
        guard isRunning == false else { return }
        self.viewSize = viewSize
        isRunning = true

        smoother.reset()
        lostSince = nil
        continuousLostSeconds = 0
        // 首次 lock 只报一次：切后台再回来重新锁上不算「首次」，
        // 否则 timeToFirstLock 这个指标会被后台切换污染。
        lockLossBeforeRestart += lockTracker.lockLossCount
        lockTracker = FaceLockTracker()
        lockTracker.start(at: CACurrentMediaTime())
        performance.start(targetFrameRate: targetFrameRate)

        provider.onGeometry = { [weak self] geometry in
            self?.handle(geometry: geometry)
        }
        provider.onFailure = { [weak self] error in
            self?.lastError = error.localizedDescription
        }

        do {
            try provider.start(
                configuration: FaceAlignmentConfiguration(
                    viewSize: viewSize,
                    isMirrored: isMirrored,
                    targetFrameRate: targetFrameRate
                )
            )
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        provider.onGeometry = nil
        provider.onFailure = nil
        provider.stop()
        guidanceFrame = .idle
        trackingState = .notDetected
    }

    func updateViewSize(_ size: CGSize) {
        viewSize = size
        provider.updateViewSize(size)
    }

    func makePreviewView() -> UIView {
        provider.makePreviewView()
    }

    // MARK: - 播放器同步

    /// 播放器换段时调用。overlay 的内容完全由 MovementSpec 决定 ——
    /// Coach 与 AR 共用同一份动作真源。
    func updateMovement(segment: PlaybackSegment?) {
        currentMovement = segment?.resolvedMovement
        mirroredMovement = segment?.mirroredMovementForBothSides
        currentSide = segment?.side ?? .none
        lastGoodOverlays = []
    }

    func updateCyclePhase(_ phase: Double) {
        guidanceFrame.cyclePhase = phase
    }

    // MARK: - 每帧合成

    private func handle(geometry rawGeometry: FaceGeometry) {
        performance.recordFrame(latencyMS: providerLatencyMS())
        currentFPS = performance.currentFPS

        let geometry = smoother.smooth(rawGeometry)
        let frame = FaceFrame(geometry: geometry)
        let policy = currentMovement?.occlusionPolicy ?? .continueGuidance
        let assessment = evaluator.assess(geometry: geometry, frame: frame, policy: policy)

        if assessment.quality == .lost {
            let since = lostSince ?? geometry.timestamp
            lostSince = since
            // 时间戳倒退（切后台、provider 重启）时归零，避免算出负数或巨大值。
            let elapsed = geometry.timestamp - since
            continuousLostSeconds = (elapsed >= 0 && elapsed < 3600) ? elapsed : 0
        } else {
            lostSince = nil
            continuousLostSeconds = 0
        }

        let didLoseLock = lockTracker.update(assessment: assessment, timestamp: geometry.timestamp)
        trackingState = lockTracker.state
        if didLoseLock {
            onFaceLockLost?(assessment.hint)
        }
        if let seconds = lockTracker.timeToFirstLock, hasReportedFirstLock == false {
            hasReportedFirstLock = true
            firstLockSeconds = seconds
            onFaceLockAcquired?(seconds)
        }

        var next = ARGuidanceFrame(
            quality: assessment.quality,
            hint: assessment.hint,
            overlayOpacity: assessment.overlayOpacity,
            overlays: [],
            cyclePhase: guidanceFrame.cyclePhase,
            isFrozen: assessment.shouldFreezeOverlay
        )

        if let frame {
            next.debugFrame = frame
            next.debugLandmarks = geometry.landmarks.mapValues(\.point)
        }

        if let frame, let movement = currentMovement, assessment.shouldFreezeOverlay == false {
            var built: [MotionOverlay] = []
            built += makeOverlays(movement: movement, geometry: geometry, frame: frame, side: currentSide, idSuffix: "primary")
            // side == .both 时同时画两侧。
            if let mirroredMovement {
                built += makeOverlays(movement: mirroredMovement, geometry: geometry, frame: frame, side: .both, idSuffix: "mirrored")
            }
            if built.isEmpty == false {
                lastGoodOverlays = built
            }
            next.overlays = built
        } else {
            // 遮挡 / 低置信度：保留最后可信位置，继续导航（规格 §4）。
            next.overlays = lastGoodOverlays
        }

        guidanceFrame = next
    }

    private var hasReportedFirstLock = false

    private func providerLatencyMS() -> Double? {
        if let vision = provider as? VisionFaceAlignmentProvider { return vision.lastLatencyMS }
        if let hrffa = provider as? HRFFAFaceAlignmentProvider { return hrffa.lastLatencyMS }
        return nil
    }

    /// 一个 MovementSpec 可能产生多个 overlay：
    /// 有轨迹的动作产生一条，只标区域的动作（expression / tap）每个区域一个。
    private func makeOverlays(
        movement: MovementSpec,
        geometry: FaceGeometry,
        frame: FaceFrame,
        side: BodySide,
        idSuffix: String
    ) -> [MotionOverlay] {
        switch movement.pathType {
        case .expression, .tap:
            let regions = makeFocusOverlays(
                movement: movement, geometry: geometry, frame: frame, side: side, idSuffix: idSuffix
            )
            // tap 允许退化成单点（focusAnchors 为空但有 startAnchor）；
            // expression 没有区域就是没有可画的东西 —— 这一段只剩提示与计时，
            // 不是错误。
            if regions.isEmpty == false { return regions }
            if movement.pathType == .expression { return [] }
        case .line, .curve, .arc, .circle, .press, .hold:
            break
        }
        guard let overlay = makePathOverlay(
            movement: movement, geometry: geometry, frame: frame, side: side, idSuffix: idSuffix
        ) else { return [] }
        return [overlay]
    }

    /// 只标区域的动作：每个 focusAnchor 一个呼吸圈。
    private func makeFocusOverlays(
        movement: MovementSpec,
        geometry: FaceGeometry,
        frame: FaceFrame,
        side: BodySide,
        idSuffix: String
    ) -> [MotionOverlay] {
        // 去重但保持顺序：内容里可能左右都列了同一个中线区域。
        var seen: Set<FaceAnchorID> = []
        let ids = movement.focusAnchorIDs.filter { seen.insert($0).inserted }

        var resolved: [(FaceAnchorID, ResolvedAnchor)] = []
        for anchorID in ids {
            guard let anchor = anchors[anchorID],
                  case let .success(point) = resolver.resolve(anchor, geometry: geometry, frame: frame),
                  point.meetsDisplayThreshold
            else { continue }
            resolved.append((anchorID, point))
        }

        return resolved.enumerated().map { index, entry in
            let (anchorID, point) = entry
            return MotionOverlay(
                id: "\(anchorID.rawValue)-focus-\(idSuffix)",
                start: point.viewPoint,
                end: nil,
                path: MotionPath(kind: movement.pathType, points: [point.viewPoint]),
                toleranceRadius: point.toleranceRadiusPoints,
                gesture: movement.gestureHint,
                direction: movement.direction,
                side: side,
                style: .focusRegion,
                sequence: (index: index, count: resolved.count)
            )
        }
    }

    private func makePathOverlay(
        movement: MovementSpec,
        geometry: FaceGeometry,
        frame: FaceFrame,
        side: BodySide,
        idSuffix: String
    ) -> MotionOverlay? {
        guard let startID = movement.startAnchorID,
              let startAnchor = anchors[startID],
              case let .success(start) = resolver.resolve(startAnchor, geometry: geometry, frame: frame),
              start.meetsDisplayThreshold
        else { return nil }

        var end: ResolvedAnchor?
        if let endID = movement.endAnchorID, let endAnchor = anchors[endID] {
            if case let .success(resolved) = resolver.resolve(endAnchor, geometry: geometry, frame: frame),
               resolved.meetsDisplayThreshold {
                end = resolved
            } else {
                // 终点不可靠时不画半条路径 —— 宁可只显示起点。
                return nil
            }
        }

        let path = sampler.makePath(
            movement: movement,
            start: start.viewPoint,
            end: end?.viewPoint,
            frame: frame
        )

        return MotionOverlay(
            id: "\(startID.rawValue)-\(idSuffix)",
            start: start.viewPoint,
            end: end?.viewPoint,
            path: path,
            toleranceRadius: start.toleranceRadiusPoints,
            gesture: movement.gestureHint,
            direction: movement.direction,
            side: side
        )
    }
}
