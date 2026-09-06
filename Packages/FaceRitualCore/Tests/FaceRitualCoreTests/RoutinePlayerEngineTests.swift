import XCTest
@testable import FaceRitualCore

final class RoutinePlayerEngineTests: XCTestCase {

    /// 60fps 推进 —— 与真机 CADisplayLink 一致。
    private let frame = 1.0 / 60.0

    private func makeRoutine(
        steps: [(id: String, duration: Double, side: BodySide)]
    ) -> Routine {
        Routine(
            id: "test_routine",
            title: "Test",
            type: .morning,
            isPremium: false,
            steps: steps.map { spec in
                RoutineStep(
                    id: RoutineStepID(rawValue: spec.id),
                    title: spec.id,
                    durationSeconds: spec.duration,
                    side: spec.side,
                    shortCue: "cue"
                )
            }
        )
    }

    private func advance(_ engine: RoutinePlayerEngine, seconds: Double) {
        let ticks = Int((seconds / frame).rounded())
        for _ in 0..<ticks { engine.tick(deltaTime: frame) }
    }

    // MARK: - PlaybackPlan

    func testLeftThenRightExpandsIntoTwoSegments() {
        let routine = makeRoutine(steps: [("a", 36, .leftThenRight), ("b", 20, .none)])
        let plan = PlaybackPlan(routine: routine)

        XCTAssertEqual(plan.segments.count, 3)
        XCTAssertEqual(plan.segments[0].side, .left)
        XCTAssertEqual(plan.segments[1].side, .right)
        XCTAssertEqual(plan.segments[0].durationSeconds, 18)
        XCTAssertEqual(plan.segments[1].durationSeconds, 18)
        XCTAssertEqual(plan.segments[2].side, .none)
        XCTAssertEqual(plan.totalDurationSeconds, 56)

        XCTAssertEqual(plan.segments[0].startOffsetSeconds, 0)
        XCTAssertEqual(plan.segments[1].startOffsetSeconds, 18)
        XCTAssertEqual(plan.segments[2].startOffsetSeconds, 36)
    }

    func testSegmentRewritesAnchorIDsToItsOwnSide() {
        let step = RoutineStep(
            id: "s",
            title: "s",
            durationSeconds: 20,
            side: .leftThenRight,
            shortCue: "cue",
            movement: MovementSpec(startAnchorID: "temple_left", endAnchorID: "jaw_angle_left", pathType: .line)
        )
        let plan = PlaybackPlan(routine: Routine(id: "r", title: "r", type: .morning, isPremium: false, steps: [step]))

        XCTAssertEqual(plan.segments[0].resolvedMovement.startAnchorID, "temple_left")
        XCTAssertEqual(plan.segments[0].resolvedMovement.endAnchorID, "jaw_angle_left")
        XCTAssertEqual(plan.segments[1].resolvedMovement.startAnchorID, "temple_right")
        XCTAssertEqual(plan.segments[1].resolvedMovement.endAnchorID, "jaw_angle_right")
    }

    func testAnchorIDWithoutSideSuffixIsNotRewritten() {
        let id: FaceAnchorID = "glabella_center"
        XCTAssertEqual(id.resolved(for: .left), "glabella_center")
        XCTAssertEqual(id.resolved(for: .right), "glabella_center")
        XCTAssertEqual(id.mirrored, "glabella_center")
    }

    // MARK: - 完整 3 分钟闭环

    func testFullThreeMinuteRoutineCompletes() throws {
        let bundle = try BundledContent.makeRepository(failOnValidationError: false).load()
        let morning = try XCTUnwrap(bundle.morningCore)
        let plan = PlaybackPlan(routine: morning, prepareCountdownSeconds: 3)

        let engine = RoutinePlayerEngine(plan: plan)
        var completedSegments: [Int] = []
        var completionSeconds: Double?
        engine.onEvent = { event in
            switch event {
            case let .segmentDidComplete(index): completedSegments.append(index)
            case let .routineCompleted(seconds): completionSeconds = seconds
            default: break
            }
        }

        engine.start()
        XCTAssertEqual(engine.status, .preparing)

        // 准备倒计时 + 完整 routine + 一点余量
        advance(engine, seconds: 3 + plan.totalDurationSeconds + 1)

        XCTAssertEqual(engine.status, .completed)
        XCTAssertEqual(completionSeconds, plan.totalDurationSeconds)
        XCTAssertEqual(plan.totalDurationSeconds, 180, "Morning Core 应为 180 秒")

        // 段数不写死：内容换一批动作就会变，写死等于每次改内容都要改测试。
        // 真正要断言的是「展开规则正确」与「每一段都走完了」。
        let expectedSegmentCount = morning.steps.reduce(0) { $0 + ($1.side == .leftThenRight ? 2 : 1) }
        XCTAssertEqual(plan.segments.count, expectedSegmentCount, "leftThenRight 应展开成两段，其余一段")
        XCTAssertEqual(completedSegments.count, plan.segments.count, "每一段都必须走完")
        XCTAssertEqual(completedSegments, Array(0..<plan.segments.count), "段必须按顺序完成，且一段都不能丢")
    }

    func testSegmentBoundariesLandAtExpectedTimes() {
        let routine = makeRoutine(steps: [("a", 10, .none), ("b", 10, .none), ("c", 10, .none)])
        let engine = RoutinePlayerEngine(plan: PlaybackPlan(routine: routine, prepareCountdownSeconds: 0))

        var starts: [(index: Int, elapsed: Double)] = []
        engine.onEvent = { event in
            if case let .segmentWillStart(index, _) = event {
                starts.append((index, engine.totalElapsed))
            }
        }
        engine.start()
        advance(engine, seconds: 30.5)

        XCTAssertEqual(starts.map(\.index), [0, 1, 2])
        XCTAssertEqual(starts[0].elapsed, 0, accuracy: 1e-9)
        XCTAssertEqual(starts[1].elapsed, 10, accuracy: 1e-9)
        XCTAssertEqual(starts[2].elapsed, 20, accuracy: 1e-9)
        XCTAssertEqual(engine.status, .completed)
    }

    /// 掉帧保护：单帧时长跨过整段时不能丢段。
    func testSingleLargeTickDoesNotSkipSegmentEvents() {
        let routine = makeRoutine(steps: [("a", 2, .none), ("b", 2, .none), ("c", 2, .none)])
        let engine = RoutinePlayerEngine(plan: PlaybackPlan(routine: routine, prepareCountdownSeconds: 0))

        var completed: [Int] = []
        engine.onEvent = { event in
            if case let .segmentDidComplete(index) = event { completed.append(index) }
        }
        engine.start()
        engine.tick(deltaTime: 5.0)   // 一帧跨过 2.5 段

        XCTAssertEqual(completed, [0, 1])
        XCTAssertEqual(engine.currentSegmentIndex, 2)
        XCTAssertEqual(engine.elapsedInSegment, 1.0, accuracy: 1e-9)
    }

    // MARK: - 控制

    func testPauseFreezesTimeAndResumeContinues() {
        let routine = makeRoutine(steps: [("a", 10, .none)])
        let engine = RoutinePlayerEngine(plan: PlaybackPlan(routine: routine, prepareCountdownSeconds: 0))
        engine.start()
        advance(engine, seconds: 4)

        let elapsedAtPause = engine.totalElapsed
        engine.pause()
        advance(engine, seconds: 5)
        XCTAssertEqual(engine.totalElapsed, elapsedAtPause, accuracy: 1e-9, "暂停期间时间不应推进")

        engine.resume()
        advance(engine, seconds: 2)
        XCTAssertEqual(engine.totalElapsed, elapsedAtPause + 2, accuracy: 1e-9)
        XCTAssertEqual(engine.status, .running)
    }

    func testSkipForwardMovesToNextSegment() {
        let routine = makeRoutine(steps: [("a", 10, .none), ("b", 10, .none)])
        let engine = RoutinePlayerEngine(plan: PlaybackPlan(routine: routine, prepareCountdownSeconds: 0))
        engine.start()
        advance(engine, seconds: 3)

        engine.skipForward()
        XCTAssertEqual(engine.currentSegmentIndex, 1)
        XCTAssertEqual(engine.elapsedInSegment, 0, accuracy: 1e-9)
        XCTAssertEqual(engine.totalElapsed, 10, accuracy: 1e-9)
    }

    func testSkipBackwardRestartsCurrentSegmentWhenPastTwoSeconds() {
        let routine = makeRoutine(steps: [("a", 10, .none), ("b", 10, .none)])
        let engine = RoutinePlayerEngine(plan: PlaybackPlan(routine: routine, prepareCountdownSeconds: 0))
        engine.start()
        engine.skipForward()
        advance(engine, seconds: 5)

        engine.skipBackward()
        XCTAssertEqual(engine.currentSegmentIndex, 1, "段内已过 2 秒 → 回到本段开头")
        XCTAssertEqual(engine.elapsedInSegment, 0, accuracy: 1e-9)

        engine.skipBackward()
        XCTAssertEqual(engine.currentSegmentIndex, 0, "段内不足 2 秒 → 跳到上一段")
    }

    func testCancelReportsPartialProgress() throws {
        let routine = makeRoutine(steps: [("a", 10, .none), ("b", 10, .none)])
        let engine = RoutinePlayerEngine(plan: PlaybackPlan(routine: routine, prepareCountdownSeconds: 0))

        var cancelledAt: Double?
        engine.onEvent = { if case let .cancelled(seconds) = $0 { cancelledAt = seconds } }

        engine.start()
        advance(engine, seconds: 7)
        engine.cancel()

        XCTAssertEqual(engine.status, .cancelled)
        XCTAssertEqual(try XCTUnwrap(cancelledAt), 7, accuracy: 1e-9)
    }

    // MARK: - 节奏

    func testCyclePhaseFollowsTempo() {
        let step = RoutineStep(
            id: "s",
            title: "s",
            durationSeconds: 12,
            shortCue: "cue",
            // 20 次/分 → 每循环 3 秒
            movement: MovementSpec(pathType: .circle, tempoCyclesPerMinute: 20, repetitions: 4)
        )
        let engine = RoutinePlayerEngine(
            plan: PlaybackPlan(
                routine: Routine(id: "r", title: "r", type: .morning, isPremium: false, steps: [step]),
                prepareCountdownSeconds: 0
            )
        )
        engine.start()

        advance(engine, seconds: 1.5)
        XCTAssertEqual(engine.cyclePhase, 0.5, accuracy: 0.02, "3 秒周期走到 1.5 秒应是半个循环")
        XCTAssertEqual(engine.completedRepetitions, 0)

        advance(engine, seconds: 3.0)
        XCTAssertEqual(engine.completedRepetitions, 1)
    }

    func testSideChangeEventFiresOncePerSideTransition() {
        let routine = makeRoutine(steps: [("a", 4, .leftThenRight), ("b", 4, .leftThenRight)])
        let engine = RoutinePlayerEngine(plan: PlaybackPlan(routine: routine, prepareCountdownSeconds: 0))

        var sides: [BodySide] = []
        engine.onEvent = { if case let .sideDidChange(side) = $0 { sides.append(side) } }

        engine.start()
        advance(engine, seconds: 9)

        // left → right → left → right
        XCTAssertEqual(sides, [.left, .right, .left, .right])
    }
}
