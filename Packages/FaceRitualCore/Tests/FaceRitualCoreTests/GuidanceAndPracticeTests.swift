import XCTest
@testable import FaceRitualCore

final class GuidanceQualityTests: XCTestCase {

    private func geometry(
        state: FaceTrackingState = .locked,
        confidence: Double = 1.0,
        occludedFraction: Double = 0,
        pose: HeadPose = .neutral,
        faceHeight: Double = 400,
        viewHeight: Double = 800
    ) -> FaceGeometry {
        // 构造一张最小可用的合成脸（含全部 required landmark）。
        let base: [SemanticLandmark: Point2D] = [
            .leftEyeCenter: Point2D(x: 150, y: 300),
            .rightEyeCenter: Point2D(x: 250, y: 300),
            .noseTip: Point2D(x: 200, y: 362),
            .chinCenter: Point2D(x: 200, y: 472),
            .leftBrowInner: Point2D(x: 178, y: 268),
            .rightBrowInner: Point2D(x: 222, y: 268),
            .leftEyeOuter: Point2D(x: 122, y: 300),
            .leftMouthCorner: Point2D(x: 158, y: 405),
            .leftJawAngle: Point2D(x: 108, y: 425),
            .rightJawAngle: Point2D(x: 292, y: 425)
        ]
        let ordered = base.keys.sorted { $0.rawValue < $1.rawValue }
        let occludeCount = Int((Double(ordered.count) * occludedFraction).rounded())
        var table: [SemanticLandmark: LandmarkSample] = [:]
        for (index, mark) in ordered.enumerated() {
            table[mark] = LandmarkSample(
                point: base[mark]!,
                confidence: confidence,
                isOccluded: index < occludeCount
            )
        }
        return FaceGeometry(
            providerID: "test",
            timestamp: 0,
            trackingState: state,
            pose: pose,
            landmarks: table,
            boundingBox: Rect2D(x: 100, y: 250, width: 200, height: faceHeight),
            viewSize: Size2D(width: 400, height: viewHeight),
            overallConfidence: confidence
        )
    }

    private func assess(_ input: FaceGeometry, policy: OcclusionPolicy = .continueGuidance) -> GuidanceAssessment {
        GuidanceQualityEvaluator().assess(geometry: input, frame: FaceFrame(geometry: input), policy: policy)
    }

    func testCleanFaceIsGoodQuality() {
        let result = assess(geometry())
        XCTAssertEqual(result.quality, .good)
        XCTAssertEqual(result.hint, .none)
        XCTAssertEqual(result.overlayOpacity, 1.0)
        XCTAssertFalse(result.shouldFreezeOverlay)
    }

    func testUndetectedFaceIsLostNotAnError() {
        let result = assess(geometry(state: .notDetected))
        XCTAssertEqual(result.quality, .lost)
        XCTAssertEqual(result.hint, .faceNotFound)
    }

    func testHeavyOcclusionFreezesOverlayButKeepsGuiding() {
        // 手遮住脸是正常按摩动作，不是错误 —— 必须继续计时与语音。
        let result = assess(geometry(occludedFraction: 0.8), policy: .continueGuidance)
        XCTAssertEqual(result.quality, .lost)
        XCTAssertEqual(result.hint, .handCoveringFace)
        XCTAssertTrue(result.shouldFreezeOverlay, "应冻结在最后可信位置，而不是消失")
        XCTAssertGreaterThan(result.overlayOpacity, 0, "continueGuidance 下 overlay 不应完全隐藏")
    }

    func testMildOcclusionOnlyDegrades() {
        let result = assess(geometry(occludedFraction: 0.3))
        XCTAssertEqual(result.quality, .degraded)
        XCTAssertFalse(result.shouldFreezeOverlay)
    }

    func testLargeHeadTurnIsLost() {
        let result = assess(geometry(pose: HeadPose(yawDegrees: 45)))
        XCTAssertEqual(result.quality, .lost)
        XCTAssertEqual(result.hint, .reduceHeadTurn)
    }

    func testModerateHeadTurnOnlyDegrades() {
        let result = assess(geometry(pose: HeadPose(yawDegrees: 28)))
        XCTAssertEqual(result.quality, .degraded)
        XCTAssertEqual(result.hint, .reduceHeadTurn)
    }

    func testFaceTooSmallAsksUserToMoveCloser() {
        let result = assess(geometry(faceHeight: 80, viewHeight: 800))
        XCTAssertEqual(result.quality, .lost)
        XCTAssertEqual(result.hint, .moveCloser)
    }

    func testPauseTrackingPolicyHidesOverlayEntirely() {
        let result = assess(geometry(occludedFraction: 0.8), policy: .pauseTracking)
        XCTAssertEqual(result.overlayOpacity, 0)
        XCTAssertFalse(result.shouldFreezeOverlay)
    }

    /// 结构性保证：GuidanceQuality 只描述「导航准不准」，
    /// 永远不描述「用户做得对不对」（规格 §10）。
    func testGuidanceQualityHasNoCorrectnessVerdict() {
        let cases: [GuidanceQuality] = [.good, .degraded, .lost]
        XCTAssertEqual(Set(cases.map(\.rawValue)), ["good", "degraded", "lost"])
    }
}

final class FaceLockTrackerTests: XCTestCase {

    private func assessment(_ quality: GuidanceQuality) -> GuidanceAssessment {
        GuidanceAssessment(quality: quality, hint: .none, overlayOpacity: 1, shouldFreezeOverlay: false)
    }

    func testLockRequiresConsecutiveGoodFrames() throws {
        var tracker = FaceLockTracker(requiredGoodFrames: 5, requiredBadFrames: 5)
        tracker.start(at: 0)

        for index in 0..<4 {
            tracker.update(assessment: assessment(.good), timestamp: Double(index) / 60)
            XCTAssertNotEqual(tracker.state, .locked, "不足 5 帧不应判定为 locked")
        }
        tracker.update(assessment: assessment(.good), timestamp: 5.0 / 60)
        XCTAssertEqual(tracker.state, .locked)
        XCTAssertEqual(try XCTUnwrap(tracker.timeToFirstLock), 5.0 / 60, accuracy: 1e-9)
    }

    func testLockLossIsCountedOnce() {
        var tracker = FaceLockTracker(requiredGoodFrames: 2, requiredBadFrames: 2)
        tracker.start(at: 0)
        tracker.update(assessment: assessment(.good), timestamp: 0)
        tracker.update(assessment: assessment(.good), timestamp: 1)
        XCTAssertEqual(tracker.state, .locked)

        XCTAssertFalse(tracker.update(assessment: assessment(.lost), timestamp: 2), "第一帧掉落还不算丢锁")
        XCTAssertTrue(tracker.update(assessment: assessment(.lost), timestamp: 3), "达到阈值才算一次丢锁")
        XCTAssertEqual(tracker.lockLossCount, 1)

        tracker.update(assessment: assessment(.lost), timestamp: 4)
        XCTAssertEqual(tracker.lockLossCount, 1, "持续丢失不应重复计数")
    }

    func testSingleBadFrameDoesNotBreakLock() {
        var tracker = FaceLockTracker(requiredGoodFrames: 2, requiredBadFrames: 10)
        tracker.start(at: 0)
        tracker.update(assessment: assessment(.good), timestamp: 0)
        tracker.update(assessment: assessment(.good), timestamp: 1)

        tracker.update(assessment: assessment(.degraded), timestamp: 2)
        XCTAssertEqual(tracker.state, .locked, "偶发抖动不应让 overlay 闪烁")
        XCTAssertEqual(tracker.lockLossCount, 0)
    }
}

final class OneEuroFilterTests: XCTestCase {

    func testFilterSuppressesJitterAroundAConstantValue() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.0)
        let noise: [Double] = [100, 103, 97, 104, 96, 102, 98, 101, 99, 100]

        var output: [Double] = []
        for (index, value) in noise.enumerated() {
            output.append(filter.filter(value, timestamp: Double(index) / 60))
        }

        let inputSpread = (noise.max()! - noise.min()!)
        let settled = Array(output.dropFirst(3))
        let outputSpread = (settled.max()! - settled.min()!)
        XCTAssertLessThan(outputSpread, inputSpread / 2, "静止时应显著抑制抖动")
    }

    func testFilterTracksFastMotionWithoutExcessiveLag() {
        // beta 较大 → 快速运动时放宽滤波，减少滞后。
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 1.0)
        var last = 0.0
        for index in 0..<40 {
            last = filter.filter(Double(index) * 10, timestamp: Double(index) / 60)
        }
        let target = 39.0 * 10
        XCTAssertEqual(last, target, accuracy: target * 0.15, "快速平移时滞后不应超过 15%")
    }

    func testFilterResetsOnTimeGap() {
        var filter = OneEuroFilter()
        _ = filter.filter(100, timestamp: 0)
        // 切后台再回来：时间跳变必须重置，而不是产生一次巨大的速度尖峰。
        let value = filter.filter(500, timestamp: 30)
        XCTAssertEqual(value, 500, accuracy: 1e-9)
    }
}

final class PracticeStatsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func session(at date: Date, seconds: Double = 180, completed: Bool = true) -> PracticeSession {
        PracticeSession(
            routineID: "morning_core",
            routineTitle: "Morning Ritual",
            routineType: .morning,
            startedAt: date,
            completedAt: completed ? date.addingTimeInterval(seconds) : nil,
            completed: completed,
            secondsCompleted: seconds,
            mode: .coach
        )
    }

    func testMonthlyStatsCountsOnlyThatMonth() {
        let sessions = [
            session(at: date(2026, 9, 1)),
            session(at: date(2026, 9, 2)),
            session(at: date(2026, 9, 2, hour: 20)),
            session(at: date(2026, 8, 31))
        ]
        let stats = PracticeStatsCalculator.monthlyStats(
            sessions: sessions,
            year: 2026,
            month: 9,
            calendar: calendar,
            now: date(2026, 9, 3)
        )
        XCTAssertEqual(stats.sessionCount, 3)
        XCTAssertEqual(stats.completedCount, 3)
        XCTAssertEqual(stats.activeDays, 2, "同一天两次只算一个活跃日")
        XCTAssertEqual(stats.totalMinutes, 9, accuracy: 1e-9)
    }

    func testIncompleteSessionsStillCountMinutes() {
        let sessions = [session(at: date(2026, 9, 1), seconds: 60, completed: false)]
        let stats = PracticeStatsCalculator.monthlyStats(
            sessions: sessions, year: 2026, month: 9, calendar: calendar, now: date(2026, 9, 1)
        )
        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.completedCount, 0)
        XCTAssertEqual(stats.totalMinutes, 1, accuracy: 1e-9)
    }

    func testStreakCountsBackFromToday() {
        let sessions = [date(2026, 9, 3), date(2026, 9, 4), date(2026, 9, 5)].map { session(at: $0) }
        let streak = PracticeStatsCalculator.currentStreak(sessions: sessions, calendar: calendar, now: date(2026, 9, 5, hour: 22))
        XCTAssertEqual(streak, 3)
    }

    /// 规格 §12：今天还没练不算断签 —— 不制造断签焦虑。
    func testTodayNotYetPracticedDoesNotBreakStreak() {
        let sessions = [date(2026, 9, 3), date(2026, 9, 4)].map { session(at: $0) }
        let streak = PracticeStatsCalculator.currentStreak(sessions: sessions, calendar: calendar, now: date(2026, 9, 5, hour: 9))
        XCTAssertEqual(streak, 2)
    }

    func testGapBreaksStreak() {
        let sessions = [date(2026, 9, 1), date(2026, 9, 2), date(2026, 9, 5)].map { session(at: $0) }
        let streak = PracticeStatsCalculator.currentStreak(sessions: sessions, calendar: calendar, now: date(2026, 9, 5, hour: 22))
        XCTAssertEqual(streak, 1)
    }

    func testEmptyHistoryHasZeroStreak() {
        XCTAssertEqual(PracticeStatsCalculator.currentStreak(sessions: [], calendar: calendar, now: date(2026, 9, 5)), 0)
    }

    func testInMemoryStoreUpsertsById() throws {
        let store = InMemoryPracticeStore()
        var record = session(at: date(2026, 9, 5), seconds: 60, completed: false)
        try store.save(record)

        record.secondsCompleted = 180
        record.completed = true
        try store.save(record)

        XCTAssertEqual(store.allSessions().count, 1, "同一 id 应更新而不是追加")
        XCTAssertTrue(store.allSessions()[0].completed)
        XCTAssertEqual(store.allSessions()[0].secondsCompleted, 180)
    }

    func testFileStoreRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("faceritual-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FilePracticeStore(fileURL: url)
        try store.save(session(at: date(2026, 9, 5)))

        let reopened = FilePracticeStore(fileURL: url)
        XCTAssertEqual(reopened.allSessions().count, 1)
        XCTAssertEqual(reopened.allSessions()[0].routineID, "morning_core")
    }

    func testCorruptedStoreFileDegradesToEmptyInsteadOfCrashing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("faceritual-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ not json".utf8).write(to: url)

        XCTAssertEqual(FilePracticeStore(fileURL: url).allSessions(), [], "记录损坏不应让 App 打不开")
    }

    /// 练习记录是用户数据。加新字段绝不能让旧记录整体解码失败 ——
    /// 那会连带 FilePracticeStore 返回空数组，等于静默清空历史。
    func testOldRecordWithoutNewFieldsStillDecodes() throws {
        // 模拟一条「didFallBackToCoach / faceProviderID 都还不存在」时期写下的记录。
        let legacy = """
        {
          "id": "legacy-1",
          "routineID": "morning_core",
          "routineTitle": "Morning Ritual",
          "routineType": "morning",
          "startedAt": "2026-09-01T08:00:00Z",
          "completed": true,
          "secondsCompleted": 180,
          "mode": "coach",
          "arMirrorUsed": false,
          "faceLockLossCount": 0,
          "contentVersion": "0.1.0-mock"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PracticeSession.self, from: legacy)

        XCTAssertEqual(session.routineID, "morning_core")
        XCTAssertEqual(session.secondsCompleted, 180)
        XCTAssertFalse(session.didFallBackToCoach, "缺失的新字段应取默认值，而不是解码失败")
        XCTAssertNil(session.faceProviderID)
    }

    func testMinimalRecordDecodesWithDefaults() throws {
        let minimal = """
        { "id": "m1", "routineID": "r", "startedAt": "2026-09-01T08:00:00Z" }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PracticeSession.self, from: minimal)

        XCTAssertEqual(session.mode, .coach)
        XCTAssertEqual(session.routineType, .morning)
        XCTAssertFalse(session.completed)
        XCTAssertEqual(session.secondsCompleted, 0)
    }

    /// 损坏的记录文件必须被隔离留存，而不是被下一次写入直接覆盖掉。
    func testCorruptedFileIsQuarantinedNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("faceritual-quarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("practice_sessions.json")
        try Data("{ not json".utf8).write(to: fileURL)

        let store = FilePracticeStore(fileURL: fileURL)
        XCTAssertEqual(store.allSessions(), [])
        XCTAssertTrue(store.lastReadWasCorrupted)

        let quarantined = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("corrupt") }
        XCTAssertEqual(quarantined.count, 1, "坏文件应被改名留存，供人工恢复")
    }
}

