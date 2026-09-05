import Foundation
import QuartzCore

/// AR 会话的性能采样。直接服务于 `AR_POC_REPORT.md` 里要求的
/// FPS / latency / 丢锁次数 三项实测数据。
///
/// 刻意做成可读可导出的：POC 阶段 Owner 需要把数字抄进报告，
/// 而不是只在 Xcode Instruments 里看一眼。
final class PerformanceMonitor {

    private var frameTimestamps: [TimeInterval] = []
    private var latencies: [Double] = []
    private let windowSeconds: TimeInterval = 3.0
    private let maxSamples = 600

    private(set) var startedAt: TimeInterval?
    private(set) var totalFrames: Int = 0
    /// 掉帧统计：帧间隔超过目标间隔 2 倍的次数。
    private(set) var stutterCount: Int = 0

    private var targetFrameInterval: TimeInterval = 1.0 / 30.0

    func start(targetFrameRate: Int) {
        reset()
        targetFrameInterval = 1.0 / Double(max(1, targetFrameRate))
        startedAt = CACurrentMediaTime()
    }

    func reset() {
        frameTimestamps.removeAll()
        latencies.removeAll()
        totalFrames = 0
        stutterCount = 0
        startedAt = nil
    }

    /// 每收到一帧 geometry 调一次。`latencyMS` 为该帧的推理耗时（provider 提供，可选）。
    func recordFrame(latencyMS: Double?) {
        let now = CACurrentMediaTime()
        if let last = frameTimestamps.last, now - last > targetFrameInterval * 2 {
            stutterCount += 1
        }
        frameTimestamps.append(now)
        totalFrames += 1

        // 只保留滑动窗口内的样本。
        while let first = frameTimestamps.first, now - first > windowSeconds {
            frameTimestamps.removeFirst()
        }
        if let latencyMS {
            latencies.append(latencyMS)
            if latencies.count > maxSamples { latencies.removeFirst(latencies.count - maxSamples) }
        }
    }

    /// 滑动窗口内的实时帧率。
    var currentFPS: Double {
        guard frameTimestamps.count >= 2,
              let first = frameTimestamps.first,
              let last = frameTimestamps.last,
              last > first
        else { return 0 }
        return Double(frameTimestamps.count - 1) / (last - first)
    }

    /// 整个会话的平均帧率。
    var averageFPS: Double {
        guard let startedAt, totalFrames > 1 else { return 0 }
        let elapsed = CACurrentMediaTime() - startedAt
        guard elapsed > 0 else { return 0 }
        return Double(totalFrames) / elapsed
    }

    var averageLatencyMS: Double {
        guard latencies.isEmpty == false else { return 0 }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    /// 95 分位延迟 —— 平均值会掩盖偶发卡顿，而卡顿正是 overlay 跳变的来源。
    var p95LatencyMS: Double {
        guard latencies.isEmpty == false else { return 0 }
        let sorted = latencies.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        return sorted[index]
    }

    var elapsedSeconds: Double {
        guard let startedAt else { return 0 }
        return CACurrentMediaTime() - startedAt
    }

    /// 供 POC 报告直接抄录的一行摘要。
    func summaryLine(providerID: String, lockLossCount: Int, timeToFirstLock: Double?) -> String {
        let lockText = timeToFirstLock.map { String(format: "%.2fs", $0) } ?? "未锁定"
        return String(
            format: "provider=%@ frames=%d avgFPS=%.1f avgLatency=%.1fms p95Latency=%.1fms stutters=%d lockLoss=%d timeToFirstLock=%@",
            providerID, totalFrames, averageFPS, averageLatencyMS, p95LatencyMS, stutterCount, lockLossCount, lockText
        )
    }
}
