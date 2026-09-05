import AVFoundation
import Foundation
import QuartzCore
import UIKit
import UserNotifications
import FaceRitualCore

// MARK: - Ticker

/// 把真实时间喂给 `RoutinePlayerEngine`。
///
/// 引擎本身不含 Timer，正是为了让这一层可以被替换成测试里的固定步长。
///
/// 继承 NSObject 是必需的：`CADisplayLink(target:selector:)` 走 ObjC runtime。
final class DisplayLinkTicker: NSObject {
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private let onTick: (Double) -> Void

    init(onTick: @escaping (Double) -> Void) {
        self.onTick = onTick
        super.init()
    }

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step))
        // 计时不需要 120Hz；30Hz 足够且省电。
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0 else { return }
        let delta = link.timestamp - lastTimestamp
        // 切后台再回来会产生巨大的 delta —— 钳住，避免 routine 瞬间跳完。
        guard delta > 0, delta < 1.0 else { return }
        onTick(delta)
    }

    deinit { stop() }
}

// MARK: - 语音

protocol VoiceCueServicing: AnyObject {
    var isEnabled: Bool { get set }
    func speak(_ text: String)
    func stop()
}

/// 语音提示。用系统 TTS 而不是录音：
/// M1 阶段动作内容还会反复替换，录音会立刻过期。
final class VoiceCueService: NSObject, VoiceCueServicing {
    private let synthesizer = AVSpeechSynthesizer()
    var isEnabled: Bool = true

    func speak(_ text: String) {
        guard isEnabled, text.isEmpty == false else { return }
        // 新提示直接打断旧的 —— 换动作时不应该听到上一个动作的尾巴。
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - 触觉

protocol HapticServicing: AnyObject {
    var isEnabled: Bool { get set }
    func stepChange()
    func countdownTick()
    func cyclePulse()
    func completion()
}

final class HapticService: HapticServicing {
    var isEnabled: Bool = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    init() {
        light.prepare()
        medium.prepare()
    }

    func stepChange() {
        guard isEnabled else { return }
        medium.impactOccurred()
        medium.prepare()
    }

    func countdownTick() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.6)
        light.prepare()
    }

    func cyclePulse() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.35)
    }

    func completion() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }
}

// MARK: - 摄像头权限

enum CameraPermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// 规格 §4：摄像头必须由用户主动开启，可随时关闭。
/// 因此权限请求只在用户点击「打开 AR Mirror」之后发生，绝不在启动时请求。
enum CameraPermission {

    static var status: CameraPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 提醒

enum ReminderKind: String, CaseIterable, Identifiable {
    case morning
    case evening

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: return "Morning Reminder"
        case .evening: return "Evening Reminder"
        }
    }

    var defaultHour: Int {
        switch self {
        case .morning: return 8
        case .evening: return 21
        }
    }

    /// 规格 §12：文案避免焦虑与羞耻感，强调轻量照顾自己。
    /// 这些是**提醒文案**，不涉及任何动作或功效声明。
    var body: String {
        switch self {
        case .morning: return "Three minutes for your face. Whenever you're ready."
        case .evening: return "Wind down with a few slow minutes."
        }
    }

    var title: String { "3-Minute Face Ritual" }
}

final class ReminderScheduler {

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func schedule(kind: ReminderKind, hour: Int, minute: Int) async {
        cancel(kind: kind)

        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: kind.rawValue,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    func cancel(kind: ReminderKind) {
        center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
    }

    func pendingKinds() async -> Set<ReminderKind> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.compactMap { ReminderKind(rawValue: $0.identifier) })
    }
}

// MARK: - 订阅状态存储

/// Core 不依赖 UserDefaults（它是平台 API），所以桥接放在 App 层。
final class UserDefaultsEntitlementFlagStorage: EntitlementFlagStorage {
    private let key = "com.faceritual.mockPremiumUnlocked"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPremiumFlag() -> Bool { defaults.bool(forKey: key) }
    func savePremiumFlag(_ value: Bool) { defaults.set(value, forKey: key) }
}
