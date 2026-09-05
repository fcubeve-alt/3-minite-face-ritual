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
            providerSection
            landmarkCoverageSection
            anchorSection
            contentSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var toolsSection: some View {
        Section {
            NavigationLink("ARKit 顶点标定") {
                ARKitCalibrationView()
            }
        } header: {
            Text("Tools")
        } footer: {
            Text("ARKit 的 1220 个顶点没有官方语义编号，需要在真机上手工标定一次。标定完成后 ARKit provider 才会变为可用。")
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        Section("Face Alignment Providers") {
            ForEach(FaceAlignmentProviderKind.allCases) { kind in
                let provider = FaceAlignmentProviderFactory.make(kind)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(kind.displayName)
                            .font(.system(size: 15, weight: .medium))
                        Spacer()
                        Text(provider.isAvailable ? "可用" : "不可用")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(provider.isAvailable ? Theme.accent : Theme.warning)
                    }
                    Text(provider.descriptor.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if let reason = provider.unavailableReason {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                    }
                    HStack(spacing: 10) {
                        tag("landmarks \(provider.descriptor.supportedLandmarks.count)")
                        if provider.descriptor.requiresTrueDepth { tag("TrueDepth") }
                        if provider.descriptor.providesHeadPose { tag("head pose") }
                        // 目前没有任何实现声称能做遮挡判断 —— 这是规格 §10 的边界。
                        tag(provider.descriptor.providesOcclusionEstimate ? "occlusion" : "no occlusion")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// 所选 provider 是否覆盖内容需要的全部 landmark。
    /// 缺一个都会让某个 anchor 直接解析失败 —— 与其在脸上少画一个点，不如在这里先报出来。
    private var landmarkCoverageSection: some View {
        let provider = FaceAlignmentProviderFactory.make(environment.settings.preferredProviderKind)
        let required = environment.requiredLandmarks
        let missing = required.subtracting(provider.descriptor.supportedLandmarks)

        return Section("Landmark Coverage") {
            HStack {
                Text("内容需要")
                Spacer()
                Text("\(required.count) 个语义 landmark")
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Text("当前 provider 覆盖")
                Spacer()
                Text(missing.isEmpty ? "全部覆盖" : "缺 \(missing.count) 个")
                    .foregroundStyle(missing.isEmpty ? Theme.accent : Theme.warning)
            }
            if missing.isEmpty == false {
                Text(missing.map(\.rawValue).sorted().joined(separator: ", "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.warning)
            }
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

    private var contentSection: some View {
        Section("Content (\(environment.content.meta.contentVersion))") {
            HStack {
                Text("Routines")
                Spacer()
                Text("\(environment.content.routines.count)")
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
