import Combine
import Foundation
import FaceRitualCore

/// 用户设置。UserDefaults 支撑，`@Published` 驱动 UI。
///
/// 主线程使用（由 SwiftUI 保证）。刻意不加 `@MainActor` ——
/// provider 的回调是 nonisolated 闭包，加了会让整条回调链无法直接调用。
final class AppSettings: ObservableObject {

    private enum Key {
        static let providerKind = "settings.faceProviderKind"
        static let mirrored = "settings.mirrorPreview"
        static let voice = "settings.voiceEnabled"
        static let haptics = "settings.hapticsEnabled"
        static let debugOverlay = "settings.debugOverlay"
        static let preferredMode = "settings.preferredPracticeMode"
        static let hasLaunchedBefore = "settings.hasLaunchedBefore"
        static func reminderEnabled(_ kind: ReminderKind) -> String { "settings.reminder.\(kind.rawValue).enabled" }
        static func reminderHour(_ kind: ReminderKind) -> String { "settings.reminder.\(kind.rawValue).hour" }
        static func reminderMinute(_ kind: ReminderKind) -> String { "settings.reminder.\(kind.rawValue).minute" }
    }

    private let defaults: UserDefaults

    @Published var preferredProviderKind: FaceAlignmentProviderKind {
        didSet { defaults.set(preferredProviderKind.rawValue, forKey: Key.providerKind) }
    }

    /// AR Mirror 默认镜像 —— 用户期待的是镜子，不是相机原始视角。
    @Published var mirrorPreview: Bool {
        didSet { defaults.set(mirrorPreview, forKey: Key.mirrored) }
    }

    @Published var voiceEnabled: Bool {
        didSet { defaults.set(voiceEnabled, forKey: Key.voice) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    /// Debug overlay：显示语义 landmark 与脸部坐标轴。POC 阶段的主要观察工具。
    @Published var showDebugOverlay: Bool {
        didSet { defaults.set(showDebugOverlay, forKey: Key.debugOverlay) }
    }

    @Published var preferredMode: PracticeMode {
        didSet { defaults.set(preferredMode.rawValue, forKey: Key.preferredMode) }
    }

    @Published var reminders: [ReminderKind: ReminderSetting] {
        didSet { persistReminders() }
    }

    let isFirstLaunch: Bool

    struct ReminderSetting: Equatable {
        var isEnabled: Bool
        var hour: Int
        var minute: Int
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        isFirstLaunch = defaults.bool(forKey: Key.hasLaunchedBefore) == false
        defaults.set(true, forKey: Key.hasLaunchedBefore)

        preferredProviderKind = defaults.string(forKey: Key.providerKind)
            .flatMap(FaceAlignmentProviderKind.init(rawValue:))
            ?? FaceAlignmentProviderFactory.defaultKind

        mirrorPreview = defaults.object(forKey: Key.mirrored) as? Bool ?? true
        voiceEnabled = defaults.object(forKey: Key.voice) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        showDebugOverlay = defaults.bool(forKey: Key.debugOverlay)
        preferredMode = defaults.string(forKey: Key.preferredMode)
            .flatMap(PracticeMode.init(rawValue:)) ?? .coach

        var loaded: [ReminderKind: ReminderSetting] = [:]
        for kind in ReminderKind.allCases {
            loaded[kind] = ReminderSetting(
                isEnabled: defaults.bool(forKey: Key.reminderEnabled(kind)),
                hour: defaults.object(forKey: Key.reminderHour(kind)) as? Int ?? kind.defaultHour,
                minute: defaults.object(forKey: Key.reminderMinute(kind)) as? Int ?? 0
            )
        }
        reminders = loaded
    }

    private func persistReminders() {
        for (kind, setting) in reminders {
            defaults.set(setting.isEnabled, forKey: Key.reminderEnabled(kind))
            defaults.set(setting.hour, forKey: Key.reminderHour(kind))
            defaults.set(setting.minute, forKey: Key.reminderMinute(kind))
        }
    }

    func reminder(_ kind: ReminderKind) -> ReminderSetting {
        reminders[kind] ?? ReminderSetting(isEnabled: false, hour: kind.defaultHour, minute: 0)
    }

    func setReminder(_ kind: ReminderKind, _ setting: ReminderSetting) {
        reminders[kind] = setting
    }

    func resetToDefaults() {
        preferredProviderKind = FaceAlignmentProviderFactory.defaultKind
        mirrorPreview = true
        voiceEnabled = true
        hapticsEnabled = true
        showDebugOverlay = false
        preferredMode = .coach
        reminders = Dictionary(
            uniqueKeysWithValues: ReminderKind.allCases.map {
                ($0, ReminderSetting(isEnabled: false, hour: $0.defaultHour, minute: 0))
            }
        )
    }
}
