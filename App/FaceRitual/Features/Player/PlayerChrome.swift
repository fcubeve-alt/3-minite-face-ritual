import SwiftUI
import FaceRitualCore

/// 播放器顶部：进度、动作名、左右侧、退出。
struct PlayerHeader: View {
    @ObservedObject var viewModel: RoutineSessionViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onExit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel(AppCopy.a11yClose)
                Spacer()
                if viewModel.routine.reviewStatus.isPublishable == false {
                    MockContentBadge(compact: true)
                }
            }

            // 整体进度条：用户随时知道「还剩多少」。
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: proxy.size.width * viewModel.routineProgress)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.currentSegment?.step.title ?? viewModel.routine.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(viewModel.currentSegment?.step.shortCue ?? "")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let side = viewModel.currentSegment?.side.shortLabel {
                    Text(side)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.0)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            OverlayPalette.accent(for: viewModel.currentSegment?.side ?? .none).opacity(0.22),
                            in: Capsule()
                        )
                        .foregroundStyle(OverlayPalette.accent(for: viewModel.currentSegment?.side ?? .none))
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

/// 播放器底部：上一动作 / 暂停 / 下一动作 + 倒计时。
struct PlayerControls: View {
    @ObservedObject var viewModel: RoutineSessionViewModel

    var body: some View {
        VStack(spacing: 18) {
            countdown

            HStack(spacing: 34) {
                controlButton("backward.end.fill", size: 18, label: AppCopy.a11yPreviousMove) {
                    viewModel.skipBackward()
                }
                Button {
                    viewModel.togglePause()
                } label: {
                    Image(systemName: viewModel.status == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.background)
                        .frame(width: 62, height: 62)
                        .background(Theme.accent, in: Circle())
                }
                .accessibilityLabel(viewModel.status == .paused ? AppCopy.a11yResume : AppCopy.a11yPause)
                controlButton("forward.end.fill", size: 18, label: AppCopy.a11yNextMove) {
                    viewModel.skipForward()
                }
            }
        }
        .padding(.bottom, 12)
    }

    private var countdown: some View {
        countdownVisual
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppCopy.a11yTimeRemaining(seconds: viewModel.secondsRemaining))
            .accessibilityValue(repetitionText ?? "")
    }

    private var countdownVisual: some View {
        ZStack {
            ProgressRing(progress: 1 - viewModel.segmentProgress, lineWidth: 4)
                .frame(width: 74, height: 74)
            VStack(spacing: 0) {
                Text("\(viewModel.secondsRemaining)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                if let reps = repetitionText {
                    Text(reps)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var repetitionText: String? {
        guard let segment = viewModel.currentSegment else { return nil }
        let total = segment.step.movement.repetitions
        guard total > 1 else { return nil }
        return "\(min(viewModel.completedRepetitions + 1, total))/\(total)"
    }

    private func controlButton(
        _ systemName: String,
        size: CGFloat,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.10), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

/// 开始前的 3-2-1。给用户一点时间把手抬起来。
struct PrepareCountdownOverlay: View {
    let remaining: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("\(remaining)")
                    .font(.system(size: 84, weight: .light, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(AppCopy.getReady)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .transition(.opacity)
    }
}

/// 退出确认。已完成部分仍会记录 —— 规格 §12 不惩罚中断。
struct ExitConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(AppCopy.exitTitle, isPresented: $isPresented) {
            Button(AppCopy.keepPracticing, role: .cancel) {}
            Button(AppCopy.endSession, role: .destructive, action: onConfirm)
        } message: {
            Text(AppCopy.exitMessage)
        }
    }
}
