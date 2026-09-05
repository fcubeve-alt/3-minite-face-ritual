import SwiftUI
import FaceRitualCore

/// About & Safety。
///
/// 存在的理由：免责声明缩成页脚一行小字，既没人会读，也保护不了任何人。
/// 规格 §19 把「安全审查与免责声明」列为 Owner 待办 ——
/// 这个页面是那份内容的落点，Owner 与法务改 `AppCopy` 即可，不必碰视图代码。
struct SafetyView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(AppCopy.safetyAndDisclaimerBody)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if environment.content.containsUnreviewedContent {
                    mockNotice
                }

                legalLinks
                versionFooter
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle(AppCopy.safetyScreenTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// M1 期间额外强调一次：这里的动作还不是专业内容。
    private var mockNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            MockContentBadge()
            Text(AppCopy.mockContentNotice)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }

    @ViewBuilder
    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let terms = LegalLinks.termsOfUse {
                Link(AppCopy.termsOfUse, destination: terms)
            }
            if let privacy = LegalLinks.privacyPolicy {
                Link(AppCopy.privacyPolicy, destination: privacy)
            }
            if LegalLinks.isComplete == false {
                // 只在开发构建里提醒，别把内部待办摆给用户看。
                #if DEBUG
                Text("⚠️ Terms / Privacy URL 尚未提供（规格 §19 Owner 待办）")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                #endif
            }
        }
        .font(.callout)
    }

    private var versionFooter: some View {
        Text("Content \(environment.content.meta.contentVersion)")
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// 法务链接。
///
/// ⚠️ 两个 URL 都是 Owner 待提供项（规格 §19）。
/// App Store 审核指南 3.1.2 要求 **Paywall 上必须有可点击的 Terms of Use 与 Privacy Policy**，
/// 缺任何一个都会被拒 —— 所以这不是可选项，是上架前置条件。
enum LegalLinks {
    static let termsOfUse: URL? = nil
    static let privacyPolicy: URL? = nil

    /// 上架前必须为 true。Debug 诊断页会显示当前状态。
    static var isComplete: Bool {
        termsOfUse != nil && privacyPolicy != nil
    }
}
