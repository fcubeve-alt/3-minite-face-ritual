import SwiftUI
import UIKit
import FaceRitualCore

/// Personalized AR Mirror Guidance（规格 §6.2）—— M1 里程碑的核心画面。
///
/// 目标很克制：让用户在自己的脸上稳定看到
/// ● 起点 / ◎ 终点 / → 动态路线 / 手势 / 节奏 / 左右侧。
/// **不做**实时动作纠错，**不判断**按压力度，
/// 手遮住脸时也**不输出**任何「正确 / 错误」（规格 §10）。
struct ARMirrorView: View {
    @StateObject private var viewModel: RoutineSessionViewModel

    /// autoclosure：`@StateObject` 只在首次构建时求值，
    /// 避免每次重绘都新建一个 ARGuidanceController（那会重复创建 provider 和相机会话）。
    init(viewModel: @autoclosure @escaping () -> RoutineSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        if let guidance = viewModel.guidance {
            // guidance 必须作为 @ObservedObject 传进子视图，
            // 否则每帧的 guidanceFrame 变化不会触发重绘，overlay 会是静止的。
            ARMirrorContent(viewModel: viewModel, guidance: guidance)
        } else {
            // 理论上不会走到 —— AR/Watch 模式一定带 guidance。
            CoachPlayerView(viewModel: viewModel)
        }
    }
}

private struct ARMirrorContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: RoutineSessionViewModel
    @ObservedObject var guidance: ARGuidanceController

    @State private var showExitConfirm = false
    @State private var showDone = false
    /// 连续这么久锁不上，才认为「AR 对这位用户当下不好用」。
    /// 计时由 ARGuidanceController 用帧时间戳完成，视图不另起时钟。
    private let fallbackPromptThreshold: Double = 12

    private var isWatchMode: Bool { viewModel.mode == .watch }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.didFallBackToCoach {
                    // 已退回 Coach：关掉摄像头画面，但**播放器继续跑**。
                    Theme.background.ignoresSafeArea()
                    CoachStageView(
                        segment: viewModel.currentSegment,
                        cyclePhase: viewModel.segmentProgress
                    )
                    .padding(.top, 150)
                    .padding(.bottom, 190)
                } else {
                    CameraPreviewRepresentable(controller: guidance)
                        .ignoresSafeArea()

                    AROverlayRenderer(
                        frame: guidance.guidanceFrame,
                        showsDebugOverlay: environment.settings.showDebugOverlay
                    )
                    .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    PlayerHeader(viewModel: viewModel) { showExitConfirm = true }
                        .padding(.top, 8)

                    if viewModel.didFallBackToCoach {
                        fellBackNotice
                    } else {
                        statusStrip
                    }

                    Spacer()

                    if isWatchMode {
                        watchModeFooter
                    } else {
                        PlayerControls(viewModel: viewModel)
                    }
                }

                if let remaining = viewModel.prepareCountdown {
                    PrepareCountdownOverlay(remaining: remaining)
                }
            }
            .onAppear {
                viewModel.startGuidance(viewSize: proxy.size)
                viewModel.start()
            }
            .onChange(of: proxy.size) { _, newSize in
                guidance.updateViewSize(newSize)
            }
        }
        .modifier(ExitConfirmationModifier(isPresented: $showExitConfirm) {
            viewModel.abandon()
            showDone = true
        })
        .fullScreenCover(isPresented: $showDone, onDismiss: { dismiss() }) {
            DoneView(session: viewModel.completedSession, routine: viewModel.routine)
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            if finished { showDone = true }
        }
        .onDisappear { viewModel.abandon() }
        .statusBarHidden()
    }

    // MARK: - 状态条

    /// 只显示**中性引导**：往哪站、脸放正。
    /// 永远不显示「你做对了 / 做错了」—— 那是我们明确不承诺的能力（规格 §10）。
    @ViewBuilder
    private var statusStrip: some View {
        VStack(spacing: 8) {
            if let notice = guidance.fallbackNotice {
                banner(text: notice, tint: Theme.warning, icon: "arrow.triangle.2.circlepath")
            }
            if let error = guidance.lastError {
                banner(text: error, tint: Theme.warning, icon: "exclamationmark.triangle")
            }
            if let message = guidance.guidanceFrame.hint.message, guidance.guidanceFrame.quality != .good {
                banner(
                    text: message,
                    tint: guidance.guidanceFrame.quality == .lost ? Theme.warning : Theme.accent,
                    icon: guidance.trackingState == .locked ? "viewfinder" : "person.crop.circle.dashed"
                )
            }
            if guidance.continuousLostSeconds >= fallbackPromptThreshold {
                fallbackPrompt
            }
            if environment.settings.showDebugOverlay {
                debugStrip
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .animation(.easeOut(duration: 0.2), value: guidance.guidanceFrame.hint)
    }

    /// 规格 §4：识别失败不得阻塞 routine。
    ///
    /// 所以这是**建议**而不是拦截 —— 不弹模态、不暂停计时。
    /// 用户可以一直无视它把 routine 做完。
    private var fallbackPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("这里的光线或角度可能不太适合 AR。")
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
            Button {
                viewModel.fallBackToCoach(reason: "user_prompted_after_\(Int(fallbackPromptThreshold))s_lost")
            } label: {
                Text("切到 Coach 继续，不中断计时")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity)
    }

    private var fellBackNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill")
                .font(.footnote)
            Text("已切到 Coach 模式，这次练习继续计入记录。")
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func banner(text: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// POC 阶段的现场读数。报告要的 FPS / provider / 丢锁次数都在这。
    private var debugStrip: some View {
        HStack(spacing: 12) {
            debugCell("provider", guidance.providerDescriptor.id)
            debugCell("fps", String(format: "%.0f", guidance.currentFPS))
            debugCell("lat", String(format: "%.0fms", guidance.performanceMonitor.averageLatencyMS))
            debugCell("lock", guidance.trackingState.rawValue)
            debugCell("loss", "\(guidance.lockLossCount)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func debugCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    /// Watch & Breathe（规格 §6.3）：只看路线动画，不动手。
    ///
    /// 刻意保留免责说明 —— 规格明确要求不得宣称「看了等于做了」。
    private var watchModeFooter: some View {
        VStack(spacing: 14) {
            Text("Just watch and breathe.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("这是动作预习与视觉放松，不等同于实际按摩。")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            Button {
                viewModel.togglePause()
            } label: {
                Image(systemName: viewModel.status == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.background)
                    .frame(width: 56, height: 56)
                    .background(Theme.accent, in: Circle())
            }
        }
        .padding(.bottom, 26)
        .padding(.horizontal, 30)
        .multilineTextAlignment(.center)
    }
}

/// 把 provider 提供的预览视图（AVCaptureVideoPreviewLayer 或 ARSCNView）接进 SwiftUI。
///
/// 预览视图由 provider 自己创建 —— ARKit 与 AVCapture 的预览方式不同，
/// 让每个 provider 各自负责，比在这里做分支干净。
struct CameraPreviewRepresentable: UIViewRepresentable {
    let controller: ARGuidanceController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        let preview = controller.makePreviewView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
