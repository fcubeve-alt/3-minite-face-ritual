import Combine
import Foundation
import SwiftUI
import FaceRitualCore

/// 依赖容器。
///
/// 所有跨屏依赖都从这里注入，没有单例散落各处。
/// 这样把 Mock 换成真实实现（内容包、订阅、analytics、provider）时，
/// 改动集中在这一个文件里。
///
/// 主线程使用（由 SwiftUI 保证）。见 AppSettings 里关于不加 `@MainActor` 的说明。
final class AppEnvironment: ObservableObject {

    let settings: AppSettings
    let contentRepository: ContentRepository
    let practiceStore: PracticeStore
    let entitlement: EntitlementService
    let analytics: AnalyticsService
    let voice: VoiceCueServicing
    let haptics: HapticServicing
    let reminders: ReminderScheduler

    @Published private(set) var content: ContentBundle
    @Published private(set) var entitlementLevel: EntitlementLevel
    @Published private(set) var contentIssues: [ContentValidationIssue]
    /// 内容加载失败时的致命错误。UI 显示可读的说明而不是白屏。
    @Published private(set) var contentLoadError: String?

    /// UI 自动化测试用的启动参数。带上它就清空本地状态，让每次跑测试的起点一致。
    /// 只在 DEBUG 生效 —— 发布包里根本没有这段代码。
    static let uiTestResetArgument = "-FRUITestReset"

    init(
        settings: AppSettings = AppSettings(),
        contentRepository: ContentRepository? = nil,
        practiceStore: PracticeStore? = nil,
        entitlement: EntitlementService? = nil,
        analytics: AnalyticsService? = nil,
        voice: VoiceCueServicing = VoiceCueService(),
        haptics: HapticServicing = HapticService(),
        reminders: ReminderScheduler = ReminderScheduler()
    ) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(AppEnvironment.uiTestResetArgument) {
            AppEnvironment.resetLocalStateForUITests()
        }
        #endif

        self.settings = settings
        self.voice = voice
        self.haptics = haptics
        self.reminders = reminders

        let recordingAnalytics = RecordingAnalyticsService(forward: ConsoleAnalyticsService())
        self.analytics = analytics ?? recordingAnalytics

        // 内容校验：DEBUG 下失败即抛（早发现），Release 下降级放行（不让用户白屏）。
        #if DEBUG
        let failOnValidationError = true
        #else
        let failOnValidationError = false
        #endif

        let repository: ContentRepository
        var loadedBundle: ContentBundle
        var issues: [ContentValidationIssue] = []
        var loadError: String?

        do {
            let jsonRepository = try BundledContent.makeRepository(failOnValidationError: failOnValidationError)
            loadedBundle = try jsonRepository.load()
            issues = jsonRepository.validationIssues()
            repository = contentRepository ?? jsonRepository
        } catch {
            loadError = String(describing: error)
            loadedBundle = ContentBundle(
                meta: ContentMeta(schemaVersion: ContentSchema.currentVersion, contentVersion: "unavailable", reviewStatus: .mockUnreviewed),
                routines: [],
                anchors: [:]
            )
            repository = contentRepository ?? EmptyContentRepository()
        }

        self.contentRepository = repository
        self.content = loadedBundle
        self.contentIssues = issues
        self.contentLoadError = loadError

        self.practiceStore = practiceStore ?? ((try? FilePracticeStore.makeDefault()) ?? InMemoryPracticeStore())

        // M1 默认 Mock Unlock（Owner 指令）。切到 StoreKit 只需换这一行。
        let entitlementService = entitlement ?? MockEntitlementService(storage: UserDefaultsEntitlementFlagStorage())
        self.entitlement = entitlementService
        self.entitlementLevel = entitlementService.level

        voice.isEnabled = settings.voiceEnabled
        haptics.isEnabled = settings.hapticsEnabled

        entitlementService.onChange = { [weak self] level in
            // 订阅状态可能从 StoreKit 的后台队列变化，统一切回主线程再动 @Published。
            if Thread.isMainThread {
                self?.entitlementLevel = level
            } else {
                DispatchQueue.main.async { self?.entitlementLevel = level }
            }
        }

        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count
        if errorCount > 0 || warningCount > 0 {
            self.analytics.track(.contentValidationIssues(errorCount: errorCount, warningCount: warningCount))
        }
    }

    // MARK: - 便捷访问

    var morningCore: Routine? { content.morningCore }
    var eveningCore: Routine? { content.eveningCore }
    var quickRituals: [Routine] { content.quickRituals }

    /// 内容里出现的全部 landmark。用于检查所选 provider 是否够用。
    var requiredLandmarks: Set<SemanticLandmark> {
        var marks = Set(SemanticLandmark.required)
        for anchor in content.anchors.values {
            marks.formUnion(anchor.rule.referencedLandmarks)
        }
        return marks
    }

    func access(to routine: Routine, mode: PracticeMode) -> AccessDecision {
        EntitlementPolicy.decide(mode: mode, routine: routine, level: entitlementLevel)
    }

    func syncFeedbackSettings() {
        voice.isEnabled = settings.voiceEnabled
        haptics.isEnabled = settings.hapticsEnabled
    }

    func applyReminderSettings() async {
        for kind in ReminderKind.allCases {
            let setting = settings.reminder(kind)
            if setting.isEnabled {
                await reminders.schedule(kind: kind, hour: setting.hour, minute: setting.minute)
                analytics.track(.reminderScheduled(kind: kind.rawValue, hour: setting.hour, minute: setting.minute))
            } else {
                reminders.cancel(kind: kind)
                analytics.track(.reminderCancelled(kind: kind.rawValue))
            }
        }
    }

    /// 保存一次练习记录，并刷新月度统计。
    func record(_ session: PracticeSession) {
        do {
            try practiceStore.save(session)
        } catch {
            // 记录写入失败不应打断用户 —— 但要能在 Debug 页看到。
            analytics.track(.contentValidationIssues(errorCount: 0, warningCount: 1))
        }
        objectWillChange.send()
    }

    func currentMonthStats() -> MonthlyStats {
        practiceStore.currentMonthStats()
    }
}

#if DEBUG
extension AppEnvironment {
    /// 清空 UserDefaults 与练习记录。只给 UI 自动化测试用。
    static func resetLocalStateForUITests() {
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        try? FilePracticeStore.makeDefault().deleteAll()
    }
}
#endif

/// 内容加载失败时的空实现，避免 UI 需要处理 optional repository。
private final class EmptyContentRepository: ContentRepository, @unchecked Sendable {
    func load() throws -> ContentBundle {
        ContentBundle(
            meta: ContentMeta(schemaVersion: ContentSchema.currentVersion, contentVersion: "unavailable", reviewStatus: .mockUnreviewed),
            routines: [],
            anchors: [:]
        )
    }
}
