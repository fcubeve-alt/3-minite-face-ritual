import SwiftUI
import FaceRitualCore

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showResetConfirm = false

    private var settings: AppSettings { environment.settings }

    var body: some View {
        Form {
            practiceSection
            reminderSection
            subscriptionSection
            cameraSection
            developerSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除所有练习记录？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                try? environment.practiceStore.deleteAll()
            }
        } message: {
            Text("此操作不可撤销。")
        }
    }

    // MARK: - 分区

    private var practiceSection: some View {
        Section("Practice") {
            Toggle("语音提示", isOn: Binding(
                get: { settings.voiceEnabled },
                set: { settings.voiceEnabled = $0; environment.syncFeedbackSettings() }
            ))
            Toggle("震动反馈", isOn: Binding(
                get: { settings.hapticsEnabled },
                set: { settings.hapticsEnabled = $0; environment.syncFeedbackSettings() }
            ))
        }
    }

    private var reminderSection: some View {
        Section {
            ForEach(ReminderKind.allCases) { kind in
                reminderRow(kind)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("提醒只是轻轻提示你照顾一下自己；错过了不会有任何惩罚。")
        }
    }

    private func reminderRow(_ kind: ReminderKind) -> some View {
        let setting = settings.reminder(kind)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(kind.displayName, isOn: Binding(
                get: { setting.isEnabled },
                set: { enabled in
                    var updated = setting
                    updated.isEnabled = enabled
                    settings.setReminder(kind, updated)
                    Task {
                        if enabled { _ = await environment.reminders.requestAuthorization() }
                        await environment.applyReminderSettings()
                    }
                }
            ))
            if setting.isEnabled {
                DatePicker(
                    "时间",
                    selection: Binding(
                        get: {
                            Calendar.current.date(
                                from: DateComponents(hour: setting.hour, minute: setting.minute)
                            ) ?? Date()
                        },
                        set: { date in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                            var updated = setting
                            updated.hour = components.hour ?? kind.defaultHour
                            updated.minute = components.minute ?? 0
                            settings.setReminder(kind, updated)
                            Task { await environment.applyReminderSettings() }
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    private var subscriptionSection: some View {
        Section {
            HStack {
                Text("当前状态")
                Spacer()
                Text(environment.entitlementLevel == .premium ? "Premium" : "Free")
                    .foregroundStyle(Theme.textSecondary)
            }
            if let mock = environment.entitlement as? MockEntitlementService {
                Toggle("Mock Unlock（开发用）", isOn: Binding(
                    get: { environment.entitlementLevel == .premium },
                    set: { unlocked in
                        mock.setMockUnlocked(unlocked)
                        environment.analytics.track(.mockUnlockToggled(enabled: unlocked))
                    }
                ))
            }
        } header: {
            Text("Subscription")
        } footer: {
            Text("M1 阶段使用 Mock Unlock。真实订阅（StoreKit）已接线但未启用；最终价格与条款是 Owner 待决策项。")
        }
    }

    private var cameraSection: some View {
        Section {
            HStack {
                Text("摄像头权限")
                Spacer()
                Text(cameraStatusText)
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("在系统设置中管理") { CameraPermission.openSettings() }
            Toggle("镜像预览（像照镜子）", isOn: Binding(
                get: { settings.mirrorPreview },
                set: { settings.mirrorPreview = $0 }
            ))
        } header: {
            Text("Camera")
        } footer: {
            Text("摄像头只在你主动打开 AR Mirror 时才会启用，随时可以关闭。Coach 模式完全不使用摄像头。")
        }
    }

    private var cameraStatusText: String {
        switch CameraPermission.status {
        case .authorized: return "已允许"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .notDetermined: return "未询问"
        }
    }

    private var developerSection: some View {
        Section {
            Picker("Face Alignment Provider", selection: Binding(
                get: { settings.preferredProviderKind },
                set: { settings.preferredProviderKind = $0 }
            )) {
                ForEach(FaceAlignmentProviderKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            Toggle("显示 AR Debug 图层", isOn: Binding(
                get: { settings.showDebugOverlay },
                set: { settings.showDebugOverlay = $0 }
            ))
            NavigationLink("Provider / 内容诊断") {
                DebugView()
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Provider 可运行时切换，用于 AR POC 的三方横评。切换后下次开始 AR Mirror 生效。")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("内容版本")
                Spacer()
                Text(environment.content.meta.contentVersion)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("清除练习记录", role: .destructive) { showResetConfirm = true }
        } header: {
            Text("About")
        } footer: {
            Text("本 App 提供的是日常护理引导，不构成医学诊断、治疗建议或疗效承诺。")
        }
    }
}
