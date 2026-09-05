import AVFoundation
import UIKit
import Vision
import FaceRitualCore

/// 基于 Apple Vision 的 face alignment。**M1 的默认 provider 与横评基线。**
///
/// 为什么它是基线而不是 HRFFA：
/// Vision 输出的是**具名区域**（leftEye / nose / medianLine / faceContour…），
/// 不需要任何魔数索引表，不需要模型文件，全机型可用。
/// 因此它是 POC 里唯一一开始就必定跑得起来的对照组 ——
/// HRFFA 与 ARKit 的表现都拿它做对比（见 AR_POC_REPORT.md）。
///
/// 已知能力边界：Vision **不提供**逐点遮挡判断。
/// 手遮住脸时我们只能观察到置信度下降，不能声称知道哪一点被挡住。
/// 这与规格 §10 的承诺一致 —— 我们只做导航，不做接触点判定。
final class VisionFaceAlignmentProvider: NSObject, FaceAlignmentProvider {

    let descriptor = FaceProviderDescriptor(
        id: "vision",
        displayName: "Vision (基线)",
        summary: "Apple Vision 的具名 landmark 区域。无模型文件、无魔数索引、全机型可用。",
        requiresTrueDepth: false,
        supportedLandmarks: VisionFaceAlignmentProvider.supportedLandmarks,
        providesHeadPose: true,
        providesOcclusionEstimate: false
    )

    static let supportedLandmarks: Set<SemanticLandmark> = [
        .leftEyeCenter, .rightEyeCenter,
        .leftEyeOuter, .rightEyeOuter, .leftEyeInner, .rightEyeInner,
        .leftEyeUpper, .rightEyeUpper, .leftEyeLower, .rightEyeLower,
        .leftBrowInner, .rightBrowInner, .leftBrowOuter, .rightBrowOuter, .leftBrowPeak, .rightBrowPeak,
        .glabella,
        .noseBridgeTop, .noseBridgeMid, .noseTip, .subnasale, .leftNoseAla, .rightNoseAla,
        .leftMouthCorner, .rightMouthCorner, .upperLipCenter, .lowerLipCenter,
        .chinCenter, .leftJawAngle, .rightJawAngle
    ]

    /// 模拟器没有摄像头 —— 这里如实报告，工厂就会自动回落到 Mock provider。
    /// 之前无条件返回 true，模拟器上会一路走到 start() 才抛错，白屏且没有退路。
    static var hasFrontCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    var isAvailable: Bool { VisionFaceAlignmentProvider.hasFrontCamera }

    var unavailableReason: String? {
        isAvailable ? nil : "本机没有可用的前置摄像头（模拟器通常如此）。"
    }

    var onGeometry: ((FaceGeometry) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let camera = CameraController()
    private let sequenceHandler = VNSequenceRequestHandler()
    private var configuration = FaceAlignmentConfiguration(viewSize: .zero)
    private var previewView: CameraPreviewView?
    private var isProcessing = false

    // MARK: - FaceAlignmentProvider

    func start(configuration: FaceAlignmentConfiguration) throws {
        self.configuration = configuration
        camera.onFrame = { [weak self] pixelBuffer, timestamp, connection in
            self?.process(pixelBuffer: pixelBuffer, timestamp: timestamp, connection: connection)
        }
        camera.onFailure = { [weak self] error in
            DispatchQueue.main.async { self?.onFailure?(error) }
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
        let view = camera.makePreviewView(isMirrored: configuration.isMirrored)
        previewView = view
        return view
    }

    // MARK: - 每帧处理

    private func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime, connection: AVCaptureConnection) {
        // 上一帧还没算完就丢掉当前帧 —— 导航要最新位置，不要排队积压。
        guard isProcessing == false else { return }
        isProcessing = true

        let viewSize = configuration.viewSize
        let isMirrored = configuration.isMirrored
        let captureSeconds = CMTimeGetSeconds(timestamp)
        let startedAt = CACurrentMediaTime()

        // 采集连接已设为竖屏方向，因此 Vision 用 .up。
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            isProcessing = false
            DispatchQueue.main.async { [weak self] in self?.onFailure?(error) }
            return
        }

        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let transform = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: isMirrored)

        let geometry: FaceGeometry
        if let observation = (request.results ?? []).max(by: { $0.boundingBox.height < $1.boundingBox.height }) {
            geometry = makeGeometry(
                observation: observation,
                transform: transform,
                imageSize: imageSize,
                viewSize: viewSize,
                isMirrored: isMirrored,
                timestamp: captureSeconds
            )
        } else {
            geometry = FaceGeometry.notDetected(
                providerID: descriptor.id,
                timestamp: captureSeconds,
                viewSize: Size2D(viewSize)
            )
        }

        let latencyMS = (CACurrentMediaTime() - startedAt) * 1000
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isProcessing = false
            self.lastLatencyMS = latencyMS
            self.onGeometry?(geometry)
        }
    }

    /// 最近一帧的推理耗时，POC 报告用。
    private(set) var lastLatencyMS: Double = 0

    // MARK: - 语义映射

    private func makeGeometry(
        observation: VNFaceObservation,
        transform: ImageToViewTransform,
        imageSize: CGSize,
        viewSize: CGSize,
        isMirrored: Bool,
        timestamp: TimeInterval
    ) -> FaceGeometry {
        guard let landmarks = observation.landmarks else {
            return FaceGeometry.notDetected(providerID: descriptor.id, timestamp: timestamp, viewSize: Size2D(viewSize))
        }

        func points(_ region: VNFaceLandmarkRegion2D?) -> [Point2D] {
            guard let region else { return [] }
            return region.pointsInImage(imageSize: imageSize).map(transform.viewPoint(fromImagePoint:))
        }

        // Vision 的 leftEye / rightEye 命名在「图像左右」与「解剖学左右」之间历来含糊。
        // 所以这里**不信任命名**，而是按几何位置判定解剖学侧：
        // 镜像预览下（像照镜子），用户自己的左半边脸出现在画面左侧（view-x 更小）。
        let eyeRegions = [points(landmarks.leftEye), points(landmarks.rightEye)].filter { $0.isEmpty == false }
        let browRegions = [points(landmarks.leftEyebrow), points(landmarks.rightEyebrow)].filter { $0.isEmpty == false }

        guard eyeRegions.count == 2 else {
            return FaceGeometry.notDetected(providerID: descriptor.id, timestamp: timestamp, viewSize: Size2D(viewSize))
        }

        let (leftEye, rightEye) = splitByAnatomicalSide(eyeRegions[0], eyeRegions[1], isMirrored: isMirrored)
        var table: [SemanticLandmark: LandmarkSample] = [:]
        let confidence = Double(landmarks.confidence)

        func put(_ mark: SemanticLandmark, _ point: Point2D?) {
            guard let point else { return }
            // isOccluded 恒为 false：Vision 不提供遮挡判断，我们不编造它。
            table[mark] = LandmarkSample(point: point, confidence: confidence, isOccluded: false)
        }

        // --- 眼 ---
        put(.leftEyeCenter, centroid(leftEye))
        put(.rightEyeCenter, centroid(rightEye))
        put(.leftEyeOuter, extreme(leftEye, isMirrored ? .minX : .maxX))
        put(.leftEyeInner, extreme(leftEye, isMirrored ? .maxX : .minX))
        put(.rightEyeOuter, extreme(rightEye, isMirrored ? .maxX : .minX))
        put(.rightEyeInner, extreme(rightEye, isMirrored ? .minX : .maxX))
        put(.leftEyeUpper, extreme(leftEye, .minY))
        put(.leftEyeLower, extreme(leftEye, .maxY))
        put(.rightEyeUpper, extreme(rightEye, .minY))
        put(.rightEyeLower, extreme(rightEye, .maxY))

        // --- 眉 ---
        if browRegions.count == 2 {
            let (leftBrow, rightBrow) = splitByAnatomicalSide(browRegions[0], browRegions[1], isMirrored: isMirrored)
            put(.leftBrowOuter, extreme(leftBrow, isMirrored ? .minX : .maxX))
            put(.leftBrowInner, extreme(leftBrow, isMirrored ? .maxX : .minX))
            put(.rightBrowOuter, extreme(rightBrow, isMirrored ? .maxX : .minX))
            put(.rightBrowInner, extreme(rightBrow, isMirrored ? .minX : .maxX))
            put(.leftBrowPeak, extreme(leftBrow, .minY))
            put(.rightBrowPeak, extreme(rightBrow, .minY))

            if let li = table[.leftBrowInner]?.point, let ri = table[.rightBrowInner]?.point {
                put(.glabella, li.lerp(to: ri, t: 0.5))
            }
        }

        // --- 鼻 ---
        let noseCrest = points(landmarks.noseCrest)
        let nose = points(landmarks.nose)
        put(.noseBridgeTop, extreme(noseCrest, .minY))
        put(.noseBridgeMid, centroid(noseCrest))
        // 鼻尖 = 鼻梁脊线上最靠下的点；noseCrest 缺失时退回 nose 区域。
        put(.noseTip, extreme(noseCrest, .maxY) ?? extreme(nose, .maxY))
        put(.leftNoseAla, extreme(nose, isMirrored ? .minX : .maxX))
        put(.rightNoseAla, extreme(nose, isMirrored ? .maxX : .minX))

        // --- 口 ---
        let outerLips = points(landmarks.outerLips)
        let (lipLeft, lipRight) = (extreme(outerLips, .minX), extreme(outerLips, .maxX))
        put(.leftMouthCorner, isMirrored ? lipLeft : lipRight)
        put(.rightMouthCorner, isMirrored ? lipRight : lipLeft)
        put(.upperLipCenter, extreme(outerLips, .minY))
        put(.lowerLipCenter, extreme(outerLips, .maxY))
        if let upper = table[.upperLipCenter]?.point, let tip = table[.noseTip]?.point {
            put(.subnasale, tip.lerp(to: upper, t: 0.45))
        }

        // --- 轮廓 ---
        let contour = points(landmarks.faceContour)
        put(.chinCenter, extreme(contour, .maxY))
        let (contourLeft, contourRight) = (extreme(contour, .minX), extreme(contour, .maxX))
        put(.leftJawAngle, isMirrored ? contourLeft : contourRight)
        put(.rightJawAngle, isMirrored ? contourRight : contourLeft)

        // Vision 的 yaw/pitch/roll 单位是弧度，且相对相机原始视角。
        // 镜像预览会翻转 yaw 与 roll 的符号 —— 不修正的话「向左转头」的提示会反向。
        let mirrorSign: Double = isMirrored ? -1 : 1
        let pose = HeadPose(
            yawDegrees: (observation.yaw?.doubleValue ?? 0) * 180 / .pi * mirrorSign,
            pitchDegrees: (observation.pitch?.doubleValue ?? 0) * 180 / .pi,
            rollDegrees: (observation.roll?.doubleValue ?? 0) * 180 / .pi * mirrorSign
        )

        return FaceGeometry(
            providerID: descriptor.id,
            timestamp: timestamp,
            trackingState: .locked,
            pose: pose,
            landmarks: table,
            boundingBox: transform.viewRect(fromNormalizedRect: observation.boundingBox),
            viewSize: Size2D(viewSize),
            isMirrored: isMirrored,
            overallConfidence: Double(observation.confidence)
        )
    }

    // MARK: - 几何小工具

    private enum Extreme { case minX, maxX, minY, maxY }

    private func extreme(_ points: [Point2D], _ kind: Extreme) -> Point2D? {
        switch kind {
        case .minX: return points.min { $0.x < $1.x }
        case .maxX: return points.max { $0.x < $1.x }
        case .minY: return points.min { $0.y < $1.y }
        case .maxY: return points.max { $0.y < $1.y }
        }
    }

    private func centroid(_ points: [Point2D]) -> Point2D? {
        guard points.isEmpty == false else { return nil }
        var x = 0.0
        var y = 0.0
        for point in points {
            x += point.x
            y += point.y
        }
        return Point2D(x: x / Double(points.count), y: y / Double(points.count))
    }

    /// 按视图 x 判定解剖学左右，不依赖 Vision 的区域命名。
    private func splitByAnatomicalSide(
        _ a: [Point2D],
        _ b: [Point2D],
        isMirrored: Bool
    ) -> (left: [Point2D], right: [Point2D]) {
        let ax = centroid(a)?.x ?? 0
        let bx = centroid(b)?.x ?? 0
        // 镜像预览：用户的左半边脸在画面左侧（x 更小）。
        // 未镜像（相机原始视角）：用户的左半边脸在画面右侧。
        let aIsAnatomicalLeft = isMirrored ? (ax < bx) : (ax > bx)
        return aIsAnatomicalLeft ? (a, b) : (b, a)
    }
}
