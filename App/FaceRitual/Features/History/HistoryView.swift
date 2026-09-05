import SwiftUI
import FaceRitualCore

/// 练习记录 + 月度分钟数（规格 §12）。
///
/// 刻意**不做**日历打卡格、不做断签警告、不做连胜特效。
/// 目标是降低执行摩擦，不是强游戏化。
struct HistoryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var sessions: [PracticeSession] = []

    private var stats: MonthlyStats { environment.currentMonthStats() }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · HH:mm"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard

                if sessions.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(sessions) { session in
                            row(session)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            sessions = environment.practiceStore.recentSessions(limit: 60)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This month")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                cell("\(stats.sessionCount)", "rituals")
                cell("\(Int(stats.totalMinutes.rounded()))", "minutes")
                cell("\(stats.activeDays)", "active days")
                // 连续天数只做正向展示；断了也不提示、不惩罚。
                cell("\(stats.currentStreakDays)", "day streak")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ session: PracticeSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.mode.iconName)
                .font(.footnote)
                .frame(width: 22)
                .foregroundStyle(session.completed ? Theme.accent : Theme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.routineTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(HistoryView.dateFormatter.string(from: session.startedAt))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(session.secondsCompleted / 60))m \(Int(session.secondsCompleted) % 60)s")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                if session.completed == false {
                    Text("partial")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(14)
        .cardBackground()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("还没有记录")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Text("完成一次 ritual 后会出现在这里。")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
