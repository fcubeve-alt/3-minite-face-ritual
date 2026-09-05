import SwiftUI
import FaceRitualCore

/// 完成页。闭环的最后一步：练习记录已经保存。
///
/// 语气刻意平和（规格 §12）：不夸奖、不施压、不制造断签焦虑。
struct DoneView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let session: PracticeSession
    let routine: Routine

    private var stats: MonthlyStats { environment.currentMonthStats() }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                Image(systemName: session.completed ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 56))
                    .foregroundStyle(session.completed ? Theme.accent : Theme.textSecondary)

                VStack(spacing: 8) {
                    Text(session.completed ? AppCopy.doneTitle : AppCopy.savedTitle)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier(A11yID.doneTitle)
                    Text(summaryLine)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                monthCard

                if session.arMirrorUsed {
                    arSummary
                }

                Spacer()

                Button(AppCopy.backToHome) { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier(A11yID.doneBackToHome)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
    }

    private var summaryLine: String {
        let minutes = Int(session.secondsCompleted / 60)
        let seconds = Int(session.secondsCompleted) % 60
        let duration = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        return "\(routine.title) · \(duration) · \(session.mode.displayName)"
    }

    private var monthCard: some View {
        HStack(spacing: 0) {
            monthCell(value: "\(stats.sessionCount)", label: AppCopy.thisMonthShort)
            divider
            monthCell(value: "\(Int(stats.totalMinutes.rounded()))", label: AppCopy.statMinutes)
            divider
            monthCell(value: "\(stats.activeDays)", label: AppCopy.statDays)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 32)
    }

    private func monthCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// AR 会话的客观读数。POC 阶段直接抄进报告，正式上线时可隐藏。
    private var arSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AR SESSION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 16) {
                if let provider = session.faceProviderID {
                    Text("provider \(provider)")
                }
                if let lock = session.timeToFirstFaceLock {
                    Text(String(format: "first lock %.1fs", lock))
                }
                Text("lock loss \(session.faceLockLossCount)")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }
}
