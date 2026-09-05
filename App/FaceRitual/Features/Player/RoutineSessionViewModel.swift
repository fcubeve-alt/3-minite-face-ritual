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
    /// AR 中途退回 Coach 后为 true。播放器不受影响，只是不再渲染摄像头与 overlay。
    @Published private(set) var didFallBackToCoach = false

    let routine: Routine
    let mode: PracticeMode
    /// AR / Watch 模式下才存在。
    let guidance: ARGuidanceController?

    private let environment: AppEnvironment
    private let engine: RoutinePlayerEngine
    private let plan: PlaybackPlan
    private var ticker: DisplayLinkTicker?

    private var sessionRecord: PracticeSession
    private var lastPulseCycle: Int = -1
    private var hasStarted = false

    var totalSegments: Int { plan.segments.count }
    var usesCamera: Bool { mode != .coach }

    init(routine: Routine, mode: PracticeMode, environment: AppEnvironment) {
        self.routine = routine
        self.mode = mode
        self.environment = environment

        let plan = PlaybackPlan(routine: routine, prepareCountdownSeconds: 3)
        self.plan = plan
        self.engine = RoutinePlayerEngine(plan: plan)

        self.guidance = mode == .coach
            ? nil
            : ARGuidanceController(
                anchors: environment.content.anchors,
                preferredProvider: environment.settings.preferredProviderKind
            )

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
        if mode == .arMirror, let guidance {
            environment.analytics.track(.arMirrorStarted(routineID: routine.id, providerID: guidance.providerDescriptor.id))
            sessionRecord.faceProviderID = guidance.providerDescriptor.id
        }
        if mode == .watch {
            environment.analytics.track(.watchModeUsed(routineID: routine.id))
        }

        let ticker = DisplayLinkTicker { [weak self] delta in
            self?.tick(delta)
        }
        self.ticker = ticker
        ticker.start()
        engine.start()
    }

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
        guidance?.updateCyclePhase(engine.cyclePhase)

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
        guidance?.stop()
        environment.voice.stop()
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
            guidance?.updateMovement(segment: segment)
            environment.haptics.stepChange()
            if let cue = segment.step.voiceCue {
                environment.voice.speak(voiceCueText(cue, side: segment.side, segment: segment))
            }

        case let .secondsRemainingChanged(remaining):
            secondsRemaining = remaining
            if remaining <= 3, remaining > 0, engine.status == .running {
                environment.haptics.countdownTick()
            }

        case let .segmentDidComplete(index):
            if let segment = plan.segment(at: index), mode == .arMirror {
                environment.analytics.track(
                    .arStepCompleted(
                        routineID: routine.id,
                        stepID: segment.step.id,
                        quality: guidance?.guidanceFrame.quality ?? .lost
                    )
                )
            }

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
        if let guidance {
            sessionRecord.faceLockLossCount = guidance.lockLossCount
            sessionRecord.timeToFirstFaceLock = guidance.timeToFirstLock
            environment.analytics.track(
                .arSessionQuality(
                    providerID: guidance.providerDescriptor.id,
                    averageFPS: guidance.performanceMonitor.averageFPS,
                    averageLatencyMS: guidance.performanceMonitor.averageLatencyMS,
                    lockLossCount: guidance.lockLossCount
                )
            )
        }

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

    // MARK: - AR

    private func wireGuidanceCallbacks() {
        guidance?.onFaceLockLost = { [weak self] hint in
            guard let self else { return }
            self.environment.analytics.track(
                .faceLockLost(
                    routineID: self.routine.id,
                    stepID: self.currentSegment?.step.id,
                    hint: hint
                )
            )
        }
        guidance?.onFaceLockAcquired = { [weak self] seconds in
            guard let self, let guidance = self.guidance else { return }
            self.environment.analytics.track(
                .faceLockAcquired(providerID: guidance.providerDescriptor.id, secondsToLock: seconds)
            )
        }
    }

    func startGuidance(viewSize: CGSize) {
        guard let guidance else { return }
        guidance.start(viewSize: viewSize, isMirrored: environment.settings.mirrorPreview)
        if let notice = guidance.fallbackNotice {
            environment.analytics.track(
                .guidanceFallback(routineID: routine.id, from: mode, to: mode, reason: notice)
            )
        }
    }

    /// AR 中途退回 Coach。**计时与动作序列不中断** —— 规格 §4：识别失败不得阻塞 routine。
    ///
    /// 这里只关掉摄像头与 overlay，播放器完全不受影响：
    /// 用户不会因为「脸识别不出来」而丢掉这次练习。
    /// 会话记录仍标记为 arMirror + didFallBackToCoach，
    /// 这样 POC 阶段能看出「有多少人是被迫退回去的」。
    func fallBackToCoach(reason: String) {
        guard didFallBackToCoach == false else { return }
        didFallBackToCoach = true
        sessionRecord.didFallBackToCoach = true

        guidance?.stop()
        environment.analytics.track(
            .guidanceFallback(routineID: routine.id, from: mode, to: .coach, reason: reason)
        )
    }

    var completedSession: PracticeSession { sessionRecord }
}
