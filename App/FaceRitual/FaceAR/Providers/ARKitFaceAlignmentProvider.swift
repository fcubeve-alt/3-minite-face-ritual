import ARKit
import UIKit
import FaceRitualCore

/// 基于 ARKit `ARFaceAnchor` 的 face alignment。
///
/// 优点：真 3D、姿态最准、TrueDepth 机型上跟随最稳。
/// 代价：`ARFaceGeometry` 给的是 1220 个**无名**顶点，
/// 想要「左眼外眼角」必须知道具体顶点编号，而 Apple 从未公布这张表。
///
/// 我们不猜编号。这里的做法是：
/// - 顶点索引表放在 `arkit_vertex_map.json`（App target 资源），可后补；
/// - 表缺失时，仅用 ARKit **官方保证**的量：`leftEyeTransform` / `rightEyeTransform`
///   / `lookAtPoint` / `transform`，加上 `Debug → ARKit 顶点标定` 工具现场标定；
/// - 未标定时 `isAvailable == false`，App 自动回落 Vision，不会白屏。
///
/// 这样 ARKit 仍然在 POC 的横评名单里，但不会因为一张猜出来的索引表
/// 把 ● 画到脸上的错误位置 —— 那比不显示更糟。
final class ARKitFaceAlignmentProvider: NSObject, FaceAlignmentProvider {

    static let vertexMapResourceName = "arkit_vertex_map"

    private var vertexMap: [SemanticLandmark: Int] = [:]
    private var mapLoadReason: String?

    override init() {
        super.init()
        loadVertexMap()
    }

    var descriptor: FaceProviderDescriptor {
        FaceProviderDescriptor(
            id: "arkit",
            displayName: "ARKit Face Mesh",
            summary: vertexMap.isEmpty
                ? "ARKit 人脸网格（1220 顶点）。顶点索引表未标定。"
                : "ARKit 人脸网格（1220 顶点），已标定 \(vertexMap.count) 个语义点。",
            requiresTrueDepth: true,
            supportedLandmarks: Set(vertexMap.keys),
            providesHeadPose: true,
            providesOcclusionEstimate: false
        )
    }

    var isAvailable: Bool {
        ARFaceTrackingConfiguration.isSupported && descriptor.canDriveGuidance
    }

    var unavailableReason: String? {
        if ARFaceTrackingConfiguration.isSupported == false {
            return "本机不支持 ARKit 人脸追踪（需要 TrueDepth 前置相机）。"
        }
        if descriptor.canDriveGuidance == false {
            return mapLoadReason
                ?? "缺少 \(ARKitFaceAlignmentProvider.vertexMapResourceName).json 顶点索引表。请用 Settings → Debug → ARKit 顶点标定 生成，或参考 docs/ARKIT_VERTEX_CALIBRATION.md。"
        }
        return nil
    }

    var onGeometry: ((FaceGeometry) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let session = ARSession()
    private var configuration = FaceAlignmentConfiguration(viewSize: .zero)
    private weak var previewView: ARSCNView?

    // MARK: - 顶点索引表

    private func loadVertexMap() {
        guard let url = Bundle.main.url(
            forResource: ARKitFaceAlignmentProvider.vertexMapResourceName,
            withExtension: "json"
        ) else { return }

        do {
            let raw = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))
            var table: [SemanticLandmark: Int] = [:]
            for (name, index) in raw {
                guard let mark = SemanticLandmark(rawValue: name) else {
                    mapLoadReason = "顶点索引表里有未知 landmark 名: \(name)"
                    continue
                }
                table[mark] = index
            }
            vertexMap = table
        } catch {
            mapLoadReason = "顶点索引表解析失败: \(error.localizedDescription)"
        }
    }

    /// 供标定工具写回索引表。
    func applyCalibratedVertexMap(_ map: [SemanticLandmark: Int]) {
        vertexMap = map
    }

    // MARK: - FaceAlignmentProvider

    func start(configuration: FaceAlignmentConfiguration) throws {
        guard ARFaceTrackingConfiguration.isSupported else {
            throw FaceAlignmentProviderError.unavailable("本机不支持 ARKit 人脸追踪")
        }
        self.configuration = configuration

        let arConfiguration = ARFaceTrackingConfiguration()
        arConfiguration.isLightEstimationEnabled = false
        arConfiguration.maximumNumberOfTrackedFaces = 1
        session.delegate = self
        session.run(arConfiguration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        session.delegate = nil
    }

    func updateViewSize(_ size: CGSize) {
        configuration.viewSize = size
    }

    func makePreviewView() -> UIView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersContinuously = true
        view.backgroundColor = .black
        // ARKit 的相机画面本身不镜像；AR Mirror 需要镜子观感，所以整个预览水平翻转。
        // 坐标投影侧由 ImageToViewTransform 的 isMirrored 对应处理。
        if configuration.isMirrored {
            view.layer.transform = CATransform3DMakeScale(-1, 1, 1)
        }
        previewView = view
        return view
    }
}

extension ARKitFaceAlignmentProvider: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let viewSize = configuration.viewSize
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let timestamp = frame.timestamp
        guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              faceAnchor.isTracked else {
            emit(FaceGeometry.notDetected(providerID: descriptor.id, timestamp: timestamp, viewSize: Size2D(viewSize)))
            return
        }

        let camera = frame.camera
        let orientation = UIInterfaceOrientation.portrait

        /// 顶点（人脸局部坐标）→ 屏幕坐标。
        func project(_ vertex: simd_float3) -> Point2D {
            let world = faceAnchor.transform * simd_float4(vertex, 1)
            let projected = camera.projectPoint(
                simd_float3(world.x, world.y, world.z),
                orientation: orientation,
                viewportSize: viewSize
            )
            var x = projected.x
            if configuration.isMirrored { x = viewSize.width - x }
            return Point2D(x: Double(x), y: Double(projected.y))
        }

        let vertices = faceAnchor.geometry.vertices
        var table: [SemanticLandmark: LandmarkSample] = [:]
        for (mark, index) in vertexMap where vertices.indices.contains(index) {
            table[mark] = LandmarkSample(point: project(vertices[index]), confidence: 1.0, isOccluded: false)
        }

        // 眼中心用 ARKit 官方保证的 eyeTransform，比任何顶点索引都可靠。
        // 注意 ARKit 的 left/right 是**解剖学**侧（相对被追踪的脸），与我们的约定一致。
        let leftEyeLocal = faceAnchor.leftEyeTransform.columns.3
        let rightEyeLocal = faceAnchor.rightEyeTransform.columns.3
        table[.leftEyeCenter] = LandmarkSample(
            point: project(simd_float3(leftEyeLocal.x, leftEyeLocal.y, leftEyeLocal.z)),
            confidence: 1.0
        )
        table[.rightEyeCenter] = LandmarkSample(
            point: project(simd_float3(rightEyeLocal.x, rightEyeLocal.y, rightEyeLocal.z)),
            confidence: 1.0
        )

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for sample in table.values {
            minX = min(minX, sample.point.x)
            minY = min(minY, sample.point.y)
            maxX = max(maxX, sample.point.x)
            maxY = max(maxY, sample.point.y)
        }

        let geometry = FaceGeometry(
            providerID: descriptor.id,
            timestamp: timestamp,
            trackingState: .locked,
            pose: ARKitFaceAlignmentProvider.headPose(from: faceAnchor, isMirrored: configuration.isMirrored),
            landmarks: table,
            boundingBox: Rect2D(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY)),
            viewSize: Size2D(viewSize),
            isMirrored: configuration.isMirrored,
            overallConfidence: 1.0
        )
        emit(geometry)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onFailure?(error) }
    }

    private func emit(_ geometry: FaceGeometry) {
        if Thread.isMainThread {
            onGeometry?(geometry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onGeometry?(geometry) }
        }
    }

    /// 从 face anchor 的变换矩阵取欧拉角。
    static func headPose(from anchor: ARFaceAnchor, isMirrored: Bool) -> HeadPose {
        let matrix = anchor.transform
        // 标准 ZYX 欧拉角分解。
        let sinPitch = -matrix.columns.2.y
        let pitch = asin(clamp(Double(sinPitch), -1, 1))
        let yaw = atan2(Double(matrix.columns.2.x), Double(matrix.columns.2.z))
        let roll = atan2(Double(matrix.columns.0.y), Double(matrix.columns.1.y))

        let sign: Double = isMirrored ? -1 : 1
        return HeadPose(
            yawDegrees: yaw * 180 / Double.pi * sign,
            pitchDegrees: pitch * 180 / Double.pi,
            rollDegrees: roll * 180 / Double.pi * sign
        )
    }
}
