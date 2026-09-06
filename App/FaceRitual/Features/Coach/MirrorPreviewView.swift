import AVFoundation
import SwiftUI
import UIKit

/// 纯镜像预览：把前置摄像头画面照原样显示，**不做任何人脸识别**。
///
/// 这是 2026-09-07 产品方向调整之后的做法。之前的 AR Mirror 要把路线贴在脸上，
/// 需要 landmark、坐标系、滤波、漂移控制一整条链路；实测下来贴不稳，
/// 而"贴不准的指引没有意义"。
///
/// 现在下半屏只要回答一个问题：**我做的动作和老师像不像。**
/// 那只需要一面镜子。没有跟踪就没有漂移，没有 provider 就没有回落，
/// 没有识别失败就不需要降级策略 —— 这一整类问题从需求上消失了。
///
/// 摄像头仍然是**可选**的：没授权、模拟器上没有摄像头、用户主动关掉，
/// 都只是少了下半屏，不影响跟着视频做完整套 routine。
final class MirrorPreviewController: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        /// 正常出画。
        case running
        /// 这台设备没有可用的前置摄像头（模拟器就是这种）。
        case unavailable
        /// 用户拒绝了权限。
        case denied
    }

    @Published private(set) var state: State = .idle

    private let session = AVCaptureSession()
    /// 相机配置与启停都放到专用队列 —— 在主线程上做会卡住界面。
    private let queue = DispatchQueue(label: "face3.mirror.session")
    private var isConfigured = false

    /// 供 UIView 侧接管的预览层。
    let previewLayer: AVCaptureVideoPreviewLayer

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndRun() } else { self?.state = .denied }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .unavailable
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        if state == .running { state = .idle }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }

            if self.isConfigured == false {
                guard let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .front
                ), let input = try? AVCaptureDeviceInput(device: device) else {
                    DispatchQueue.main.async { self.state = .unavailable }
                    return
                }
                self.session.beginConfiguration()
                // 只做预览，不取样本缓冲 —— 分辨率要够看，但没必要拉满。
                self.session.sessionPreset = .high
                if self.session.canAddInput(input) { self.session.addInput(input) }
                self.session.commitConfiguration()
                self.isConfigured = true

                DispatchQueue.main.async {
                    // 镜像：用户看到的应该是"镜子里的自己"，不是别人眼里的自己。
                    // 不镜像的话，老师抬左手你会跟着抬右手。
                    if let connection = self.previewLayer.connection,
                       connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                }
            }

            if self.session.isRunning == false { self.session.startRunning() }
            DispatchQueue.main.async { self.state = .running }
        }
    }
}

/// 把预览层接进 SwiftUI。
struct MirrorPreviewRepresentable: UIViewRepresentable {
    let controller: MirrorPreviewController

    func makeUIView(context: Context) -> MirrorPreviewUIView {
        let view = MirrorPreviewUIView()
        view.backgroundColor = .black
        view.attach(controller.previewLayer)
        return view
    }

    func updateUIView(_ uiView: MirrorPreviewUIView, context: Context) {}
}

/// 预览层必须在 `layoutSubviews` 里跟着改 frame ——
/// CALayer 不参与 Auto Layout，父视图变了它不会自己跟。
final class MirrorPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = layer
        self.layer.addSublayer(layer)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 关掉隐式动画：不关的话每次布局变化预览层都会做一次淡入，看起来像闪。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}
