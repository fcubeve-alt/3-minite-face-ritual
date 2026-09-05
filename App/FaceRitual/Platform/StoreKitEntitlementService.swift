import Foundation
import StoreKit
import FaceRitualCore

/// StoreKit 2 的订阅实现骨架。
///
/// **M1 不启用它**，默认走 `MockEntitlementService`（Owner 指令：Premium 先 Mock Unlock）。
/// 这里先把结构搭好，是为了让「订阅架构」这一项在 M1 就成立：
/// 切换实现只需改 `AppEnvironment` 里的一行，UI 与权限判断完全不动。
///
/// 上线前仍需 Owner 决策（规格 §19）：
/// 最终价格、年费方案、订阅条款、隐私政策、App Store Connect 商品配置。
/// 这些属于产品与法务决策，工程侧不代为决定。
final class StoreKitEntitlementService: EntitlementService {

    private(set) var level: EntitlementLevel = .free {
        didSet { if oldValue != level { onChange?(level) } }
    }

    var onChange: ((EntitlementLevel) -> Void)?
    private(set) var availableProducts: [SubscriptionProduct] = []

    private var storeProducts: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    /// 商品 ID 来自配置而不是硬编码字面量散落各处。
    private let productIdentifiers: [String]

    init(productIdentifiers: [String] = MockEntitlementService.defaultProducts.map(\.id)) {
        self.productIdentifiers = productIdentifiers
        listenForTransactions()
    }

    deinit { updatesTask?.cancel() }

    func refresh() async {
        await loadProducts()
        await updateEntitlement()
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: productIdentifiers)
            storeProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            availableProducts = products.map { product in
                SubscriptionProduct(
                    id: product.id,
                    displayName: product.displayName,
                    // 真实价格一律以 StoreKit 返回为准，不使用任何占位数字。
                    placeholderPrice: product.displayPrice,
                    period: product.subscription?.subscriptionPeriod.unit.localizedDescription ?? "",
                    isDefault: product.id == productIdentifiers.first
                )
            }
        } catch {
            // 取不到商品时保持空列表；Paywall 会显示「暂时无法加载」而不是假价格。
            availableProducts = []
        }
    }

    private func updateEntitlement() async {
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            if productIdentifiers.contains(transaction.productID), transaction.revocationDate == nil {
                level = .premium
                return
            }
        }
        level = .free
    }

    func purchase(productID: String) async throws {
        guard let product = storeProducts[productID] else {
            throw EntitlementError.productNotFound(productID)
        }
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw EntitlementError.purchaseFailed("交易校验失败")
            }
            await transaction.finish()
            await updateEntitlement()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await updateEntitlement()
    }

    /// 订阅可能在 App 之外发生变化（续订、退款、家庭共享），必须持续监听。
    private func listenForTransactions() {
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case let .verified(transaction) = result else { continue }
                await transaction.finish()
                await self?.updateEntitlement()
            }
        }
    }
}

private extension Product.SubscriptionPeriod.Unit {
    var localizedDescription: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return ""
        }
    }
}
