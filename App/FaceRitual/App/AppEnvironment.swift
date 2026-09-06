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

        // 订阅实现按构建类型分开。
        //
        // Release **必须**走真实的 StoreKit —— 之前默认 Mock，意味着打包出去
        // 点订阅会直接解锁而不收钱。那不是「还没接」，是「接错了」。
        //
        // DEBUG 保留 Mock：模拟器上没有 App Store 沙盒商品，
        // `Product.products(for:)` 会返回空，Paywall 只能显示「暂时无法加载」，
        // 开发和 UI 测试就都走不通了。
        //
        // 真机沙盒测试请用 Release 构建，或在 Settings → Developer 里临时切换。
        // 有一条测试盯着这里：Release 不得使用 Mock（testReleaseUsesRealStoreKit）。
        let entitlementService: EntitlementService
        if let entitlement {
            entitlementService = entitlement
        } else {
            #if DEBUG
            entitlementService = MockEntitlementService(storage: UserDefaultsEntitlementFlagStorage())
            #else
            entitlementService = StoreKitEntitlementService()
            #endif
        }
        self.entitlement = entitlementService
        self.entitlementLevel = entitlementService.level

        voice.isEnabled = settings.voiceEnabled
        haptics.isEnabled = settings.hapticsEnabled

        #if !DEBUG
        // StoreKit 的商品与订阅状态要异步拉一次，否则 Paywall 打开时是空的。
        if let storeKit = entitlementService as? StoreKitEntitlementService {
            Task { await storeKit.refresh() }
        }
        #endif

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
    /// 除主推之外的其余 Morning 版本。
    ///
    /// Sprint 3 §4 一次给出三套 3 分钟原型，§7 要求「同一批用户交叉体验」——
    /// 所以另外两套必须是用户点得到的，不能藏在 Debug 页里。
    var alternateMorningRoutines: [Routine] {
        content.routines(ofType: .morning).filter { $0.id != content.morningCore?.id }
    }
    /// Gold Motion Library 里尚未通过 Expert Gate 的动作，供 Debug 页展示。
    var movesAwaitingExpertGate: [GoldMove] { content.movesAwaitingExpertGate }
    var allMoves: [GoldMove] { content.sortedMoves }

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
