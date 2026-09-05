import Foundation

public enum EntitlementLevel: String, Codable, Sendable {
    case free
    case premium
}

public enum AccessDecision: Sendable, Hashable {
    case allowed
    case requiresPremium

    public var isAllowed: Bool { self == .allowed }
}

/// 规格 §11 的免费/付费边界。
///
/// 这是**产品承诺**，不是内容，所以写在代码里而不是 JSON ——
/// 免得有人改一行 JSON 就把 Morning Core 变成付费。
public enum EntitlementPolicy {

    public static func decide(routine: Routine, level: EntitlementLevel) -> AccessDecision {
        if level == .premium { return .allowed }
        // Morning Core 永久免费，无论 JSON 怎么标。
        if routine.type == .morning { return .allowed }
        return routine.isPremium ? .requiresPremium : .allowed
    }

    /// AR Mirror Guidance：免费用户可在 Morning Core 内体验（规格 §11 表格）。
    public static func decideARMirror(routine: Routine, level: EntitlementLevel) -> AccessDecision {
        if level == .premium { return .allowed }
        return routine.type == .morning ? .allowed : .requiresPremium
    }

    /// Watch & Breathe 在 MVP 阶段作为实验功能对免费用户开放。
    public static func decideWatchMode(routine: Routine, level: EntitlementLevel) -> AccessDecision {
        decide(routine: routine, level: level)
    }

    public static func decide(mode: PracticeMode, routine: Routine, level: EntitlementLevel) -> AccessDecision {
        switch mode {
        case .coach: return decide(routine: routine, level: level)
        case .arMirror: return decideARMirror(routine: routine, level: level)
        case .watch: return decideWatchMode(routine: routine, level: level)
        }
    }
}

/// 订阅商品配置。价格**不写死在代码里** ——
/// 规格 §20 明确付费价格属于 Owner 决策，工程侧只留可配置接口。
public struct SubscriptionProduct: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    /// 仅用于无法连接 StoreKit 时的占位展示；真实价格一律以 StoreKit 返回为准。
    public var placeholderPrice: String
    public var period: String
    public var isDefault: Bool

    public init(id: String, displayName: String, placeholderPrice: String, period: String, isDefault: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.placeholderPrice = placeholderPrice
        self.period = period
        self.isDefault = isDefault
    }
}

public protocol EntitlementService: AnyObject {
    var level: EntitlementLevel { get }
    var availableProducts: [SubscriptionProduct] { get }
    func refresh() async
    func purchase(productID: String) async throws
    func restore() async throws
    /// 变更通知。App 层订阅它刷新 UI。
    var onChange: ((EntitlementLevel) -> Void)? { get set }
}

public enum EntitlementError: Error {
    case productNotFound(String)
    case purchaseFailed(String)
    case notImplemented(String)
}

/// Mock 解锁状态的存储抽象。App 层用 UserDefaults 实现，测试用内存实现。
/// Core 不直接依赖 UserDefaults —— 它是平台 API。
public protocol EntitlementFlagStorage: AnyObject {
    func loadPremiumFlag() -> Bool
    func savePremiumFlag(_ value: Bool)
}

public final class InMemoryEntitlementFlagStorage: EntitlementFlagStorage {
    private var flag: Bool
    public init(initial: Bool = false) { flag = initial }
    public func loadPremiumFlag() -> Bool { flag }
    public func savePremiumFlag(_ value: Bool) { flag = value }
}

/// M1 使用的 Mock 实现 —— Owner 指令：「Premium 内容可以先 Mock Unlock」。
/// 状态持久化在调用方注入的存储里。
public final class MockEntitlementService: EntitlementService {

    private let storage: EntitlementFlagStorage
    public var onChange: ((EntitlementLevel) -> Void)?

    public private(set) var level: EntitlementLevel {
        didSet { if oldValue != level { onChange?(level) } }
    }

    public let availableProducts: [SubscriptionProduct]

    public init(
        storage: EntitlementFlagStorage,
        products: [SubscriptionProduct] = MockEntitlementService.defaultProducts
    ) {
        self.storage = storage
        self.availableProducts = products
        self.level = storage.loadPremiumFlag() ? .premium : .free
    }

    /// 占位价格取自规格 §11 的「工作价格 $4.99/月（待测试）」。
    /// 这是 Owner 待决策项，上线前必须替换为 StoreKit 真实价格。
    public static let defaultProducts: [SubscriptionProduct] = [
        SubscriptionProduct(
            id: "com.faceritual.premium.monthly",
            displayName: "Premium Monthly",
            placeholderPrice: "$4.99",
            period: "month",
            isDefault: true
        ),
        SubscriptionProduct(
            id: "com.faceritual.premium.yearly",
            displayName: "Premium Yearly",
            // Owner 2026-09-06 定：年费 29.99。
            // 用 .99 是因为 App Store 的价格档位历来是 X.99；
            // 若本意就是 29.90，改这里即可。
            placeholderPrice: "$29.99",
            period: "year"
        )
    ]

    public func refresh() async {
        level = storage.loadPremiumFlag() ? .premium : .free
    }

    public func purchase(productID: String) async throws {
        guard availableProducts.contains(where: { $0.id == productID }) else {
            throw EntitlementError.productNotFound(productID)
        }
        setMockUnlocked(true)
    }

    public func restore() async throws {
        await refresh()
    }

    /// 开发用开关，只在 Settings → Developer 暴露。
    public func setMockUnlocked(_ unlocked: Bool) {
        storage.savePremiumFlag(unlocked)
        level = unlocked ? .premium : .free
    }
}
