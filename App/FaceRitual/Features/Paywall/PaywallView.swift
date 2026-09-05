import SwiftUI
import FaceRitualCore

/// Paywall 占位。
///
/// **价格不写死在代码里**（规格 §20：付费价格属于 Owner 决策）。
/// M1 显示的是配置里的占位值，并明确标注「待定」；
/// 接上 StoreKit 后一律显示 `product.displayPrice`。
struct PaywallView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let source: String
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    benefits
                    products
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                    disclaimer
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") {
                        Task { try? await environment.entitlement.restore() }
                    }
                }
            }
        }
        .task {
            environment.analytics.track(.paywallViewed(source: source))
            await environment.entitlement.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Morning Ritual 永久免费")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Premium 解锁 Evening Ritual 与全部 Quick Rituals。")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// 与规格 §11 的表格一一对应，不多承诺一项。
    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow("checkmark.circle.fill", "Morning Core", "免费用户也永久包含", included: true)
            benefitRow("moon.stars.fill", "Evening Ritual", "约 5 分钟的舒缓 routine")
            benefitRow("sparkles", "全部 Quick Rituals", "De-Puff · Tired Eyes 等")
            benefitRow("faceid", "全部 routine 的 AR Mirror", "免费用户可在 Morning Core 内体验")
        }
    }

    private func benefitRow(_ icon: String, _ title: String, _ subtitle: String, included: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .frame(width: 26)
                .foregroundStyle(included ? Theme.textSecondary : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var products: some View {
        VStack(spacing: 10) {
            ForEach(environment.entitlement.availableProducts) { product in
                Button {
                    purchase(product)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName)
                                .font(.system(size: 16, weight: .medium))
                            Text("per \(product.period)")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text(product.placeholderPrice)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(16)
                    .cardBackground(elevated: product.isDefault)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)
            }
        }
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("价格为待测试的占位值，最终定价、年费方案与订阅条款上线前确认。")
            Text("本 App 提供日常护理引导，不构成医学诊断、治疗建议或疗效承诺。")
        }
        .font(.caption)
        .foregroundStyle(Theme.textTertiary)
    }

    private func purchase(_ product: SubscriptionProduct) {
        isPurchasing = true
        errorMessage = nil
        environment.analytics.track(.purchaseAttempted(productID: product.id))
        Task {
            do {
                try await environment.entitlement.purchase(productID: product.id)
                environment.analytics.track(.purchaseResult(productID: product.id, success: true))
                await MainActor.run { dismiss() }
            } catch {
                environment.analytics.track(.purchaseResult(productID: product.id, success: false))
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isPurchasing = false
                }
            }
        }
    }
}
