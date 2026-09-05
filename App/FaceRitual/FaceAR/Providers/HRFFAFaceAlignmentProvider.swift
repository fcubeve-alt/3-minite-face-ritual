import AVFoundation
import CoreImage
import CoreML
import UIKit
import Vision
import FaceRitualCore

/// HRFFA（或任何同级稠密 face alignment 模型）的 CoreML 接入。
///
/// **当前状态：接线完成，等待模型文件。**
/// 把转换好的 `HRFFA.mlpackage` 放进 App target 即自动启用，
/// 无需改动本文件以外的任何代码 —— 这正是 Provider Abstraction 的意义。
/// 转换步骤见 `docs/HRFFA_INTEGRATION.md`。
///
/// 设计要点：
/// - 人脸框由 Vision 的 `VNDetectFaceRectanglesRequest` 提供（比自己写检测器稳，也省一份模型）；
/// - 模型只负责在裁剪出来的人脸上回归稠密点；
/// - 输出点数自动识别布局（68 → iBUG，98 → WFLW），映射表见 `DenseLandmarkLayout`；
/// - 模型缺失时 `isAvailable == false`，App 会回落到 Vision 并上报 `guidanceFallback`，
///   **不会因为没有模型就打不开 AR Mirror**（规格 §18：POC 失败也不能拖死 MVP）。
final class HRFFAFaceAlignmentProvider: NSObject, FaceAlignmentProvider {

    /// 模型资源名。替换模型时只改这里。
    static let modelResourceName = "HRFFA"

    private(set) var layout: DenseLandmarkLayout?
    private var model: MLModel?
    private var loadFailureReason: String?

    override init() {
        super.init()
        loadModel()
    }

    var descriptor: FaceProviderDescriptor {
        FaceProviderDescriptor(
            id: "hrffa",
            displayName: "HRFFA (CoreML)",
            summary: layout.map { "稠密 face alignment 模型，\($0.pointCount) 点（\($0.rawValue) 布局）。" }
                ?? "稠密 face alignment 模型（未加载）。",
            requiresTrueDepth: false,
            supportedLandmarks: layout?.supportedLandmarks ?? [],
            providesHeadPose: true,
            providesOcclusionEstimate: false
        )
    }

    var isAvailable: Bool { model != nil && layout != nil && VisionFaceAlignmentProvider.hasFrontCamera }

    var unavailableReason: String? {
        guard isAvailable == false else { return nil }
        if VisionFaceAlignmentProvider.hasFrontCamera == false {
            return "本机没有可用的前置摄像头（模拟器通常如此）。"
        }
        return loadFailureReason ?? "未找到 \(HRFFAFaceAlignmentProvider.modelResourceName).mlmodelc，请参考 docs/HRFFA_INTEGRATION.md 转换并加入 App target。"
    }

    var onGeometry: ((FaceGeometry) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let camera = CameraController()
    private let sequenceHandler = VNSequenceRequestHandler()
    private var configuration = FaceAlignmentConfiguration(viewSize: .zero)
    private var isProcessing = false
    private(set) var lastLatencyMS: Double = 0

    // MARK: - 模型加载

    private func loadModel() {
        guard let url = Bundle.main.url(forResource: HRFFAFaceAlignmentProvider.modelResourceName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: HRFFAFaceAlignmentProvider.modelResourceName, withExtension: "mlpackage")
        else {
            return
        }
        do {
            let configuration = MLModelConfiguration()
            // 优先 Neural Engine；不可用时 CoreML 自动回落 GPU/CPU。
            configuration.computeUnits = .all
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            model = loaded
            layout = HRFFAFaceAlignmentProvider.inferLayout(from: loaded)
            if layout == nil {
                loadFailureReason = "模型已加载，但输出点数无法识别为 68 或 98 点布局。请在 DenseLandmarkLayout 中补充映射表。"
                model = nil
            }
        } catch {
            loadFailureReason = "模型加载失败: \(error.localizedDescription)"
        }
    }

    /// 从模型输出的 shape 推断布局。支持 [1, N, 2] / [1, 2N] / [N, 2] 几种常见形状。
    private static func inferLayout(from model: MLModel) -> DenseLandmarkLayout? {
        for feature in model.modelDescription.outputDescriptionsByName.values {
            guard let constraint = feature.multiArrayConstraint else { continue }
            let shape = constraint.shape.map(\.intValue).filter { $0 > 1 }
            if let pointCount = shape.first(where: { $0 == 68 || $0 == 98 }) {
                return DenseLandmarkLayout.layout(forPointCount: pointCount)
            }
            // [1, 136] / [1, 196] 这类展平输出
            if let flat = shape.first, flat % 2 == 0 {
                return DenseLandmarkLayout.layout(forPointCount: flat / 2)
            }
        }
        return nil
    }

    // MARK: - FaceAlignmentProvider

    func start(configuration: FaceAlignmentConfiguration) throws {
        guard isAvailable else {
            throw FaceAlignmentProviderError.modelMissing(unavailableReason ?? "HRFFA")
        }
        self.configuration = configuration
        camera.onFrame = { [weak self] pixelBuffer, timestamp, _ in
            self?.process(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
        try camera.configureAndStart(targetFrameRate: configuration.targetFrameRate)
    }

    func stop() {
        camera.stop()
        camera.onFrame = nil
    }

    func updateViewSize(_ size: CGSize) {
        configuration.viewSize = size
    }

    func makePreviewView() -> UIView {
        camera.makePreviewView(isMirrored: configuration.isMirrored)
    }

    // MARK: - 每帧处理

    private func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isProcessing == false, let model, let layout else { return }
        isProcessing = true

        let viewSize = configuration.viewSize
        let isMirrored = configuration.isMirrored
        let captureSeconds = CMTimeGetSeconds(timestamp)
        let startedAt = CACurrentMediaTime()

        defer { lastLatencyMS = (CACurrentMediaTime() - startedAt) * 1000 }

        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let transform = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: isMirrored)

        // 1) 先用 Vision 找人脸框。
        let detect = VNDetectFaceRectanglesRequest()
        do {
            try sequenceHandler.perform([detect], on: pixelBuffer, orientation: .up)
        } catch {
            finish(with: nil, timestamp: captureSeconds, viewSize: viewSize, error: error)
            return
        }
        guard let face = (detect.results ?? []).max(by: { $0.boundingBox.height < $1.boundingBox.height }) else {
            finish(with: nil, timestamp: captureSeconds, viewSize: viewSize, error: nil)
            return
        }

        // 2) 按人脸框裁剪并跑模型。
        let cropRect = HRFFAFaceAlignmentProvider.expandedCropRect(
            normalized: face.boundingBox,
            imageSize: imageSize
        )
        guard let cropped = HRFFAFaceAlignmentProvider.crop(pixelBuffer: pixelBuffer, to: cropRect) else {
            finish(with: nil, timestamp: captureSeconds, viewSize: viewSize, error: nil)
            return
        }

        do {
            let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: cropped)])
            let output = try model.prediction(from: provider)

            guard let raw = HRFFAFaceAlignmentProvider.extractPoints(from: output, expectedCount: layout.pointCount) else {
                finish(with: nil, timestamp: captureSeconds, viewSize: viewSize, error: nil)
                return
            }

            // 3) 模型输出是裁剪框内的归一化坐标 → 还原到全图 → 再到视图坐标。
            let viewPoints = raw.map { point -> Point2D in
                let imagePoint = CGPoint(
                    x: cropRect.origin.x + point.x * cropRect.width,
                    // 模型输出按左上原点；Vision 的图像坐标是左下原点，这里先翻回去。
                    y: cropRect.origin.y + (1 - point.y) * cropRect.height
                )
                return transform.viewPoint(fromImagePoint: imagePoint)
            }

            let table = layout.resolve(points: viewPoints, confidence: Double(face.confidence))
            guard table.isEmpty == false else {
                finish(with: nil, timestamp: captureSeconds, viewSize: viewSize, error: nil)
                return
            }

            let geometry = FaceGeometry(
                providerID: descriptor.id,
                timestamp: captureSeconds,
                trackingState: .locked,
                // 稠密模型本身不输出姿态；由 landmark 几何估算（见 HeadPoseEstimator）。
                pose: HeadPoseEstimator.estimate(from: table),
                landmarks: table,
                boundingBox: transform.viewRect(fromNormalizedRect: face.boundingBox),
                viewSize: Size2D(viewSize),
                isMirrored: isMirrored,
                overallConfidence: Double(face.confidence)
            )
            finish(with: geometry, timestamp: captureSeconds, viewSize: viewSize, error: nil)
        } catch {
            finish(with: nil, timestamp: captureSeconds, viewSize: viewSize, error: error)
        }
    }

    private func finish(with geometry: FaceGeometry?, timestamp: TimeInterval, viewSize: CGSize, error: Error?) {
        let result = geometry ?? FaceGeometry.notDetected(
            providerID: descriptor.id,
            timestamp: timestamp,
            viewSize: Size2D(viewSize)
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isProcessing = false
            if let error { self.onFailure?(error) }
            self.onGeometry?(result)
        }
    }

    // MARK: - 裁剪与解码

    /// 人脸框外扩一圈 —— 稠密模型通常在带余量的人脸裁剪上训练，
    /// 贴边裁剪会让轮廓点被截断。
    static func expandedCropRect(normalized: CGRect, imageSize: CGSize, margin: CGFloat = 0.25) -> CGRect {
        let pixel = CGRect(
            x: normalized.origin.x * imageSize.width,
            y: normalized.origin.y * imageSize.height,
            width: normalized.width * imageSize.width,
            height: normalized.height * imageSize.height
        )
        // 取正方形，避免模型输入被非等比拉伸。
        let side = max(pixel.width, pixel.height) * (1 + margin * 2)
        let centerX = pixel.midX
        let centerY = pixel.midY
        return CGRect(
            x: max(0, centerX - side / 2),
            y: max(0, centerY - side / 2),
            width: min(side, imageSize.width),
            height: min(side, imageSize.height)
        )
    }

    private static func crop(pixelBuffer: CVPixelBuffer, to rect: CGRect) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: rect)
        let context = CIContext()
        var output: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(rect.width),
            Int(rect.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else { return nil }
        context.render(ciImage, to: output)
        return output
    }

    /// 从模型输出里取出 N 个归一化坐标。兼容 [N,2] / [2N] / [1,N,2] 等形状。
    static func extractPoints(from output: MLFeatureProvider, expectedCount: Int) -> [CGPoint]? {
        for name in output.featureNames {
            guard let array = output.featureValue(for: name)?.multiArrayValue else { continue }
            let count = array.count
            guard count == expectedCount * 2 else { continue }

            var points: [CGPoint] = []
            points.reserveCapacity(expectedCount)
            for index in 0..<expectedCount {
                let x = array[index * 2].doubleValue
                let y = array[index * 2 + 1].doubleValue
                points.append(CGPoint(x: x, y: y))
            }
            return points
        }
        return nil
    }
}

/// 从语义 landmark 估算头部姿态。
///
/// 稠密 2D 模型不直接给姿态，但导航需要它来判断「转头是否过大」。
/// 这里用简单的几何近似（不解 PnP）：
/// - roll  ：双眼连线的倾角，精确；
/// - yaw   ：鼻尖相对双眼中点的水平偏移 / 瞳距，近似；
/// - pitch ：鼻尖到眼线的垂直距离与标准比例的偏差，近似。
/// 用于阈值判断足够；不用于任何需要精确角度的场景。
enum HeadPoseEstimator {

    /// 正脸时鼻尖到双眼中点的垂直距离约为 0.62 个瞳距（与合成脸模型一致）。
    static let neutralNoseDropRatio = 0.62

    static func estimate(from landmarks: [SemanticLandmark: LandmarkSample]) -> HeadPose {
        guard
            let leftEye = landmarks[.leftEyeCenter]?.point,
            let rightEye = landmarks[.rightEyeCenter]?.point,
            let noseTip = landmarks[.noseTip]?.point
        else { return .neutral }

        let axis = rightEye - leftEye
        let interocular = axis.length
        guard interocular > 1e-6 else { return .neutral }

        let roll = axis.angle * 180 / Double.pi

        let origin = leftEye.lerp(to: rightEye, t: 0.5)
        let unitX = axis.normalized
        let unitY = unitX.rotatedClockwise90
        let delta = noseTip - origin
        let localX = (delta.dx * unitX.dx + delta.dy * unitX.dy) / interocular
        let localY = (delta.dx * unitY.dx + delta.dy * unitY.dy) / interocular

        // 经验系数：鼻尖每偏移 0.5 瞳距约对应 45° 偏航。
        let yaw = clamp(localX / 0.5, -1, 1) * 45
        let pitch = clamp((neutralNoseDropRatio - localY) / 0.35, -1, 1) * 45

        return HeadPose(yawDegrees: yaw, pitchDegrees: pitch, rollDegrees: roll)
    }
}
