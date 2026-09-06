import Combine
import Foundation
import SwiftUI
import FaceRitualCore

/// 一次练习会话。**Coach / AR Mirror / Watch & Breathe 共用这一个 view model。**
///
/// 三种模式的差别只在渲染层：
/// - Coach：播放占位媒体，不开摄像头
/// - AR Mirror：开摄像头 + overlay
/// - Watch & Breathe：开摄像头 + overlay，但不催促用户动手
///
/// 计时、换动作、左右切换、语音、震动、记录保存全部走同一条路径 ——
/// 这正是规格 §4「一个动作真源」在播放侧的体现。
///
/// 线程约定同 `ARGuidanceController`：全部在主线程。
final class RoutineSessionViewModel: ObservableObject {

    @Published private(set) var status: PlayerStatus = .idle
    @Published private(set) var currentSegment: PlaybackSegment?
    @Published private(set) var currentSegmentIndex: Int = 0
    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var segmentProgress: Double = 0
    @Published private(set) var routineProgress: Double = 0
    @Published private(set) var prepareCountdown: Int?
    @Published private(set) var completedRepetitions: Int = 0
    @Published private(set) var didFinish = false
    let routine: Routine
    let mode: PracticeMode

    private let environment: AppEnvironment
    private let engine: RoutinePlayerEngine
    private let plan: PlaybackPlan
    private var ticker: DisplayLinkTicker?

    private var sessionRecord: PracticeSession
    private var lastPulseCycle: Int = -1
    private var hasStarted = false

    var totalSegments: Int { plan.segments.count }

    init(routine: Routine, mode: PracticeMode, environment: AppEnvironment) {
        self.routine = routine
        self.mode = mode
        self.environment = environment

        let plan = PlaybackPlan(routine: routine, prepareCountdownSeconds: 3)
        self.plan = plan
        self.engine = RoutinePlayerEngine(plan: plan)

        self.sessionRecord = PracticeSession(
            routineID: routine.id,
            routineTitle: routine.title,
            routineType: routine.type,
            startedAt: Date(),
            mode: mode,
            arMirrorUsed: mode == .arMirror,
            contentVersion: environment.content.meta.contentVersion
        )

        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        wireGuidanceCallbacks()
    }

    // MARK: - 生命周期

    func start() {
        guard hasStarted == false else { return }
        hasStarted = true

        environment.analytics.track(.routineStarted(routineID: routine.id, type: routine.type, mode: mode))

        // 用户全程双手在脸上，3–5 分钟不会碰屏幕。
        // 不阻止自动锁屏的话，动作做到一半屏幕就黑了。
        ScreenWakeLock.shared.acquire()

        let ticker = DisplayLinkTicker { [weak self] delta in
            self?.tick(delta)
        }
        self.ticker = ticker
        ticker.start()
        engine.start()
    }

    // MARK: - 前后台

    /// 进入后台。
    ///
    /// 必须把摄像头关掉 —— 后台还开着相机既费电又是用户信任问题，
    /// 而且规格 §4 说摄像头「随时可以关闭」，切走就是最明确的一次「随时」。
    func handleEnteredBackground() {
        guard didFinish == false else { return }
        wasRunningBeforeBackground = engine.status == .running || engine.status == .preparing
        if wasRunningBeforeBackground {
            engine.pause()
        }
        environment.voice.stop()
        ScreenWakeLock.shared.releaseAll()
    }

    /// 回到前台。
    ///
    /// **刻意保持暂停**：用户刚切回来，手还没抬起来。
    /// 自动继续会让他直接错过一整个动作，而且没有任何好处。
    func handleReturnedToForeground(viewSize: CGSize) {
        guard didFinish == false else { return }
        ScreenWakeLock.shared.acquire()
    }

    private var wasRunningBeforeBackground = false

    func pause() {
        engine.pause()
    }

    func resume() {
        engine.resume()
    }

    func togglePause() {
        engine.status == .paused ? engine.resume() : engine.pause()
    }

    func skipForward() { engine.skipForward() }
    func skipBackward() { engine.skipBackward() }

    /// 用户中途退出。已完成部分照样记录 —— 规格 §12 不惩罚中断。
    func abandon() {
        guard didFinish == false else { return }
        engine.cancel()
        teardown()
    }

    private func tick(_ delta: Double) {
        engine.tick(deltaTime: delta)
        segmentProgress = engine.segmentProgress
        routineProgress = engine.routineProgress
        completedRepetitions = engine.completedRepetitions

        // 每个循环开头给一次轻震动，作为节奏提示。
        let cycle = engine.completedRepetitions
        if cycle != lastPulseCycle, engine.status == .running {
            lastPulseCycle = cycle
            if cycle > 0 { environment.haptics.cyclePulse() }
        }
    }

    private func teardown() {
        ticker?.stop()
        ticker = nil
        environment.voice.stop()
        ScreenWakeLock.shared.release()
    }

    // MARK: - 播放器事件

    private func handle(_ event: PlayerEvent) {
        switch event {
        case let .prepareCountdown(remaining):
            prepareCountdown = remaining > 0 ? remaining : nil
            if remaining > 0 { environment.haptics.countdownTick() }

        case let .segmentWillStart(index, segment):
            prepareCountdown = nil
            currentSegmentIndex = index
            currentSegment = segment
            lastPulseCycle = -1
            environment.haptics.stepChange()
            if let cue = segment.step.voiceCue {
                environment.voice.speak(voiceCueText(cue, side: segment.side, segment: segment))
            }

        case let .secondsRemainingChanged(remaining):
            secondsRemaining = remaining
            if remaining <= 3, remaining > 0, engine.status == .running {
                environment.haptics.countdownTick()
            }

        case .segmentDidComplete:
            break

        case .sideDidChange:
            break

        case .paused, .resumed:
            break

        case let .segmentHalfway(index):
            _ = index

        case let .routineCompleted(seconds):
            finish(secondsCompleted: seconds, completed: true)

        case let .cancelled(seconds):
            finish(secondsCompleted: seconds, completed: false)
        }

        status = engine.status
    }

    /// 左右侧提示拼进语音里 —— 用户不必自己记住现在做哪边。
    private func voiceCueText(_ cue: String, side: BodySide, segment: PlaybackSegment) -> String {
        switch side {
        case .left where segment.segmentCountInStep > 1:
            return "Left side. " + cue
        case .right where segment.segmentCountInStep > 1:
            return "Now the right side. " + cue
        default:
            return cue
        }
    }

    private func finish(secondsCompleted: Double, completed: Bool) {
        guard didFinish == false else { return }
        didFinish = true

        sessionRecord.completedAt = Date()
        sessionRecord.completed = completed
        sessionRecord.secondsCompleted = secondsCompleted

        environment.record(sessionRecord)

        if completed {
            environment.haptics.completion()
            environment.analytics.track(.routineCompleted(routineID: routine.id, mode: mode, secondsCompleted: secondsCompleted))
        } else {
            environment.analytics.track(
                .routineAbandoned(
                    routineID: routine.id,
                    mode: mode,
                    secondsCompleted: secondsCompleted,
                    atStepIndex: currentSegmentIndex
                )
            )
        }
        teardown()
    }

    var completedSession: PracticeSession { sessionRecord }
}
