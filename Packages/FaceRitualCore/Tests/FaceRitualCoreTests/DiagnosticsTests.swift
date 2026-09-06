import XCTest
@testable import FaceRitualCore

/// `StabilityMeter` 的期望值全部在 Python 里独立算过一遍
/// （和 golden vector 一个路子）——
/// 断言里的数字不是从 Swift 输出里抄回来的，否则测试只会证明"代码等于它自己"。
final class StabilityMeterTests: XCTestCase {

    func testConstantPointHasNoDriftAndNoJitter() {
        var meter = StabilityMeter()
        for _ in 0..<200 {
            meter.record(localPoint: Point2D(x: -0.31, y: 0.42))
        }
        XCTAssertEqual(meter.sampleCount, 200)
        XCTAssertEqual(meter.center.x, -0.31, accuracy: 1e-12)
        XCTAssertEqual(meter.center.y, 0.42, accuracy: 1e-12)
        XCTAssertEqual(meter.driftRMS, 0, accuracy: 1e-12)
        XCTAssertEqual(meter.driftP95, 0, accuracy: 1e-12)
        XCTAssertEqual(meter.jitterMedian, 0, accuracy: 1e-12)
    }

    /// 在 ±0.02 瞳距之间来回跳：漂移是 0.02，但**抖动是 0.04** ——
    /// 两个指标必须能区分开，否则调滤波时不知道该动哪个参数。
    func testAlternatingPointSeparatesDriftFromJitter() {
        var meter = StabilityMeter()
        for index in 0..<50 {
            meter.record(localPoint: Point2D(x: index.isMultiple(of: 2) ? 0 : 0.04, y: 0))
        }
        XCTAssertEqual(meter.center.x, 0.020, accuracy: 1e-12)
        XCTAssertEqual(meter.driftRMS, 0.020, accuracy: 1e-12)
        XCTAssertEqual(meter.driftP95, 0.020, accuracy: 1e-12)
        XCTAssertEqual(meter.jitterMedian, 0.040, accuracy: 1e-12)
    }

    /// 线性斜坡 —— 覆盖分位数的插值分支。
    /// 期望值由 Python 参考实现给出。
    func testLinearRampMatchesReferenceStatistics() {
        var meter = StabilityMeter()
        for index in 0..<100 {
            meter.record(localPoint: Point2D(x: Double(index) * 0.001, y: 0))
        }
        XCTAssertEqual(meter.center.x, 0.049500000000, accuracy: 1e-9)
        XCTAssertEqual(meter.driftRMS, 0.028866070048, accuracy: 1e-9)
        XCTAssertEqual(meter.driftP95, 0.047500000000, accuracy: 1e-9)
        XCTAssertEqual(meter.driftMax, 0.049500000000, accuracy: 1e-9)
        XCTAssertEqual(meter.jitterMedian, 0.001000000000, accuracy: 1e-9)
        XCTAssertEqual(meter.jitterP95, 0.001000000000, accuracy: 1e-9)
    }

    /// 超出容量后必须是环形覆盖，不能无限增长 —— 它跑在每一帧上。
    func testCapacityIsBounded() {
        var meter = StabilityMeter(capacity: 10)
        for index in 0..<1000 {
            meter.record(localPoint: Point2D(x: Double(index), y: 0))
        }
        XCTAssertEqual(meter.sampleCount, 10, "样本数必须被容量限制住")
        // 最后 10 个点是 990…999，中心应落在这一段里。
        XCTAssertGreaterThan(meter.center.x, 980)
    }

    func testDriftRatioComparesAgainstTolerance() {
        var meter = StabilityMeter()
        for index in 0..<50 {
            meter.record(localPoint: Point2D(x: index.isMultiple(of: 2) ? 0 : 0.04, y: 0))
        }
        // 漂移 p95 = 0.02，容差 0.20 → 占容差圈的十分之一。
        XCTAssertEqual(meter.driftRatio(toleranceRadius: 0.20), 0.1, accuracy: 1e-9)
    }
}

final class POCRecorderTests: XCTestCase {

    private let anchor: FaceAnchorID = "temple_left"

    private func feed(_ recorder: POCRecorder, quality: GuidanceQuality, x: Double, times: Int = 1) {
        for _ in 0..<times {
            recorder.record(
                quality: quality,
                anchorLocalPoints: [anchor: Point2D(x: x, y: 0)],
                toleranceRadii: [anchor: 0.18]
            )
        }
    }

    func testQualityRatiosSumToOne() throws {
        let recorder = POCRecorder()
        recorder.begin(scenario: POCRecorder.standardScenarios[0])
        feed(recorder, quality: .good, x: 0, times: 6)
        feed(recorder, quality: .degraded, x: 0, times: 3)
        feed(recorder, quality: .lost, x: 0, times: 1)

        let measurement = try XCTUnwrap(recorder.finish(
            providerID: "test", averageFPS: 30, averageLatencyMS: 10,
            p95LatencyMS: 15, stutterCount: 0, lockLossCount: 0, timeToFirstLockSeconds: 1
        ))

        XCTAssertEqual(measurement.frameCount, 10)
        XCTAssertEqual(measurement.goodRatio, 0.6, accuracy: 1e-12)
        XCTAssertEqual(measurement.degradedRatio, 0.3, accuracy: 1e-12)
        XCTAssertEqual(measurement.lostRatio, 0.1, accuracy: 1e-12)
        XCTAssertEqual(
            measurement.goodRatio + measurement.degradedRatio + measurement.lostRatio,
            1.0, accuracy: 1e-12
        )
    }

    /// lost 帧的位置本来就没有意义，混进稳定性统计会让漂移虚高，
    /// 反而掩盖真实问题。
    func testLostFramesAreExcludedFromStability() throws {
        let recorder = POCRecorder()
        recorder.begin(scenario: POCRecorder.standardScenarios[0])
        feed(recorder, quality: .good, x: 0.5, times: 20)
        // 一堆位置离谱的 lost 帧
        feed(recorder, quality: .lost, x: 99.0, times: 20)

        let measurement = try XCTUnwrap(recorder.finish(
            providerID: "test", averageFPS: 30, averageLatencyMS: 10,
            p95LatencyMS: 15, stutterCount: 0, lockLossCount: 3, timeToFirstLockSeconds: nil
        ))

        let snapshot = try XCTUnwrap(measurement.stability.first)
        XCTAssertEqual(snapshot.sampleCount, 20, "只有非 lost 的帧参与位置统计")
        XCTAssertEqual(snapshot.driftP95, 0, accuracy: 1e-12, "20 个相同的点不应产生漂移")
        XCTAssertEqual(measurement.lostRatio, 0.5, accuracy: 1e-12, "但 lost 仍要计入质量分布")
    }

    func testRecordingOutsideAScenarioIsIgnored() {
        let recorder = POCRecorder()
        feed(recorder, quality: .good, x: 0, times: 10)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.currentFrameCount, 0)
        XCTAssertNil(recorder.finish(
            providerID: "test", averageFPS: 0, averageLatencyMS: 0,
            p95LatencyMS: 0, stutterCount: 0, lockLossCount: 0, timeToFirstLockSeconds: nil
        ))
    }

    func testReportRoundTripsThroughJSON() throws {
        let recorder = POCRecorder()
        recorder.begin(scenario: POCRecorder.standardScenarios[1])
        feed(recorder, quality: .good, x: 0.1, times: 5)
        _ = recorder.finish(
            providerID: "vision", averageFPS: 29.5, averageLatencyMS: 12,
            p95LatencyMS: 21, stutterCount: 1, lockLossCount: 0,
            timeToFirstLockSeconds: 0.8, note: "手动备注"
        )

        let report = recorder.makeReport(
            deviceModel: "iPhone", systemVersion: "17.0",
            appVersion: "0.1", contentVersion: "0.3.0-draft"
        )
        let data = try report.encodedJSON()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(POCRecorder.Report.self, from: data)

        XCTAssertEqual(decoded.measurements.count, 1)
        XCTAssertEqual(decoded.measurements[0].providerID, "vision")
        XCTAssertEqual(decoded.measurements[0].note, "手动备注")
        XCTAssertEqual(decoded.contentVersion, "0.3.0-draft")
        XCTAssertFalse(report.markdownTable.isEmpty)
        XCTAssertTrue(report.markdownTable.contains("vision"))
    }

    /// 场景标签固定成一份表，不让人自由填 ——
    /// 自由填的结果是三个人测出三套对不上的数据。
    func testStandardScenariosHaveUniqueIDs() {
        let ids = POCRecorder.standardScenarios.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "场景 id 不得重复")
        XCTAssertFalse(POCRecorder.standardScenarios.isEmpty)
    }
}
