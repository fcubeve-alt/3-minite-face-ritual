import UIKit
import FaceRitualCore

/// 合成人脸 provider。
///
/// 用途：
/// 1. 模拟器上开发 UI 与 Overlay（模拟器没有摄像头）；
/// 2. 真机上做 A/B 对照 —— 如果 Mock 下 overlay 正常而真实 provider 异常，
///    问题就在 provider 或坐标变换，而不在渲染或播放逻辑；
/// 3. 演示与截图。
///
/// 它输出的脸会缓慢左右摆动、呼吸式缩放，用来观察 overlay 的跟随与平滑效果。
///
/// 继承 NSObject 是必需的：`CADisplayLink(target:selector:)` 走 ObjC runtime，
/// 而 `@objc` 方法只能定义在继承自 NSObject 的类里。
final class MockFaceAlignmentProvider: NSObject, FaceAlignmentProvider {

    let descriptor = FaceProviderDescriptor(
        id: "mock",
        displayName: "Mock (合成脸)",
        summary: "程序生成的动画人脸，不使用摄像头。用于模拟器开发与对照排查。",
        requiresTrueDepth: false,
        supportedLandmarks: Set(SemanticLandmark.allCases),
        providesHeadPose: true,
        providesOcclusionEstimate: false
    )

    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }

    var onGeometry: ((FaceGeometry) -> Void)?
    var onFailure: ((Error) -> Void)?

    private var displayLink: CADisplayLink?
    private var configuration = FaceAlignmentConfiguration(viewSize: .zero)
    private var startTime: CFTimeInterval = 0

    /// 合成脸的标准比例，单位 = 瞳距，原点 = 双眼中点，+x 朝用户右侧，+y 朝下。
    /// 与 `tools/golden/generate_golden.py` 里的 CANONICAL_FACE 保持一致。
    /// 这是一张用于自测的合成脸，比例只求大致合理，不代表真实人群的解剖学数据。
    private static let canonicalFace: [SemanticLandmark: Point2D] = [
        .leftEyeCenter: Point2D(x: -0.50, y: 0.00),
        .rightEyeCenter: Point2D(x: 0.50, y: 0.00),
        .leftEyeOuter: Point2D(x: -0.78, y: 0.00),
        .rightEyeOuter: Point2D(x: 0.78, y: 0.00),
        .leftEyeInner: Point2D(x: -0.25, y: 0.02),
        .rightEyeInner: Point2D(x: 0.25, y: 0.02),
        .leftEyeUpper: Point2D(x: -0.50, y: -0.12),
        .rightEyeUpper: Point2D(x: 0.50, y: -0.12),
        .leftEyeLower: Point2D(x: -0.50, y: 0.10),
        .rightEyeLower: Point2D(x: 0.50, y: 0.10),
        .leftBrowInner: Point2D(x: -0.22, y: -0.32),
        .rightBrowInner: Point2D(x: 0.22, y: -0.32),
        .leftBrowOuter: Point2D(x: -0.80, y: -0.32),
        .rightBrowOuter: Point2D(x: 0.80, y: -0.32),
        .leftBrowPeak: Point2D(x: -0.52, y: -0.40),
        .rightBrowPeak: Point2D(x: 0.52, y: -0.40),
        .glabella: Point2D(x: 0.00, y: -0.28),
        .noseBridgeTop: Point2D(x: 0.00, y: -0.10),
        .noseBridgeMid: Point2D(x: 0.00, y: 0.25),
        .noseTip: Point2D(x: 0.00, y: 0.62),
        .subnasale: Point2D(x: 0.00, y: 0.78),
        .leftNoseAla: Point2D(x: -0.22, y: 0.70),
        .rightNoseAla: Point2D(x: 0.22, y: 0.70),
        .mouthLeftCorner: Point2D(x: -0.42, y: 1.05),
        .mouthRightCorner: Point2D(x: 0.42, y: 1.05),
        .upperLipCenter: Point2D(x: 0.00, y: 0.95),
        .lowerLipCenter: Point2D(x: 0.00, y: 1.15),
        .chinCenter: Point2D(x: 0.00, y: 1.72),
        .leftJawAngle: Point2D(x: -0.92, y: 1.25),
        .rightJawAngle: Point2D(x: 0.92, y: 1.25),
        .leftCheekbone: Point2D(x: -0.78, y: 0.42),
        .rightCheekbone: Point2D(x: 0.78, y: 0.42),
        .leftTemple: Point2D(x: -1.05, y: -0.18),
        .rightTemple: Point2D(x: 1.05, y: -0.18),
        .foreheadCenter: Point2D(x: 0.00, y: -0.72)
    ]

    func start(configuration: FaceAlignmentConfiguration) throws {
        self.configuration = configuration
        startTime = CACurrentMediaTime()

        let link = CADisplayLink(target: self, selector: #selector(emitFrame))
        link.preferredFramesPerSecond = configuration.targetFrameRate
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func updateViewSize(_ size: CGSize) {
        configuration.viewSize = size
    }

    func makePreviewView() -> UIView {
        MockPreviewView()
    }

    @objc private func emitFrame() {
        let viewSize = configuration.viewSize
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let elapsed = CACurrentMediaTime() - startTime
        // 缓慢摆动 + 呼吸式缩放 —— 用来观察 overlay 的跟随与平滑。
        let roll = sin(elapsed * 0.5) * 8
        let yaw = sin(elapsed * 0.31) * 12
        let pitch = sin(elapsed * 0.23) * 6
        let breathing = 1.0 + sin(elapsed * 0.7) * 0.02

        let interocular = Double(min(viewSize.width, viewSize.height)) * 0.26 * breathing
        let center = Point2D(
            x: Double(viewSize.width) / 2 + sin(elapsed * 0.4) * Double(viewSize.width) * 0.03,
            y: Double(viewSize.height) * 0.40 + sin(elapsed * 0.6) * Double(viewSize.height) * 0.01
        )

        let angle = roll * Double.pi / 180
        let cosA = cos(angle)
        let sinA = sin(angle)

        var table: [SemanticLandmark: LandmarkSample] = [:]
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for (mark, local) in MockFaceAlignmentProvider.canonicalFace {
            let sx = local.x * interocular
            let sy = local.y * interocular
            let point = Point2D(
                x: center.x + sx * cosA - sy * sinA,
                y: center.y + sx * sinA + sy * cosA
            )
            table[mark] = LandmarkSample(point: point, confidence: 0.95, isOccluded: false)
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        let geometry = FaceGeometry(
            providerID: descriptor.id,
            timestamp: CACurrentMediaTime(),
            trackingState: .locked,
            pose: HeadPose(yawDegrees: yaw, pitchDegrees: pitch, rollDegrees: roll),
            landmarks: table,
            boundingBox: Rect2D(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            viewSize: Size2D(viewSize),
            isMirrored: configuration.isMirrored,
            overallConfidence: 0.95
        )
        onGeometry?(geometry)
    }
}

/// Mock 模式的背景。刻意做成明显的占位样式 ——
/// 绝不能让人误以为这是真实摄像头画面。
private final class MockPreviewView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.12, alpha: 1)

        let label = UILabel()
        label.text = "MOCK FACE — 未使用摄像头"
        label.textColor = UIColor(white: 1, alpha: 0.45)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
