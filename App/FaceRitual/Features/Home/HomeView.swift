import SwiftUI
import FaceRitualCore

/// 规格 §5.1 首页。
///
/// 设计约束（规格 §4「极简」）：
/// 打开 → 看到今天该做的那一件事 → START。没有问卷、没有内容墙、没有选择困难。
struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var path: NavigationPath

    @State private var paywallRoutine: Routine?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return (hour >= 5 && hour < 12) ? AppCopy.greetingMorning : AppCopy.greetingEvening
    }

    /// 主卡片**恒为 Morning Core**（规格 §5.1 就是这么写的）。
    ///
    /// 之前按时间切换成 Evening 是个真 bug：Evening 是付费的，而 Morning Core
    /// 又不在下面的次级列表里 —— 于是下午 5 点之后，免费用户看到的是一张锁着的
    /// 主卡片加一列锁着的 Quick Ritual，**根本进不去那个永久免费的核心 routine**。
    /// 是 CI 的闭环测试在 UTC 18:09 跑时撞出来的。
    ///
    /// 现在 Evening 挪到次级列表，晚上排在最前 —— 看得到、进得去，也不挡住免费入口。
    private var featuredRoutine: Routine? {
        environment.morningCore ?? environment.eveningCore
    }

    /// 次级入口：其余 Morning 原型 + Evening + 全部 Quick Rituals。
    ///
    /// 其余 Morning 原型排在最前：Sprint 3 §4 一次给出 A/B/C 三套 3 分钟版本，
    /// §7 要求同一批用户交叉体验后再选，所以另外两套必须点得到。
    /// 傍晚把 Evening 排到最前，保留「按时间给出合适建议」的意图，
    /// 但不再以牺牲免费入口为代价。
    private var secondaryRituals: [Routine] {
        var list: [Routine] = environment.alternateMorningRoutines
        if let evening = environment.eveningCore, evening.id != featuredRoutine?.id {
            list.append(evening)
        }
        list.append(contentsOf: environment.quickRituals)

        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 17 {
            // 白天把 Evening 放到最后，Quick Ritual 更相关。
            list = list.filter { $0.type != .evening } + list.filter { $0.type == .evening }
        }
        return list
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
            Text(AppCopy.homeTagline)
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
        let rituals = secondaryRituals
        if rituals.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppCopy.moreRituals)
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

    /// 进入 routine 详情。
    ///
    /// 用**导航推入**而不是 fullScreenCover。
    ///
    /// 之前是模态：首页 fullScreenCover → 详情，详情里再 fullScreenCover → 播放器。
    /// 两层嵌套的 cover 在外层入场动画还没结束时触发内层，UIKit 会以
    /// 「上一个转场还在进行」为由把内层丢掉 —— 用户点了「Coach」但什么也没发生。
    /// 手快的用户、开了辅助功能「减弱动态效果」的用户，以及 CI 上动画很慢的
    /// 模拟器都会撞到（2026-09-06 的 run 34035131613 就是这么挂的）。
    ///
    /// 改成推入之后全 App 只剩播放器这一层 cover，这类问题从根上没有了。
    /// `AppRoute.routineDetail` 本来就已经接好线，只是一直没人用。
    private func start(_ routine: Routine) {
        if environment.access(to: routine, mode: .coach) == .requiresPremium {
            paywallRoutine = routine
        } else {
            path.append(AppRoute.routineDetail(routine.id))
        }
    }
}
