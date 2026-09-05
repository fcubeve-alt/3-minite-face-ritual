import Foundation

public enum PlayerStatus: String, Sendable, Equatable {
    case idle
    /// 开始前的 3-2-1 准备倒计时。
    case preparing
    case running
    case paused
    case completed
    case cancelled
}

/// 播放器事件。Coach / AR Mirror / Watch & Breathe 三种模式订阅**同一条**事件流。
public enum PlayerEvent: Sendable, Equatable {
    case prepareCountdown(remaining: Int)
    case segmentWillStart(index: Int, segment: PlaybackSegment)
    case segmentHalfway(index: Int)
    /// 段内剩余整秒数变化（3 / 2 / 1 / 0）。语音与震动挂在这里。
    case secondsRemainingChanged(Int)
    case segmentDidComplete(index: Int)
    case sideDidChange(BodySide)
    case paused
    case resumed
    case routineCompleted(secondsCompleted: Double)
    case cancelled(secondsCompleted: Double)
}

/// 纯 tick 驱动的 routine 播放器。
///
/// **内部没有 Timer / DispatchQueue / CADisplayLink**，
/// 因此单元测试可以用固定步长把 3 分钟推完并断言每次换步时刻。
/// App 层用 `DisplayLinkTicker` 把真实时间喂进来。
public final class RoutinePlayerEngine {

    public private(set) var plan: PlaybackPlan
    public private(set) var status: PlayerStatus = .idle
    public private(set) var currentSegmentIndex: Int = 0
    public private(set) var elapsedInSegment: Double = 0
    public private(set) var totalElapsed: Double = 0

    private var prepareRemaining: Double = 0
    private var lastAnnouncedSecond: Int = -1
    private var didAnnounceHalfway = false
    private var lastSide: BodySide?

    /// 事件回调。App 层设置一次即可。
    public var onEvent: ((PlayerEvent) -> Void)?

    public init(plan: PlaybackPlan) {
        self.plan = plan
    }

    // MARK: - 查询

    public var currentSegment: PlaybackSegment? {
        plan.segment(at: currentSegmentIndex)
    }

    public var secondsRemainingInSegment: Double {
        guard let segment = currentSegment else { return 0 }
        return max(0, segment.durationSeconds - elapsedInSegment)
    }

    /// 当前段进度 0…1，用于移动光点与倒计时环。
    public var segmentProgress: Double {
        guard let segment = currentSegment, segment.durationSeconds > 0 else { return 0 }
        return clamp(elapsedInSegment / segment.durationSeconds, 0, 1)
    }

    public var routineProgress: Double {
        guard plan.totalDurationSeconds > 0 else { return 0 }
        return clamp(totalElapsed / plan.totalDurationSeconds, 0, 1)
    }

    public var isActive: Bool {
        status == .preparing || status == .running
    }

    /// 当前段内的循环相位 0…1，按 MovementSpec 的 tempo/repetitions 折算。
    /// 移动光点、脉冲和 rep 计数都用它。
    public var cyclePhase: Double {
        guard let segment = currentSegment else { return 0 }
        let cycle = segment.step.movement.cycleDuration(fallbackTotalSeconds: segment.durationSeconds)
        guard cycle > 1e-6 else { return 0 }
        return (elapsedInSegment.truncatingRemainder(dividingBy: cycle)) / cycle
    }

    public var completedRepetitions: Int {
        guard let segment = currentSegment else { return 0 }
        let cycle = segment.step.movement.cycleDuration(fallbackTotalSeconds: segment.durationSeconds)
        guard cycle > 1e-6 else { return 0 }
        return Int(elapsedInSegment / cycle)
    }

    // MARK: - 控制

    public func start() {
        guard status == .idle || status == .completed || status == .cancelled else { return }
        guard plan.isEmpty == false else {
            status = .completed
            onEvent?(.routineCompleted(secondsCompleted: 0))
            return
        }
        currentSegmentIndex = 0
        elapsedInSegment = 0
        totalElapsed = 0
        lastAnnouncedSecond = -1
        didAnnounceHalfway = false
        lastSide = nil

        if plan.prepareCountdownSeconds > 0 {
            prepareRemaining = plan.prepareCountdownSeconds
            status = .preparing
            onEvent?(.prepareCountdown(remaining: Int(prepareRemaining.rounded(.up))))
        } else {
            status = .running
            beginCurrentSegment()
        }
    }

    public func pause() {
        guard isActive else { return }
        status = .paused
        onEvent?(.paused)
    }

    public func resume() {
        guard status == .paused else { return }
        status = prepareRemaining > 0 ? .preparing : .running
        onEvent?(.resumed)
    }

    public func cancel() {
        guard status != .completed, status != .cancelled else { return }
        status = .cancelled
        onEvent?(.cancelled(secondsCompleted: totalElapsed))
    }

    public func skipForward() {
        guard isActive || status == .paused else { return }
        advanceSegment(consumingOverflow: 0)
    }

    public func skipBackward() {
        guard isActive || status == .paused else { return }
        // 段内已过 2 秒以上 → 回到本段开头；否则跳到上一段。
        if elapsedInSegment > 2.0 || currentSegmentIndex == 0 {
            totalElapsed -= elapsedInSegment
            elapsedInSegment = 0
        } else {
            currentSegmentIndex -= 1
            let segment = plan.segments[currentSegmentIndex]
            totalElapsed = segment.startOffsetSeconds
            elapsedInSegment = 0
        }
        beginCurrentSegment()
    }

    // MARK: - 时间推进

    /// 由 App 层每帧调用；`deltaTime` 为秒。
    public func tick(deltaTime: Double) {
        guard deltaTime > 0 else { return }

        switch status {
        case .preparing:
            prepareRemaining -= deltaTime
            let remaining = max(0, Int(prepareRemaining.rounded(.up)))
            if remaining != lastAnnouncedSecond {
                lastAnnouncedSecond = remaining
                onEvent?(.prepareCountdown(remaining: remaining))
            }
            if prepareRemaining <= 0 {
                prepareRemaining = 0
                status = .running
                lastAnnouncedSecond = -1
                beginCurrentSegment()
            }

        case .running:
            var remainingDelta = deltaTime
            // 单帧时长可能跨过一整段（低端机掉帧 / 极短 step），循环消化。
            while remainingDelta > 0, status == .running {
                guard let segment = currentSegment else {
                    finish()
                    return
                }
                let left = segment.durationSeconds - elapsedInSegment
                if remainingDelta < left {
                    elapsedInSegment += remainingDelta
                    totalElapsed += remainingDelta
                    remainingDelta = 0
                    emitInSegmentEvents(segment: segment)
                } else {
                    elapsedInSegment += left
                    totalElapsed += left
                    remainingDelta -= left
                    onEvent?(.segmentDidComplete(index: currentSegmentIndex))
                    advanceSegment(consumingOverflow: 0)
                }
            }

        case .idle, .paused, .completed, .cancelled:
            break
        }
    }

    // MARK: - 内部

    private func beginCurrentSegment() {
        guard let segment = currentSegment else {
            finish()
            return
        }
        elapsedInSegment = 0
        didAnnounceHalfway = false
        lastAnnouncedSecond = -1

        onEvent?(.segmentWillStart(index: currentSegmentIndex, segment: segment))
        if segment.side != lastSide {
            lastSide = segment.side
            if segment.side != .none {
                onEvent?(.sideDidChange(segment.side))
            }
        }
        emitInSegmentEvents(segment: segment)
    }

    private func advanceSegment(consumingOverflow overflow: Double) {
        let next = currentSegmentIndex + 1
        guard next < plan.segments.count else {
            currentSegmentIndex = plan.segments.count
            finish()
            return
        }
        currentSegmentIndex = next
        totalElapsed = plan.segments[next].startOffsetSeconds + overflow
        beginCurrentSegment()
    }

    private func emitInSegmentEvents(segment: PlaybackSegment) {
        let remaining = max(0, Int((segment.durationSeconds - elapsedInSegment).rounded(.up)))
        if remaining != lastAnnouncedSecond {
            lastAnnouncedSecond = remaining
            onEvent?(.secondsRemainingChanged(remaining))
        }
        if didAnnounceHalfway == false, elapsedInSegment >= segment.durationSeconds / 2 {
            didAnnounceHalfway = true
            onEvent?(.segmentHalfway(index: currentSegmentIndex))
        }
    }

    private func finish() {
        guard status != .completed else { return }
        status = .completed
        totalElapsed = plan.totalDurationSeconds
        onEvent?(.routineCompleted(secondsCompleted: plan.totalDurationSeconds))
    }
}
