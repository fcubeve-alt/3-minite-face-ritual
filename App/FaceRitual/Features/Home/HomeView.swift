import SwiftUI
import FaceRitualCore

/// 规格 §5.1 首页。
///
/// 设计约束（规格 §4「极简」）：
/// 打开 → 看到今天该做的那一件事 → START。没有问卷、没有内容墙、没有选择困难。
struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var path: NavigationPath

    @State private var activeRoutine: Routine?
    @State private var paywallRoutine: Routine?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 5 && hour < 12) ? AppCopy.greetingMorning : AppCopy.greetingEvening
    }

    /// 按本地时间决定主卡片放 Morning 还是 Evening。
    /// Evening Core 是 Premium，但主卡片仍然展示 —— 让用户看得到，而不是藏起来。
    private var featuredRoutine: Routine? {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 17, let evening = environment.eveningCore { return evening }
        return environment.morningCore ?? environment.eveningCore
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let routine = featuredRoutine {
                    featuredCard(routine)
                }
                quickRituals
                monthlySummary
                mockContentNotice
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(AppRoute.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(AppCopy.a11ySettings)
            }
        }
        .fullScreenCover(item: $activeRoutine) { routine in
            // 模态里需要自己的 NavigationStack，否则详情页的标题栏与关闭按钮无处安放。
            NavigationStack {
                RoutineDetailView(routine: routine, presentedModally: true)
            }
            .tint(Theme.accent)
        }
        .sheet(item: $paywallRoutine) { routine in
            PaywallView(source: "home_\(routine.id.rawValue)")
        }
        .task {
            environment.analytics.track(.homeViewed(greeting: greeting))
        }
    }

    // MARK: - 区块

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Follow the coach. Mirror on your face. Done.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func featuredCard(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(routine.formattedDuration) · \(routine.steps.count) moves")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if routine.reviewStatus.isPublishable == false {
                    MockContentBadge(compact: true)
                }
            }

            if routine.usesARGuidance {
                Label(AppCopy.arGuidanceAvailable, systemImage: "faceid")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            }

            Button(AppCopy.start) {
                start(routine)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier(A11yID.homeStart)
        }
        .padding(20)
        .cardBackground(elevated: true)
    }

    @ViewBuilder
    private var quickRituals: some View {
        let rituals = environment.quickRituals
        if rituals.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppCopy.quickRituals)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                ForEach(rituals) { routine in
                    Button {
                        start(routine)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(routine.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(routine.formattedDuration)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if environment.access(to: routine, mode: .coach) == .requiresPremium {
                                Image(systemName: "lock.fill")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(16)
                        .cardBackground()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 规格 §12：按月展示次数/分钟数，不制造断签焦虑。
    private var monthlySummary: some View {
        let stats = environment.currentMonthStats()
        return Button {
            path.append(AppRoute.history)
        } label: {
            HStack(spacing: 20) {
                statCell(value: "\(stats.sessionCount)", label: AppCopy.statRituals)
                statCell(value: "\(Int(stats.totalMinutes.rounded()))", label: AppCopy.statMinutes)
                statCell(value: "\(stats.activeDays)", label: AppCopy.statDays)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(18)
            .cardBackground()
        }
        .buttonStyle(.plain)
        // 合成一条：否则会被念成「3、rituals、9、minutes、2、days、按钮」。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppCopy.a11yMonthlySummary(
                rituals: stats.sessionCount,
                minutes: Int(stats.totalMinutes.rounded()),
                days: stats.activeDays
            )
        )
        .accessibilityHint(AppCopy.a11yOpensHistory)
        .accessibilityIdentifier(A11yID.homeMonthlySummary)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var mockContentNotice: some View {
        if environment.content.containsUnreviewedContent {
            VStack(alignment: .leading, spacing: 6) {
                MockContentBadge()
                Text(AppCopy.mockContentNotice)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .cardBackground()
        }
    }

    // MARK: - 动作

    private func start(_ routine: Routine) {
        if environment.access(to: routine, mode: .coach) == .requiresPremium {
            paywallRoutine = routine
        } else {
            activeRoutine = routine
        }
    }
}
