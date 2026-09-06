import Foundation

/// 真机 AR POC 的测量记录器。
///
/// 存在的理由：`AR_POC_REPORT.md` §2 原本要求人肉观察九项指标再手填表格。
/// 那样做出来的数据既费事又不可比 —— "有点漂"和"还行"没法拿去和另一个 provider 比，
/// 也没法在调完滤波参数之后判断到底变好了没有。
///
/// 这个类把同样的九项变成**按场景标注的数值**，测完导出一份 JSON。
/// 测试者要做的只是：进入某个场景 → 点一下开始 → 保持十几秒 → 点结束。
///
/// 它**不做任何"用户做得对不对"的判断**（规格 §10）。
/// 它记录的是**系统自己的表现**：识别质量、帧率、位置稳定性。
/// 这两件事完全不同 —— 前者我们明确不做，后者正是 POC 要回答的问题。
public final class POCRecorder: @unchecked Sendable {

    /// 正在测的场景。标签由测试者从预置列表里选，保证不同人测出来的能对上。
    public struct Scenario: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var label: String
        /// 对应 AR_POC_REPORT.md §2 的哪一节。
        public var section: String

        public init(id: String, label: String, section: String) {
            self.id = id
            self.label = label
            self.section = section
        }
    }

    /// 预置场景表 —— 直接对应 POC 报告里的表格行。
    ///
    /// 固定这份列表而不是让人自由填标签：自由填的结果是三个人测出三套
    /// 对不上的数据，最后谁也没法比。
    public static let standardScenarios: [Scenario] = [
        .init(id: "dist_15", label: "很近 · 约 15cm", section: "B 距离"),
        .init(id: "dist_30", label: "正常 · 约 30cm", section: "B 距离"),
        .init(id: "dist_60", label: "较远 · 约 60cm", section: "B 距离"),
        .init(id: "dist_100", label: "很远 · 约 1m", section: "B 距离"),
        .init(id: "pose_up", label: "轻微抬头 · 约 15°", section: "C 头部姿态"),
        .init(id: "pose_down", label: "轻微低头 · 约 15°", section: "C 头部姿态"),
        .init(id: "pose_yaw20", label: "转头 · 约 20°", section: "C 头部姿态"),
        .init(id: "pose_yaw40", label: "大幅转头 · 约 40°", section: "C 头部姿态"),
        .init(id: "still", label: "静止不动", section: "D 漂移"),
        .init(id: "sway", label: "缓慢左右平移", section: "D 漂移"),
        .init(id: "occl_finger", label: "单指点在脸上", section: "E 手遮挡"),
        .init(id: "occl_twofinger", label: "两指划过", section: "E 手遮挡"),
        .init(id: "occl_palm", label: "手掌盖住半张脸", section: "E 手遮挡"),
        .init(id: "routine", label: "完整走一遍 routine", section: "A 基础运行"),
    ]

    /// 一个场景测完的结果。
    public struct Measurement: Codable, Hashable, Sendable {
        public var scenario: Scenario
        public var providerID: String
        public var durationSeconds: Double
        public var frameCount: Int

        // 帧率与延迟
        public var averageFPS: Double
        public var averageLatencyMS: Double
        public var p95LatencyMS: Double
        public var stutterCount: Int

        // 识别质量分布（占比 0…1）。这是"在这个场景下还撑不撑得住"的直接答案。
        public var goodRatio: Double
        public var degradedRatio: Double
        public var lostRatio: Double
        public var lockLossCount: Int
        public var timeToFirstLockSeconds: Double?

        /// 被跟踪 anchor 的位置稳定性。单位=瞳距。
        public var stability: [StabilitySnapshot]

        /// 测试者补的一句话。数值答不了"看起来怎么样"。
        public var note: String?

        public init(
            scenario: Scenario,
            providerID: String,
            durationSeconds: Double,
            frameCount: Int,
            averageFPS: Double,
            averageLatencyMS: Double,
            p95LatencyMS: Double,
            stutterCount: Int,
            goodRatio: Double,
            degradedRatio: Double,
            lostRatio: Double,
            lockLossCount: Int,
            timeToFirstLockSeconds: Double?,
            stability: [StabilitySnapshot],
            note: String? = nil
        ) {
            self.scenario = scenario
            self.providerID = providerID
            self.durationSeconds = durationSeconds
            self.frameCount = frameCount
            self.averageFPS = averageFPS
            self.averageLatencyMS = averageLatencyMS
            self.p95LatencyMS = p95LatencyMS
            self.stutterCount = stutterCount
            self.goodRatio = goodRatio
            self.degradedRatio = degradedRatio
            self.lostRatio = lostRatio
            self.lockLossCount = lockLossCount
            self.timeToFirstLockSeconds = timeToFirstLockSeconds
            self.stability = stability
            self.note = note
        }
    }

    /// 导出的完整报告。
    public struct Report: Codable, Sendable {
        public var schemaVersion: Int
        public var recordedAt: Date
        public var deviceModel: String
        public var systemVersion: String
        public var appVersion: String
        public var contentVersion: String
        public var measurements: [Measurement]

        public init(
            schemaVersion: Int = 1,
            recordedAt: Date = Date(),
            deviceModel: String,
            systemVersion: String,
            appVersion: String,
            contentVersion: String,
            measurements: [Measurement]
        ) {
            self.schemaVersion = schemaVersion
            self.recordedAt = recordedAt
            self.deviceModel = deviceModel
            self.systemVersion = systemVersion
            self.appVersion = appVersion
            self.contentVersion = contentVersion
            self.measurements = measurements
        }

        public func encodedJSON() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(self)
        }

        /// 人能直接读的摘要，贴进 AR_POC_REPORT.md 就是一张表。
        public var markdownTable: String {
            var lines: [String] = []
            lines.append("| 场景 | provider | 时长 | FPS | p95延迟 | good | degraded | lost | 漂移p95(瞳距) | 漂移/容差 |")
            lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
            for m in measurements {
                let worst = m.stability.max { $0.driftP95 < $1.driftP95 }
                let drift = worst.map { String(format: "%.3f", $0.driftP95) } ?? "—"
                let ratio = worst.map { String(format: "%.2f", $0.driftRatio) } ?? "—"
                lines.append(String(
                    format: "| %@ | %@ | %.0fs | %.1f | %.0fms | %.0f%% | %.0f%% | %.0f%% | %@ | %@ |",
                    m.scenario.label, m.providerID, m.durationSeconds,
                    m.averageFPS, m.p95LatencyMS,
                    m.goodRatio * 100, m.degradedRatio * 100, m.lostRatio * 100,
                    drift, ratio
                ))
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - 采集

    private var meters: [FaceAnchorID: StabilityMeter] = [:]
    private var tolerances: [FaceAnchorID: Double] = [:]
    private var qualityCounts: [GuidanceQuality: Int] = [:]
    private var frameCount = 0
    private var activeScenario: Scenario?
    private var startedAt: Date?

    /// 每个 anchor 保留多少帧样本。30fps 下 900 帧 = 30 秒。
    /// 单个场景本来就只测十几二十秒，再长的窗口只是白占内存
    /// （27 个 anchor × 900 × 16B ≈ 390KB）。
    private let sampleCapacity: Int

    public init(sampleCapacity: Int = 900) {
        self.sampleCapacity = max(2, sampleCapacity)
    }

    public private(set) var completed: [Measurement] = []

    public var isRecording: Bool { activeScenario != nil }
    public var currentScenario: Scenario? { activeScenario }
    public var currentFrameCount: Int { frameCount }

    public func begin(scenario: Scenario) {
        meters.removeAll()
        tolerances.removeAll()
        qualityCounts.removeAll()
        frameCount = 0
        activeScenario = scenario
        startedAt = Date()
    }

    public func cancel() {
        activeScenario = nil
        startedAt = nil
    }

    /// 每帧调一次。
    ///
    /// `anchorLocalPoints` 必须是**脸部局部坐标**（单位=瞳距）。
    /// 传屏幕坐标进来的话，测出的"漂移"里会混进头部真实移动，数字就没有意义了。
    public func record(
        quality: GuidanceQuality,
        anchorLocalPoints: [FaceAnchorID: Point2D],
        toleranceRadii: [FaceAnchorID: Double]
    ) {
        guard activeScenario != nil else { return }
        frameCount += 1
        qualityCounts[quality, default: 0] += 1

        // 只在识别可信时统计位置 —— lost 的帧位置本来就没有意义，
        // 混进去会让漂移数字虚高，反而掩盖真实问题。
        guard quality != .lost else { return }
        for (anchorID, point) in anchorLocalPoints {
            meters[anchorID, default: StabilityMeter(capacity: sampleCapacity)].record(localPoint: point)
            if let radius = toleranceRadii[anchorID] {
                tolerances[anchorID] = radius
            }
        }
    }

    /// 结束当前场景并记入结果。
    public func finish(
        providerID: String,
        averageFPS: Double,
        averageLatencyMS: Double,
        p95LatencyMS: Double,
        stutterCount: Int,
        lockLossCount: Int,
        timeToFirstLockSeconds: Double?,
        note: String? = nil
    ) -> Measurement? {
        guard let scenario = activeScenario, let startedAt else { return nil }
        let duration = Date().timeIntervalSince(startedAt)
        let total = max(1, frameCount)

        let stability = meters
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { anchorID, meter in
                StabilitySnapshot(
                    anchorID: anchorID.rawValue,
                    meter: meter,
                    toleranceRadius: tolerances[anchorID] ?? 0
                )
            }

        let measurement = Measurement(
            scenario: scenario,
            providerID: providerID,
            durationSeconds: duration,
            frameCount: frameCount,
            averageFPS: averageFPS,
            averageLatencyMS: averageLatencyMS,
            p95LatencyMS: p95LatencyMS,
            stutterCount: stutterCount,
            goodRatio: Double(qualityCounts[.good] ?? 0) / Double(total),
            degradedRatio: Double(qualityCounts[.degraded] ?? 0) / Double(total),
            lostRatio: Double(qualityCounts[.lost] ?? 0) / Double(total),
            lockLossCount: lockLossCount,
            timeToFirstLockSeconds: timeToFirstLockSeconds,
            stability: stability,
            note: note
        )
        completed.append(measurement)
        activeScenario = nil
        self.startedAt = nil
        return measurement
    }

    public func discardAll() {
        completed.removeAll()
        cancel()
    }

    public func makeReport(
        deviceModel: String,
        systemVersion: String,
        appVersion: String,
        contentVersion: String
    ) -> Report {
        Report(
            deviceModel: deviceModel,
            systemVersion: systemVersion,
            appVersion: appVersion,
            contentVersion: contentVersion,
            measurements: completed
        )
    }
}
