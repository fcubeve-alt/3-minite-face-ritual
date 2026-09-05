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
            .navigationTitle(AppCopy.premium)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppCopy.close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppCopy.restore) {
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
            Text(AppCopy.morningIsFreeForever)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(AppCopy.premiumUnlocks)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// 与规格 §11 的表格一一对应，不多承诺一项。
    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow("checkmark.circle.fill", AppCopy.benefitMorningTitle, AppCopy.benefitMorningSubtitle, included: true)
            benefitRow("moon.stars.fill", AppCopy.benefitEveningTitle, AppCopy.benefitEveningSubtitle)
            benefitRow("sparkles", AppCopy.benefitQuickTitle, AppCopy.benefitQuickSubtitle)
            benefitRow("faceid", AppCopy.benefitARTitle, AppCopy.benefitARSubtitle)
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
            Text(AppCopy.pricePlaceholderNotice)
            Text(AppCopy.medicalDisclaimer)
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
                    // 原始错误进 analytics，不进用户界面。
                    errorMessage = AppCopy.purchaseFailed
                    isPurchasing = false
                }
            }
        }
    }
}
