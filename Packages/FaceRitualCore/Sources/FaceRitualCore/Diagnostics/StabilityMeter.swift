import Foundation

/// 一个 anchor 在**脸部局部坐标系**里的稳定性统计。
///
/// 为什么这样就能测出漂移，而且不需要任何真值标注：
///
/// `FaceFrame` 的定义（原点=双眼中点、x 轴=左眼→右眼、单位=瞳距）决定了
/// 一个 anchor 的局部坐标对**尺度、平移、roll 天然不变** ——
/// 离线 golden vector 已经证明这一点：6 种变换下最大漂移 2e-15 瞳距。
///
/// 所以在真人脸上，同一个 anchor 的局部坐标**理论上应该恒定**。
/// 它实际波动了多少，就是这条链路（provider landmark 抖动 + FaceFrame 不稳 +
/// 滤波残差）在用户脸上造成的漂移。不需要知道"正确位置在哪"，
/// 因为坐标系本身就是以脸为参照的。
///
/// 单位全部是**瞳距**，因此不同的人、不同的距离、不同的机型之间可以直接比。
///
/// 区分两个指标，因为它们的观感完全不同：
/// - **jitter（抖动）**：相邻帧之间的位移。高频噪声，用户看到的是"点在抖"。
/// - **drift（漂移）**：相对整段均值的偏离。低频游走，用户看到的是"点慢慢跑偏"。
///
/// 滤波参数要调哪一个，取决于这两个数谁大：
/// jitter 大 → `minCutoff` 调小；drift 大且跟随滞后 → `beta` 调大。
public struct StabilityMeter: Sendable {

    /// 最多保留的样本数。30fps 下约 60 秒。
    /// 有上限是因为它跑在每一帧上，不能无限增长。
    public let capacity: Int

    private var samples: [Point2D] = []
    /// 相邻帧位移。与 samples 错开一位。
    private var steps: [Double] = []
    private var writeIndex = 0
    private var stepIndex = 0
    private var lastSample: Point2D?

    public init(capacity: Int = 1800) {
        self.capacity = max(2, capacity)
        samples.reserveCapacity(self.capacity)
        steps.reserveCapacity(self.capacity)
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        steps.removeAll(keepingCapacity: true)
        writeIndex = 0
        stepIndex = 0
        lastSample = nil
    }

    /// 记录一帧。`localPoint` 必须是**脸部局部坐标**（单位=瞳距），不是屏幕坐标。
    public mutating func record(localPoint: Point2D) {
        if let lastSample {
            let step = lastSample.distance(to: localPoint)
            if steps.count < capacity {
                steps.append(step)
            } else {
                steps[stepIndex] = step
                stepIndex = (stepIndex + 1) % capacity
            }
        }
        lastSample = localPoint

        if samples.count < capacity {
            samples.append(localPoint)
        } else {
            samples[writeIndex] = localPoint
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    public var sampleCount: Int { samples.count }

    /// 样本中心。漂移以它为基准。
    public var center: Point2D {
        guard samples.isEmpty == false else { return .zero }
        var sumX = 0.0
        var sumY = 0.0
        for point in samples {
            sumX += point.x
            sumY += point.y
        }
        let count = Double(samples.count)
        return Point2D(x: sumX / count, y: sumY / count)
    }

    /// 相对中心的偏离，从小到大排好序。单位=瞳距。
    private var sortedDeviations: [Double] {
        let mid = center
        return samples.map { $0.distance(to: mid) }.sorted()
    }

    /// 漂移的 RMS。整体"跑偏"程度。
    public var driftRMS: Double {
        guard samples.isEmpty == false else { return 0 }
        let mid = center
        let sumSquares = samples.reduce(0.0) { partial, point in
            let d = point.distance(to: mid)
            return partial + d * d
        }
        return (sumSquares / Double(samples.count)).squareRoot()
    }

    /// 漂移的 95 分位。
    ///
    /// 用 p95 而不是最大值：单帧的一次识别失败会把最大值拉到毫无代表性的地方，
    /// 而那一帧在屏幕上根本来不及看见。p95 反映的是"经常能看到的最差情况"。
    public var driftP95: Double { percentile(sortedDeviations, 0.95) }

    public var driftMax: Double { sortedDeviations.last ?? 0 }

    /// 相邻帧位移的中位数。高频抖动。
    public var jitterMedian: Double { percentile(steps.sorted(), 0.5) }

    /// 相邻帧位移的 95 分位。跳变。
    public var jitterP95: Double { percentile(steps.sorted(), 0.95) }

    /// 最近秩插值的分位数。样本少时（POC 里常见）比"取整下标"稳得多。
    private func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard sorted.isEmpty == false else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = (Double(sorted.count) - 1) * clamp(q, 0, 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let t = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * t
    }

    /// 相对某个容差半径的判定。
    ///
    /// 容差圈表达的是「大概这一带」。漂移的 p95 只要明显小于容差半径，
    /// 用户就不会觉得点跑出了它该在的位置。
    /// 这里刻意**不给"合格/不合格"**，只给比值 —— 阈值该定在哪，
    /// 要等真机数据出来再谈（规格 §18 的 Go/No-Go 判定）。
    public func driftRatio(toleranceRadius: Double) -> Double {
        guard toleranceRadius > 1e-9 else { return .infinity }
        return driftP95 / toleranceRadius
    }
}

/// 一次 POC 场景测量的结果。Codable，可以直接导出成 JSON 交回来分析。
public struct StabilitySnapshot: Codable, Hashable, Sendable {
    public var anchorID: String
    public var sampleCount: Int
    /// 以下全部单位=瞳距。
    public var driftRMS: Double
    public var driftP95: Double
    public var driftMax: Double
    public var jitterMedian: Double
    public var jitterP95: Double
    /// 该 anchor 的容差半径，同样以瞳距为单位。用于解读上面几个数的量级。
    public var toleranceRadius: Double

    public init(
        anchorID: String,
        sampleCount: Int,
        driftRMS: Double,
        driftP95: Double,
        driftMax: Double,
        jitterMedian: Double,
        jitterP95: Double,
        toleranceRadius: Double
    ) {
        self.anchorID = anchorID
        self.sampleCount = sampleCount
        self.driftRMS = driftRMS
        self.driftP95 = driftP95
        self.driftMax = driftMax
        self.jitterMedian = jitterMedian
        self.jitterP95 = jitterP95
        self.toleranceRadius = toleranceRadius
    }

    public init(anchorID: String, meter: StabilityMeter, toleranceRadius: Double) {
        self.init(
            anchorID: anchorID,
            sampleCount: meter.sampleCount,
            driftRMS: meter.driftRMS,
            driftP95: meter.driftP95,
            driftMax: meter.driftMax,
            jitterMedian: meter.jitterMedian,
            jitterP95: meter.jitterP95,
            toleranceRadius: toleranceRadius
        )
    }

    /// 漂移相对容差圈的占比。1.0 表示 95% 的帧刚好落在容差圈边缘。
    public var driftRatio: Double {
        toleranceRadius > 1e-9 ? driftP95 / toleranceRadius : .infinity
    }
}
