import SwiftUI
import FaceRitualCore

/// Routine 详情 + 模式选择（规格 §6 的三种练习体验）。
///
/// 摄像头相关的一切都在这里守门：
/// 只有当用户主动选择 AR Mirror / Watch & Breathe 时才请求权限（规格 §4）。
struct RoutineDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let routine: Routine
    var presentedModally: Bool = false

    @State private var activeMode: PracticeMode?
    @State private var showPaywall = false
    @State private var cameraDeniedAlert = false
    @State private var isRequestingCamera = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                modePicker
                stepList
                if let note = routine.safetyNote {
                    safetyNote(note)
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle(routine.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedModally {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppCopy.close) { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $activeMode) { mode in
            sessionView(for: mode)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "routine_\(routine.id.rawValue)")
        }
        .alert(AppCopy.cameraNeededTitle, isPresented: $cameraDeniedAlert) {
            Button(AppCopy.openSettings) { CameraPermission.openSettings() }
            Button(AppCopy.useCoachInstead) { activeMode = .coach }
            Button(AppCopy.cancel, role: .cancel) {}
        } message: {
            Text(AppCopy.cameraNeededMessage)
        }
    }

    // MARK: - 区块

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(routine.formattedDuration) · \(routine.steps.count) moves")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if routine.reviewStatus.isPublishable == false {
                    MockContentBadge(compact: true)
                }
            }
            if let subtitle = routine.subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppCopy.howToPractice)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(availableModes, id: \.self) { mode in
                modeRow(mode)
            }
        }
    }

    private var availableModes: [PracticeMode] {
        var modes: [PracticeMode] = [.coach]
        if routine.usesARGuidance {
            modes.append(.arMirror)
            modes.append(.watch)
        }
        return modes
    }

    private func modeRow(_ mode: PracticeMode) -> some View {
        let locked = environment.access(to: routine, mode: mode) == .requiresPremium

        return Button {
            select(mode)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 19))
                    .frame(width: 30)
                    .foregroundStyle(mode == .arMirror ? Theme.accent : Theme.textPrimary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mode.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        if mode == .watch {
                            Text(AppCopy.experimentalTag)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.textTertiary.opacity(0.2), in: Capsule())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text(mode.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .cardBackground(elevated: mode == .arMirror)
        }
        .buttonStyle(.plain)
        .disabled(isRequestingCamera)
        .accessibilityIdentifier(A11yID.mode(mode.rawValue))
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppCopy.inThisRitual)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(step.shortCue)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("\(Int(step.durationSeconds))s")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .cardBackground()
            }
        }
    }

    private func safetyNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.textTertiary)
            Text(note)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// 注意：view model 直接写在调用处，不先 let 出来 ——
    /// 两个播放视图的 init 都是 autoclosure，这样才能真正延迟到 `@StateObject` 首次构建时求值。
    @ViewBuilder
    private func sessionView(for mode: PracticeMode) -> some View {
        switch mode {
        case .coach:
            CoachPlayerView(
                viewModel: RoutineSessionViewModel(routine: routine, mode: mode, environment: environment)
            )
        case .arMirror, .watch:
            ARMirrorView(
                viewModel: RoutineSessionViewModel(routine: routine, mode: mode, environment: environment)
            )
        }
    }

    // MARK: - 动作

    private func select(_ mode: PracticeMode) {
        guard environment.access(to: routine, mode: mode) == .allowed else {
            showPaywall = true
            return
        }
        environment.analytics.track(.modeSelected(mode: mode, routineID: routine.id))
        environment.settings.preferredMode = mode

        guard mode != .coach else {
            activeMode = .coach
            return
        }
        requestCameraThenStart(mode)
    }

    /// 规格 §4：摄像头由用户主动开启。权限请求只发生在这里。
    ///
    /// 先看**实际会被用到的那个 provider** 需不需要摄像头 ——
    /// Mock provider 生成的是合成脸，不碰摄像头，那就不该弹权限框。
    /// 这条同时让模拟器上的自动化测试能跑通整条闭环（模拟器没有摄像头）。
    private func requestCameraThenStart(_ mode: PracticeMode) {
        let resolved = FaceAlignmentProviderFactory
            .makeFirstAvailable(preferring: environment.settings.preferredProviderKind)
            .provider
        guard resolved.descriptor.requiresCamera else {
            activeMode = mode
            return
        }

        switch CameraPermission.status {
        case .authorized:
            activeMode = mode
        case .denied, .restricted:
            cameraDeniedAlert = true
        case .notDetermined:
            isRequestingCamera = true
            environment.analytics.track(.cameraPermissionRequested)
            Task {
                let granted = await CameraPermission.request()
                await MainActor.run {
                    isRequestingCamera = false
                    environment.analytics.track(.cameraPermissionResult(granted: granted))
                    if granted {
                        activeMode = mode
                    } else {
                        cameraDeniedAlert = true
                    }
                }
            }
        }
    }
}

