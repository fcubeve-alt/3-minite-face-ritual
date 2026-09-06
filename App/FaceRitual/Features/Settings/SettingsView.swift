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
        .navigationTitle(AppCopy.settingsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(AppCopy.clearHistoryTitle, isPresented: $showResetConfirm) {
            Button(AppCopy.cancel, role: .cancel) {}
            Button(AppCopy.clearHistoryConfirm, role: .destructive) {
                try? environment.practiceStore.deleteAll()
            }
        } message: {
            Text(AppCopy.clearHistoryMessage)
        }
    }

    // MARK: - 分区

    private var practiceSection: some View {
        Section(AppCopy.sectionPractice) {
            Toggle(AppCopy.voiceCues, isOn: Binding(
                get: { settings.voiceEnabled },
                set: { settings.voiceEnabled = $0; environment.syncFeedbackSettings() }
            ))
            Toggle(AppCopy.haptics, isOn: Binding(
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
            Text(AppCopy.sectionReminders)
        } footer: {
            Text(AppCopy.remindersFooter)
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
                    AppCopy.reminderTime,
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
                Text(AppCopy.subscriptionStatus)
                Spacer()
                Text(environment.entitlementLevel == .premium ? AppCopy.statusPremium : AppCopy.statusFree)
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text(AppCopy.sectionSubscription)
        }
    }

    private var cameraSection: some View {
        Section {
            HStack {
                Text(AppCopy.cameraPermission)
                Spacer()
                Text(cameraStatusText)
                    .foregroundStyle(Theme.textSecondary)
            }
            Button(AppCopy.manageInSystemSettings) { CameraPermission.openSettings() }
            Toggle(AppCopy.mirrorPreview, isOn: Binding(
                get: { settings.mirrorPreview },
                set: { settings.mirrorPreview = $0 }
            ))
        } header: {
            Text(AppCopy.sectionCamera)
        } footer: {
            Text(AppCopy.cameraFooter)
        }
    }

    private var cameraStatusText: String {
        switch CameraPermission.status {
        case .authorized: return AppCopy.permissionAllowed
        case .denied: return AppCopy.permissionDenied
        case .restricted: return AppCopy.permissionRestricted
        case .notDetermined: return AppCopy.permissionNotAsked
        }
    }

    /// 开发面。只有团队会看，保留中文；用户面文案统一在 `AppCopy`。
    ///
    /// Mock Unlock 放在这里而不是 Subscription 区：它是开发开关，
    /// 普通用户不该在订阅设置里看到「Mock」这种字眼。
    private var developerSection: some View {
        Section {
            if let mock = environment.entitlement as? MockEntitlementService {
                Toggle("Mock Unlock（跳过付费墙）", isOn: Binding(
                    get: { environment.entitlementLevel == .premium },
                    set: { unlocked in
                        mock.setMockUnlocked(unlocked)
                        environment.analytics.track(.mockUnlockToggled(enabled: unlocked))
                    }
                ))
            }
            NavigationLink("Provider / 内容诊断") {
                DebugView()
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Provider 可运行时切换，用于 AR POC 的三方横评，切换后下次开始 AR Mirror 生效。"
                 + "订阅走 Mock Unlock；真实 StoreKit 已接线但未启用，最终价格与条款是 Owner 待决策项。")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text(AppCopy.contentVersion)
                Spacer()
                Text(environment.content.meta.contentVersion)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            NavigationLink(AppCopy.safetyScreenTitle) {
                SafetyView()
            }
            Button(AppCopy.clearHistory, role: .destructive) { showResetConfirm = true }
        } header: {
            Text(AppCopy.sectionAbout)
        } footer: {
            Text(AppCopy.medicalDisclaimer)
        }
    }
}
