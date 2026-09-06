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
/// App Store 审核指南 3.1.2 要求 **Paywall 上必须有可点击的 Terms of Use 与 Privacy Policy**，
/// 缺任何一个都会被拒 —— 这不是可选项，是上架前置条件。
enum LegalLinks {

    /// 用户协议用 **Apple 的标准 EULA**。
    ///
    /// 不必自己写一份：绝大多数不做自定义条款的 App 都直接链这个，
    /// 合规、免费、不用请律师起草。
    /// 只有当你确实需要自定义条款（例如特殊的退款或责任约定）时，才换成自己的 URL。
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    /// ⚠️ 隐私政策**必须自己提供**，没有标准版可用。
    ///
    /// 草稿已写好并且是照代码实际行为写的：`site/privacy.html`。
    /// 发布方式见 `site/README.md`（GitHub Pages 免费即可），
    /// 拿到网址后填在这里。
    static let privacyPolicy: URL? = nil

    /// 上架前必须为 true。Debug 诊断页与 Paywall 会显示当前状态。
    static var isComplete: Bool {
        termsOfUse != nil && privacyPolicy != nil
    }
}
