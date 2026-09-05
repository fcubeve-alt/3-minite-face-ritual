import Foundation

/// One Euro Filter（Casiez et al., 2012）。
///
/// 面部 landmark 逐帧抖动会让脸上的 ● ◎ 抖成筛子，而单纯的低通滤波又会带来
/// 明显滞后。One Euro 在低速时强滤波、高速时弱滤波，正好适配「静止看提示 /
/// 转头快速跟随」这两种状态。
public struct OneEuroFilter: Sendable {
    /// 最小截止频率（Hz）。越小越平滑、静止时越稳。
    public var minCutoff: Double
    /// 速度系数。越大越快跟上快速运动，滞后越小。
    public var beta: Double
    /// 速度信号自身的截止频率。
    public var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTimestamp: TimeInterval?

    public init(minCutoff: Double = 1.0, beta: Double = 0.02, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func reset() {
        lastValue = nil
        lastDerivative = 0
        lastTimestamp = nil
    }

    public mutating func filter(_ value: Double, timestamp: TimeInterval) -> Double {
        guard let previous = lastValue, let previousTime = lastTimestamp else {
            lastValue = value
            lastTimestamp = timestamp
            return value
        }
        let dt = timestamp - previousTime
        // 时间戳倒退或过大间隔（切前后台）时重置，避免滤波器炸掉。
        guard dt > 1e-6, dt < 1.0 else {
            lastValue = value
            lastTimestamp = timestamp
            lastDerivative = 0
            return value
        }
        let rate = 1.0 / dt

        let rawDerivative = (value - previous) * rate
        let derivative = lowPass(
            rawDerivative,
            previous: lastDerivative,
            alpha: OneEuroFilter.alpha(cutoff: derivativeCutoff, rate: rate)
        )
        lastDerivative = derivative

        let cutoff = minCutoff + beta * abs(derivative)
        let filtered = lowPass(
            value,
            previous: previous,
            alpha: OneEuroFilter.alpha(cutoff: cutoff, rate: rate)
        )
        lastValue = filtered
        lastTimestamp = timestamp
        return filtered
    }

    private func lowPass(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }

    static func alpha(cutoff: Double, rate: Double) -> Double {
        let tau = 1.0 / (2 * Double.pi * max(cutoff, 1e-6))
        let dt = 1.0 / rate
        return 1.0 / (1.0 + tau / dt)
    }
}

/// 对整套语义 landmark 做逐点平滑。
public struct FaceGeometrySmoother: Sendable {
    private var filtersX: [SemanticLandmark: OneEuroFilter] = [:]
    private var filtersY: [SemanticLandmark: OneEuroFilter] = [:]
    private let template: OneEuroFilter

    public init(minCutoff: Double = 1.2, beta: Double = 0.03) {
        self.template = OneEuroFilter(minCutoff: minCutoff, beta: beta)
    }

    public mutating func reset() {
        filtersX.removeAll()
        filtersY.removeAll()
    }

    public mutating func smooth(_ geometry: FaceGeometry) -> FaceGeometry {
        guard geometry.trackingState != .notDetected else {
            reset()
            return geometry
        }
        var result = geometry
        for (mark, sample) in geometry.landmarks {
            var fx = filtersX[mark] ?? template
            var fy = filtersY[mark] ?? template
            let x = fx.filter(sample.point.x, timestamp: geometry.timestamp)
            let y = fy.filter(sample.point.y, timestamp: geometry.timestamp)
            filtersX[mark] = fx
            filtersY[mark] = fy
            result.landmarks[mark] = LandmarkSample(
                point: Point2D(x: x, y: y),
                confidence: sample.confidence,
                isOccluded: sample.isOccluded
            )
        }
        return result
    }
}
