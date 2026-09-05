import ARKit
import SwiftUI
import UIKit
import FaceRitualCore

/// ARKit 顶点索引标定工具。
///
/// 存在的理由：`ARFaceGeometry` 给的是 1220 个**无名**顶点，
/// Apple 从未公布「哪个编号是左眼外眼角」。网上流传的索引表来源不明且互相矛盾。
/// 我们不猜 —— 在脸上把 ● 画到错位置比不画更糟，还会污染 POC 结论。
///
/// 所以做这个工具：让人在自己脸上点一次，把编号标出来。
/// 流程：显示全部顶点 → 依次提示「点你的鼻尖」→ 取屏幕最近顶点 → 导出 JSON。
///
/// 导出后把 `arkit_vertex_map.json` 放进 App target 的 Resources，
/// `ARKitFaceAlignmentProvider` 就会自动变为可用。详见 docs/ARKIT_VERTEX_CALIBRATION.md。
struct ARKitCalibrationView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ARKitCalibrationController()

    @State private var exportedJSON: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if ARFaceTrackingConfiguration.isSupported {
                calibrationSurface
            } else {
                unsupportedNotice
            }
        }
        .navigationTitle("ARKit 顶点标定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            controller.targets = calibrationTargets
            controller.start()
        }
        .onDisappear { controller.stop() }
        .sheet(item: Binding(
            get: { exportedJSON.map(ExportPayload.init(json:)) },
            set: { if $0 == nil { exportedJSON = nil } }
        )) { payload in
            ExportSheet(json: payload.json)
        }
    }

    /// 需要标定的点 = 内容实际用到的 landmark，减去 ARKit 官方已保证的双眼中心。
    ///
    /// 只标真正需要的，不做完整 68 点表 ——
    /// 第一阶段只建 3–5 个测试 anchor（规格 §8），多标的部分现在没人用。
    private var calibrationTargets: [SemanticLandmark] {
        environment.requiredLandmarks
            .subtracting([.leftEyeCenter, .rightEyeCenter])
            .sorted { $0.rawValue < $1.rawValue }
    }

    private var calibrationSurface: some View {
        GeometryReader { proxy in
            ZStack {
                ARCalibrationPreview(controller: controller)
                    .ignoresSafeArea()

                // 全部 1220 个顶点，画成小点供瞄准。
                Canvas { context, _ in
                    for point in controller.projectedVertices {
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)),
                            with: .color(.green.opacity(0.5))
                        )
                    }
                    // 已标定的点用大一些的实心圆标出来。
                    for (_, index) in controller.calibrated {
                        guard controller.projectedVertices.indices.contains(index) else { continue }
                        let point = controller.projectedVertices[index]
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
                            with: .color(.cyan)
                        )
                    }
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // 显式写出 coordinateSpace，否则会和无参数的 onTapGesture 重载撞上。
                .onTapGesture(coordinateSpace: .local) { location in
                    controller.recordTap(at: location)
                }

                VStack {
                    instructionCard
                    Spacer()
                    controls
                }
                .padding(20)
            }
            .onChange(of: proxy.size) { _, newSize in
                controller.viewSize = newSize
            }
            .onAppear { controller.viewSize = proxy.size }
        }
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let target = controller.currentTarget {
                Text("请点击你脸上的")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(target.rawValue)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text(ARKitCalibrationView.humanHint(for: target))
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            } else {
                Text("全部标定完成")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 10) {
                Text("\(controller.calibrated.count) / \(controller.targets.count)")
                    .font(.caption.monospacedDigit())
                Text(controller.isTracking ? "追踪中" : "未检测到人脸")
                    .font(.caption)
                    .foregroundStyle(controller.isTracking ? Theme.accent : Theme.warning)
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("撤销上一个") { controller.undo() }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(controller.calibrated.isEmpty)

            Button("导出 JSON") {
                exportedJSON = controller.exportJSON()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(controller.calibrated.isEmpty)
        }
    }

    private var unsupportedNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "faceid")
                .font(.system(size: 40))
                .foregroundStyle(Theme.warning)
            Text("本机不支持 ARKit 人脸追踪")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("需要带 TrueDepth 前置相机的机型。可以先用 Vision provider 完成 POC。")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }

    /// 给标定者的人话提示。**只描述解剖学位置，不含任何护理或穴位含义。**
    static func humanHint(for landmark: SemanticLandmark) -> String {
        switch landmark {
        case .noseTip: return "鼻尖最前端"
        case .chinCenter: return "下巴最下缘的中点"
        case .leftBrowInner: return "你左边眉毛靠鼻子那一端"
        case .rightBrowInner: return "你右边眉毛靠鼻子那一端"
        case .leftEyeOuter: return "你左眼靠耳朵那一侧的眼角"
        case .rightEyeOuter: return "你右眼靠耳朵那一侧的眼角"
        case .mouthLeftCorner: return "你左边的嘴角"
        case .mouthRightCorner: return "你右边的嘴角"
        case .leftJawAngle: return "你左侧下颌骨转角处"
        case .rightJawAngle: return "你右侧下颌骨转角处"
        default: return landmark.rawValue
        }
    }
}

private struct ExportPayload: Identifiable {
    let json: String
    var id: String { json }
    init(json: String) { self.json = json }
}

/// 导出结果。给出可复制的 JSON 与放置位置说明。
private struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let json: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("把下面内容存成 arkit_vertex_map.json，放进 App/FaceRitual/Resources/ 并加入 target。")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Text(json)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .cardBackground()
                    Button("复制到剪贴板") {
                        UIPasteboard.general.string = json
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 控制器

/// 只负责标定所需的最小 ARKit 能力：投影全部顶点 + 记录点击最近的那个。
///
/// 刻意不复用 `ARKitFaceAlignmentProvider` ——
/// 那个类的职责是产出 FaceGeometry，混进标定逻辑会让两边都变复杂。
final class ARKitCalibrationController: NSObject, ObservableObject {

    @Published private(set) var projectedVertices: [CGPoint] = []
    @Published private(set) var calibrated: [(landmark: SemanticLandmark, index: Int)] = []
    @Published private(set) var isTracking = false

    var targets: [SemanticLandmark] = []
    var viewSize: CGSize = .zero

    let session = ARSession()

    var currentTarget: SemanticLandmark? {
        let done = Set(calibrated.map(\.landmark))
        return targets.first { done.contains($0) == false }
    }

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        session.delegate = nil
    }

    /// 记录距离点击位置最近的顶点。
    func recordTap(at location: CGPoint) {
        guard let target = currentTarget else { return }
        var best: (index: Int, distance: CGFloat)?
        for (index, point) in projectedVertices.enumerated() {
            let distance = hypot(point.x - location.x, point.y - location.y)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        // 点得太偏就不记 —— 免得把随手一点当成标定结果。
        guard let best, best.distance < 44 else { return }
        calibrated.append((target, best.index))
    }

    func undo() {
        guard calibrated.isEmpty == false else { return }
        calibrated.removeLast()
    }

    func exportJSON() -> String {
        let table = Dictionary(uniqueKeysWithValues: calibrated.map { ($0.landmark.rawValue, $0.index) })
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: table,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}

extension ARKitCalibrationController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        guard let anchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, anchor.isTracked else {
            DispatchQueue.main.async { [weak self] in
                self?.isTracking = false
                self?.projectedVertices = []
            }
            return
        }

        let camera = frame.camera
        let size = viewSize
        let points = anchor.geometry.vertices.map { vertex -> CGPoint in
            let world = anchor.transform * simd_float4(vertex, 1)
            let projected = camera.projectPoint(
                simd_float3(world.x, world.y, world.z),
                orientation: .portrait,
                viewportSize: size
            )
            // 标定界面**不镜像**：这样点击坐标与投影坐标在同一个空间里，
            // 少一层换算就少一处出错的机会。
            return projected
        }

        DispatchQueue.main.async { [weak self] in
            self?.isTracking = true
            self?.projectedVertices = points
        }
    }
}

/// 标定用的相机预览。不镜像 —— 理由见上。
private struct ARCalibrationPreview: UIViewRepresentable {
    let controller: ARKitCalibrationController

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = controller.session
        view.automaticallyUpdatesLighting = false
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
