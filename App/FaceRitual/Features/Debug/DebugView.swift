import SwiftUI
import FaceRitualCore

/// 诊断页。POC 阶段的主要工具。
///
/// 回答三个问题：
/// 1. 当前设备上每个 provider 可不可用？不可用的原因是什么？
/// 2. 所选 provider 能否覆盖内容里用到的全部 landmark？
/// 3. 内容包有没有校验问题？
struct DebugView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        List {
            toolsSection
            anchorSection
            moveLibrarySection
            contentSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var toolsSection: some View {
        Section {
            videoAvailabilityRow
            HStack {
                Text("Terms / Privacy 链接")
                Spacer()
                Text(LegalLinks.isComplete ? "已配置" : "缺失（上架会被拒）")
                    .foregroundStyle(LegalLinks.isComplete ? Theme.accent : Theme.warning)
            }
        } header: {
            Text("Tools")
        } footer: {
            Text("示范视频放在 App/FaceRitual/Resources/CoachVideos/，命名与交付要求见 docs/COACH_VIDEO_SPEC.md。缺素材时播放器会回落到示意动画，不影响使用。")
        }
    }

    /// 示范视频素材进度。
    ///
    /// 缺素材不是错误 —— 播放器会回落到示意动画。但「缺了多少」得看得见，
    /// 否则很容易以为素材已经齐了，而实际上文件名写错了 App 根本没找到。
    private var videoAvailabilityRow: some View {
        let steps = environment.content.routines.flatMap(\.steps)
        let status = LoopingVideoPlayer.availability(for: steps)
        return HStack {
            Text("示范视频素材")
            Spacer()
            Text("\(status.present) / \(status.total)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(status.present == status.total ? Theme.accent : Theme.warning)
        }
    }

    private var anchorSection: some View {
        Section("Face Anchors (\(environment.content.anchors.count))") {
            ForEach(environment.content.anchors.values.sorted { $0.id.rawValue < $1.id.rawValue }, id: \.id) { anchor in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(anchor.id.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Spacer()
                        if anchor.reviewStatus.isPublishable == false {
                            MockContentBadge(compact: true)
                        }
                    }
                    Text(anchor.name)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text("landmarks: " + anchor.rule.referencedLandmarks.map(\.rawValue).sorted().joined(separator: ", "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    Text(String(
                        format: "tolerance %.2f · yaw≤%.0f° pitch≤%.0f° roll≤%.0f°",
                        anchor.toleranceRadius,
                        anchor.poseConstraints.maxYawDegrees,
                        anchor.poseConstraints.maxPitchDegrees,
                        anchor.poseConstraints.maxRollDegrees
                    ))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 3)
            }
        }
    }

    /// Gold Motion Library。
    ///
    /// 这一屏是 Expert Gate 的工作面：每个动作旁边直接显示中文原文来源、
    /// 力度、工具要求与证据等级 —— 专家审的是原文，用户看的是英文，
    /// 两份并存才审得动。
    private var moveLibrarySection: some View {
        let moves = environment.allMoves
        let pending = environment.movesAwaitingExpertGate.count
        return Section("Gold Motion Library (\(moves.count))") {
            HStack {
                Text("待专家审核")
                Spacer()
                Text("\(pending) / \(moves.count)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(pending > 0 ? Theme.warning : Theme.accent)
            }
            ForEach(moves) { move in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(move.id.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Text(move.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if move.reviewStatus.isPublishable == false {
                            MockContentBadge(compact: true)
                        }
                    }
                    Text(move.source.titleZh)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 5) {
                        tag(move.region.rawValue)
                        tag(move.movement.pathType.rawValue)
                        tag(move.intensity.rawValue)
                        if move.requiresTool.isTool { tag(move.requiresTool.rawValue) }
                    }
                    Text("\(move.source.documentRef) · \(move.evidenceLevel.rawValue) · "
                         + move.allowedRoutineTypes.map(\.rawValue).joined(separator: "/"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    if let stop = move.source.stopSignalsZh {
                        Text("停止信号：" + stop)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.warning)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var contentSection: some View {
        Section("Content (\(environment.content.meta.contentVersion))") {
            HStack {
                Text("Routines")
                Spacer()
                Text("\(environment.content.routines.count)")
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Text("Schema")
                Spacer()
                Text("v\(environment.content.meta.schemaVersion)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Text("审核状态")
                Spacer()
                Text(environment.content.meta.reviewStatus.rawValue)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(environment.content.meta.reviewStatus.isPublishable ? Theme.accent : Theme.warning)
            }
            if environment.contentIssues.isEmpty {
                Text("无校验问题")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(Array(environment.contentIssues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(issue.severity.rawValue)] \(issue.path)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(issue.severity == .error ? Theme.warning : Theme.textSecondary)
                        Text(issue.message)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.textTertiary.opacity(0.18), in: Capsule())
            .foregroundStyle(Theme.textSecondary)
    }
}
