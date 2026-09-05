import AVFoundation
import UIKit

/// 前置摄像头采集。Vision 与 HRFFA provider 共用；ARKit provider 自带 ARSession，不用它。
///
/// 摄像头只在用户主动开启 AR Mirror 时才启动（规格 §4「摄像头可选」）。
final class CameraController: NSObject {

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.faceritual.camera.session")
    private let sampleQueue = DispatchQueue(label: "com.faceritual.camera.samples")

    /// 每帧回调（在 sampleQueue 上）。
    var onFrame: ((CVPixelBuffer, CMTime, AVCaptureConnection) -> Void)?
    var onFailure: ((Error) -> Void)?

    private(set) var isRunning = false

    // MARK: - 生命周期

    func configureAndStart(targetFrameRate: Int) throws {
        try configureIfNeeded(targetFrameRate: targetFrameRate)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning == false else { return }
            self.session.startRunning()
        }
        isRunning = true
    }

    func stop() {
        isRunning = false
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private var isConfigured = false

    private func configureIfNeeded(targetFrameRate: Int) throws {
        guard isConfigured == false else { return }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw FaceAlignmentProviderError.cameraUnavailable
        }

        session.beginConfiguration()
        // 720p 足够做 face alignment，而且比 1080p 省电、延迟更低。
        session.sessionPreset = .hd1280x720

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw FaceAlignmentProviderError.configurationFailed("无法添加摄像头输入")
            }
            session.addInput(input)
        } catch let error as FaceAlignmentProviderError {
            throw error
        } catch {
            session.commitConfiguration()
            throw FaceAlignmentProviderError.configurationFailed(error.localizedDescription)
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // 丢帧而不是排队：AR 导航要的是最新一帧，不是完整一帧都不漏。
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw FaceAlignmentProviderError.configurationFailed("无法添加视频输出")
        }
        session.addOutput(videoOutput)

        // 让像素缓冲直接以竖屏方向到达，Vision 就可以用 .up，省掉一层方向换算。
        // 采集连接**不**做镜像：镜像只发生在预览层与坐标变换里，
        // 这样检测器始终看到相机原始视角，解剖学左右的判定才有唯一基准。
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        session.commitConfiguration()

        configureFrameRate(device: device, target: targetFrameRate)
        isConfigured = true
    }

    private func configureFrameRate(device: AVCaptureDevice, target: Int) {
        guard target > 0 else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let duration = CMTime(value: 1, timescale: CMTimeScale(target))
            let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
                CMTimeCompare(duration, $0.minFrameDuration) >= 0 && CMTimeCompare(duration, $0.maxFrameDuration) <= 0
            }
            guard supported else { return }
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        } catch {
            // 帧率固定失败不致命 —— 用系统默认继续跑。
        }
    }

    // MARK: - 预览

    func makePreviewView(isMirrored: Bool) -> CameraPreviewView {
        CameraPreviewView(session: session, isMirrored: isMirrored)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(pixelBuffer, timestamp, connection)
    }
}

/// 承载 `AVCaptureVideoPreviewLayer` 的 UIView。
final class CameraPreviewView: UIView {

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    init(session: AVCaptureSession, isMirrored: Bool) {
        super.init(frame: .zero)
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black

        if let connection = previewLayer.connection {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = isMirrored
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
