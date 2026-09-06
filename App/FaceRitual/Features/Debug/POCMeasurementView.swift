import SwiftUI
import UIKit
import FaceRitualCore

/// 真机 AR POC 的测量台。
///
/// 存在的理由：`AR_POC_REPORT.md` §2 原本要求人肉观察九项指标再手填表格。
/// 那么做出来的数据既费事又不可比 ——「有点漂」没法拿去和另一个 provider 比，
/// 也没法在调完 One Euro 参数之后判断到底变好了没有。
///
/// 现在流程是：选场景 → 按住那个姿势十几秒 → 停止 → 换下一个 → 全部测完导出 JSON。
///
/// 它测的是**系统自己的表现**（识别质量、帧率、位置稳定性），
/// 不是「用户做得对不对」—— 后者规格 §10 明确不做，领域模型里根本没有那个字段。
struct POCMeasurementView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model: POCMeasurementModel

    init(anchors: [FaceAnchorID: FaceAnchor], provider: FaceAlignmentProviderKind) {
        _model = StateObject(wrappedValue: POCMeasurementModel(anchors: anchors, provider: provider))
    }

    @State private var exportText: String?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                preview
                    .frame(height: proxy.size.height * 0.42)
                    .clipped()
                controls
            }
            .onAppear {
                model.start(
                    viewSize: CGSize(width: proxy.size.width, height: proxy.size.height * 0.42),
                    isMirrored: environment.settings.mirrorPreview
                )
            }
        }
        .background(Theme.background)
        .navigationTitle("POC 测量")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stop() }
        .sheet(item: Binding(
            get: { exportText.map(POCExportPayload.init(text:)) },
            set: { if $0 == nil { exportText = nil } }
        )) { payload in
            POCExportSheet(text: payload.text)
        }
    }

    // MARK: - 画面

    private var preview: some View {
        ZStack {
            Color.black
            CameraPreviewRepresentable(controller: model.guidance)
            // 只画 landmark 与坐标轴，不画动作路线 —— 这里测的是几何本身。
            AROverlayRenderer(frame: model.guidance.guidanceFrame, showsDebugOverlay: true)
            VStack {
                HStack(spacing: 10) {
                    readout("fps", String(format: "%.0f", model.guidance.currentFPS))
                    readout("质量", model.guidance.guidanceFrame.quality.rawValue)
                    readout("锁定", model.guidance.trackingState.rawValue)
                    if model.recorder.isRecording {
                        readout("帧", "\(model.recorder.currentFrameCount)")
                    }
                }
                .padding(.top, 8)
                Spacer()
            }
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - 操作区

    private var controls: some View {
        List {
            if model.recorder.isRecording {
                recordingSection
            } else {
                scenarioSection
            }
            if model.recorder.completed.isEmpty == false {
                resultsSection
            }
            noticeSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private var scenarioSection: some View {
        Section {
            ForEach(POCRecorder.standardScenarios) { scenario in
                Button {
                    model.begin(scenario)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.label)
                                .foregroundStyle(Theme.textPrimary)
                            Text(scenario.section)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        if model.measuredScenarioIDs.contains(scenario.id) {
                            Text("已测").font(.caption).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        } header: {
            Text("选一个场景开始（provider：\(model.guidance.providerDescriptor.id)）")
        } footer: {
            Text("摆好姿势再点，保持 10–20 秒。测完可以换 provider 再测一轮，两轮数据会一起导出。")
        }
    }

    private var recordingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.recorder.currentScenario?.label ?? "")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("已采集 \(model.recorder.currentFrameCount) 帧 —— 保持住这个姿势")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                TextField("备注（可选，数值答不了「看起来怎么样」）", text: $model.note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    Button("停止并记录") { model.finish() }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("丢弃") { model.cancel() }
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("正在测量")
        }
    }

    private var resultsSection: some View {
        Section {
            ForEach(Array(model.recorder.completed.enumerated()), id: \.offset) { _, measurement in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(measurement.scenario.label)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(measurement.providerID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(String(
                        format: "%.0fs · %.1f fps · good %.0f%% / deg %.0f%% / lost %.0f%%",
                        measurement.durationSeconds, measurement.averageFPS,
                        measurement.goodRatio * 100, measurement.degradedRatio * 100,
                        measurement.lostRatio * 100
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    if let worst = measurement.stability.max(by: { $0.driftP95 < $1.driftP95 }) {
                        Text(String(
                            format: "最差漂移 %@ p95=%.3f 瞳距（容差的 %.0f%%）· 抖动中位 %.4f",
                            worst.anchorID, worst.driftP95, worst.driftRatio * 100, worst.jitterMedian
                        ))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(worst.driftRatio > 1 ? Theme.warning : Theme.textTertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            Button("导出全部（\(model.recorder.completed.count) 条）") {
                exportText = model.exportText(contentVersion: environment.content.meta.contentVersion)
            }
            Button("清空") { model.discardAll() }
                .foregroundStyle(Theme.warning)
        } header: {
            Text("已完成")
        }
    }

    private var noticeSection: some View {
        Section {
            Text("""
            漂移是怎么算出来的：anchor 在**脸部局部坐标系**里的位置理论上恒定 \
            —— 坐标系以双眼为基准、以瞳距为单位，对远近、平移、歪头天然不变 \
            （离线 golden vector 已证明，6 种变换下漂移 2e-15 瞳距）。\
            所以它在真人脸上的残余波动就是漂移本身，不需要任何真值标注。

            漂移 = 相对整段均值的偏离（点慢慢跑偏）。
            抖动 = 相邻帧的位移（点在原地抖）。
            两者要调的滤波参数不同：抖动大调小 minCutoff，跟随滞后调大 beta。
            """)
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Model

/// 把 AR 会话和记录器串起来。
///
/// 刻意不加 `@MainActor`：provider 的回调是 nonisolated 的，
/// 加了之后没法直接调这里的方法（和 ARGuidanceController 同样的原因）。
final class POCMeasurementModel: ObservableObject {

    let guidance: ARGuidanceController
    let recorder = POCRecorder()

    @Published var note: String = ""
    /// 已经测过的场景 id —— 用来在列表里标「已测」，避免漏测或重复测。
    @Published private(set) var measuredScenarioIDs: Set<String> = []
    /// 采集期间驱动界面刷新（帧计数）。
    @Published private(set) var tick: Int = 0

    private var timer: Timer?

    init(anchors: [FaceAnchorID: FaceAnchor], provider: FaceAlignmentProviderKind) {
        guidance = ARGuidanceController(anchors: anchors, preferredProvider: provider)
        guidance.pocRecorder = recorder
    }

    func start(viewSize: CGSize, isMirrored: Bool) {
        guidance.start(viewSize: viewSize, isMirrored: isMirrored)
        // 记录器不是 ObservableObject（它是纯 Core 类型，不该依赖 Combine），
        // 所以用一个低频计时器驱动界面刷新帧计数。2Hz 够用，不浪费。
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.recorder.isRecording else { return }
            self.tick &+= 1
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guidance.stop()
    }

    func begin(_ scenario: POCRecorder.Scenario) {
        note = ""
        recorder.begin(scenario: scenario)
        objectWillChange.send()
    }

    func cancel() {
        recorder.cancel()
        objectWillChange.send()
    }

    func finish() {
        let monitor = guidance.performanceMonitor
        let measurement = recorder.finish(
            providerID: guidance.providerDescriptor.id,
            averageFPS: monitor.averageFPS,
            averageLatencyMS: monitor.averageLatencyMS,
            p95LatencyMS: monitor.p95LatencyMS,
            stutterCount: monitor.stutterCount,
            lockLossCount: guidance.lockLossCount,
            timeToFirstLockSeconds: guidance.timeToFirstLock,
            note: note.isEmpty ? nil : note
        )
        if let measurement {
            measuredScenarioIDs.insert(measurement.scenario.id)
        }
        note = ""
        objectWillChange.send()
    }

    func discardAll() {
        recorder.discardAll()
        measuredScenarioIDs.removeAll()
        objectWillChange.send()
    }

    func exportText(contentVersion: String) -> String {
        let report = recorder.makeReport(
            deviceModel: UIDevice.current.model + " / " + deviceIdentifier(),
            systemVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            contentVersion: contentVersion
        )
        let json = (try? report.encodedJSON()).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return report.markdownTable + "\n\n<!-- 原始数据 -->\n" + json
    }

    /// `UIDevice.model` 只会说 "iPhone"。真机型号要从 uname 取。
    private func deviceIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
        }
    }
}

// MARK: - 导出

private struct POCExportPayload: Identifiable {
    let text: String
    var id: String { text }
}

private struct POCExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("上半段是可以直接贴进 AR_POC_REPORT.md 的表格，下半段是原始 JSON。")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .cardBackground()
                    Button("复制到剪贴板") { UIPasteboard.general.string = text }
                        .buttonStyle(PrimaryButtonStyle())
                    ShareLink(item: text) {
                        Text("分享…").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("POC 数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
