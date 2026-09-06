import Foundation

public struct ContentValidationIssue: Sendable, Hashable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        case error
        case warning
    }

    public let severity: Severity
    public let path: String
    public let message: String

    public init(severity: Severity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }

    public var description: String { "[\(severity.rawValue)] \(path): \(message)" }
}

/// 内容包完整性校验。
///
/// 存在的理由：动作内容全部来自可替换 JSON，代码里没有任何字面量。
/// 一旦 JSON 写错（引用了不存在的 anchor、时长对不上、premium 标记冲突），
/// 必须在启动时**大声**报出来，而不是在用户脸上画到一半才崩。
public struct ContentValidator: Sendable {

    /// Morning Core 目标时长（规格 §5.2「约 3 分钟」），偏差超过容差给 warning。
    public var morningTargetSeconds: Double
    public var eveningTargetSeconds: Double
    public var durationToleranceSeconds: Double

    public init(
        morningTargetSeconds: Double = 180,
        eveningTargetSeconds: Double = 300,
        durationToleranceSeconds: Double = 30
    ) {
        self.morningTargetSeconds = morningTargetSeconds
        self.eveningTargetSeconds = eveningTargetSeconds
        self.durationToleranceSeconds = durationToleranceSeconds
    }

    public func validate(_ bundle: ContentBundle) -> [ContentValidationIssue] {
        var issues: [ContentValidationIssue] = []

        validateRoutineIdentity(bundle, into: &issues)
        validateFreemiumPolicy(bundle, into: &issues)
        validateMoveLibrary(bundle, into: &issues)

        for routine in bundle.routines {
            validateRoutine(routine, bundle: bundle, into: &issues)
        }
        for anchor in bundle.anchors.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            validateAnchor(anchor, into: &issues)
        }

        if bundle.containsUnreviewedContent {
            issues.append(
                ContentValidationIssue(
                    severity: .warning,
                    path: "bundle",
                    message: "内容包含未经专业审核的条目（mock_unreviewed / draft）。发布前必须由 Owner + 专业人员替换。"
                )
            )
        }
        return issues
    }

    // MARK: - 分项

    private func validateRoutineIdentity(_ bundle: ContentBundle, into issues: inout [ContentValidationIssue]) {
        var seen: Set<RoutineID> = []
        for routine in bundle.routines {
            if seen.insert(routine.id).inserted == false {
                issues.append(.init(severity: .error, path: "routines.\(routine.id)", message: "routine id 重复"))
            }
        }
        if bundle.morningCore == nil {
            issues.append(
                .init(
                    severity: .error,
                    path: "routines",
                    message: "缺少免费的 Morning Core（type=morning 且 isPremium=false）。规格 §11 要求它永久免费。"
                )
            )
        }
    }

    private func validateFreemiumPolicy(_ bundle: ContentBundle, into issues: inout [ContentValidationIssue]) {
        for routine in bundle.routines where routine.type == .morning && routine.isPremium {
            issues.append(
                .init(
                    severity: .error,
                    path: "routines.\(routine.id)",
                    message: "Morning routine 不得标记为 premium（规格 §11）。"
                )
            )
        }
    }

    private func validateRoutine(_ routine: Routine, bundle: ContentBundle, into issues: inout [ContentValidationIssue]) {
        let path = "routines.\(routine.id)"

        if routine.steps.isEmpty {
            issues.append(.init(severity: .error, path: path, message: "routine 没有任何 step"))
            return
        }

        var seenSteps: Set<RoutineStepID> = []
        for (index, step) in routine.steps.enumerated() {
            let stepPath = "\(path).steps[\(index)]:\(step.id)"
            if seenSteps.insert(step.id).inserted == false {
                issues.append(.init(severity: .error, path: stepPath, message: "step id 在同一 routine 内重复"))
            }
            if step.durationSeconds <= 0 {
                issues.append(.init(severity: .error, path: stepPath, message: "durationSeconds 必须 > 0"))
            }
            if step.durationSeconds > 90 {
                issues.append(.init(severity: .warning, path: stepPath, message: "单个动作超过 90 秒，与规格 §4「每个动作短」不符"))
            }
            if step.shortCue.isEmpty {
                issues.append(.init(severity: .warning, path: stepPath, message: "缺少 shortCue，屏幕上会没有文字提示"))
            }
            validateMovement(step.movement, bundle: bundle, path: stepPath, into: &issues)
            validateStepAgainstMoveLibrary(step, routine: routine, bundle: bundle, path: stepPath, into: &issues)
        }

        let target: Double?
        switch routine.type {
        case .morning: target = morningTargetSeconds
        case .evening: target = eveningTargetSeconds
        case .quick: target = nil
        }
        if let target, abs(routine.totalDurationSeconds - target) > durationToleranceSeconds {
            issues.append(
                .init(
                    severity: .warning,
                    path: path,
                    message: "总时长 \(Int(routine.totalDurationSeconds))s 偏离目标 \(Int(target))s 超过 \(Int(durationToleranceSeconds))s"
                )
            )
        }
    }

    private func validateMovement(
        _ movement: MovementSpec,
        bundle: ContentBundle,
        path: String,
        into issues: inout [ContentValidationIssue]
    ) {
        func requireAnchor(_ id: FaceAnchorID?, label: String) {
            guard let id else { return }
            if bundle.anchors[id] == nil {
                issues.append(.init(severity: .error, path: path, message: "\(label) 引用了不存在的 anchor: \(id)"))
            }
        }
        requireAnchor(movement.startAnchorID, label: "startAnchor")
        requireAnchor(movement.endAnchorID, label: "endAnchor")

        switch movement.pathType {
        case .line, .curve, .arc:
            if movement.startAnchorID == nil || movement.endAnchorID == nil {
                issues.append(
                    .init(
                        severity: .error,
                        path: path,
                        message: "pathType=\(movement.pathType.rawValue) 需要同时提供 startAnchor 与 endAnchor"
                    )
                )
            }
        case .circle:
            if movement.startAnchorID == nil {
                issues.append(.init(severity: .error, path: path, message: "pathType=circle 需要 startAnchor 作为圆心"))
            }
            if (movement.pathGeometry.radius ?? 0) <= 0 {
                issues.append(.init(severity: .warning, path: path, message: "circle 未指定 radius，将使用默认 0.35 瞳距"))
            }
        case .press, .hold:
            if movement.startAnchorID == nil {
                issues.append(.init(severity: .error, path: path, message: "pathType=\(movement.pathType.rawValue) 需要 startAnchor"))
            }
        case .expression:
            // 表情肌动作没有手部接触，本来就没有路径。
            // 但如果作者填了 anchor，说明多半是选错了 pathType，要提醒。
            if movement.startAnchorID != nil || movement.endAnchorID != nil {
                issues.append(
                    .init(
                        severity: .warning,
                        path: path,
                        message: "pathType=expression 不应有 start/endAnchor（表情动作没有手部接触点）；要高亮区域请用 focusAnchors"
                    )
                )
            }
            if movement.gestureHint != .none {
                issues.append(
                    .init(severity: .warning, path: path, message: "pathType=expression 不应有 gestureHint —— 手不参与")
                )
            }
        case .tap:
            if movement.focusAnchorIDs.isEmpty && movement.startAnchorID == nil {
                issues.append(
                    .init(
                        severity: .error,
                        path: path,
                        message: "pathType=tap 需要 focusAnchors（跨区域轻拍）或 startAnchor（单点轻拍），否则 AR 无处可画"
                    )
                )
            }
        }

        for anchorID in movement.focusAnchorIDs {
            requireAnchor(anchorID, label: "focusAnchors")
        }

        if movement.repetitions < 1 {
            issues.append(.init(severity: .error, path: path, message: "repetitions 必须 >= 1"))
        }
        // 规格 §10：MVP 阶段不允许任何动作声称支持实时纠错。
        if movement.trackingSupport == .observableCorrectionExperimental {
            issues.append(
                .init(
                    severity: .warning,
                    path: path,
                    message: "trackingSupport=observableCorrectionExperimental 需逐个动作验证达标后才可启用（规格 §10）"
                )
            )
        }
    }

    /// 动作库自身的约束。
    private func validateMoveLibrary(_ bundle: ContentBundle, into issues: inout [ContentValidationIssue]) {
        guard bundle.moves.isEmpty == false else {
            issues.append(
                .init(severity: .error, path: "moves", message: "动作库为空。routine 只是时间线，没有动作库就拼不出任何 step。")
            )
            return
        }

        for move in bundle.sortedMoves {
            let path = "moves.\(move.id)"
            if move.defaultDurationSeconds <= 0 {
                issues.append(.init(severity: .error, path: path, message: "defaultDurationSeconds 必须 > 0"))
            }
            if move.allowedRoutineTypes.isEmpty {
                issues.append(
                    .init(severity: .error, path: path, message: "allowedRoutineTypes 为空，这个动作永远不可能被任何 routine 使用")
                )
            }
            // Sprint 3 §9：Gua Sha / Roller 不得成为免费核心操的必要条件。
            if move.requiresTool.isTool, move.allowedRoutineTypes.contains(.morning) {
                issues.append(
                    .init(
                        severity: .error,
                        path: path,
                        message: "需要工具的动作（\(move.requiresTool.rawValue)）不得允许出现在 morning routine —— 免费核心操不能依赖工具（Sprint 3 §9）"
                    )
                )
            }
            // 安全字段是翻译，专家审的是原文；缺原文就没法审。
            if move.safetyNote != nil, (move.source.stopSignalsZh ?? "").isEmpty {
                issues.append(
                    .init(
                        severity: .warning,
                        path: path,
                        message: "有英文 safetyNote 但缺 source.stopSignalsZh，Expert Gate 无从对照原文复核"
                    )
                )
            }
        }

        // 库里有、但没有任何 routine 用到的动作。不是错误 —— Sprint 3 §11 说
        // Evening 与 Quick Ritual 尚未设计，剩余动作正是留给它们的。
        var used: Set<GoldMoveID> = []
        for routine in bundle.routines {
            for step in routine.steps {
                if let moveID = step.sourceMoveID { used.insert(moveID) }
            }
        }
        let unused = bundle.sortedMoves.filter { used.contains($0.id) == false }
        if unused.isEmpty == false {
            issues.append(
                .init(
                    severity: .warning,
                    path: "moves",
                    message: "\(unused.count) 个动作尚未被任何 routine 使用: \(unused.map { $0.id.rawValue }.joined(separator: ", "))"
                )
            )
        }
    }

    /// 展开后的 step 是否违反了它来源动作声明的约束。
    private func validateStepAgainstMoveLibrary(
        _ step: RoutineStep,
        routine: Routine,
        bundle: ContentBundle,
        path: String,
        into issues: inout [ContentValidationIssue]
    ) {
        guard let moveID = step.sourceMoveID else { return }
        guard let move = bundle.moves[moveID] else {
            issues.append(.init(severity: .error, path: path, message: "step 来源动作 \(moveID) 不在动作库里"))
            return
        }
        if move.allowedRoutineTypes.contains(routine.type) == false {
            issues.append(
                .init(
                    severity: .error,
                    path: path,
                    message: "动作 \(moveID) 声明只允许用于 \(move.allowedRoutineTypes.map { $0.rawValue }.joined(separator: "/"))，却出现在 \(routine.type.rawValue) routine 里"
                )
            )
        }
        if move.requiresTool.isTool, routine.type == .morning {
            issues.append(
                .init(
                    severity: .error,
                    path: path,
                    message: "morning routine 用到了需要工具的动作 \(moveID)（\(move.requiresTool.rawValue)）—— 免费核心操不能依赖工具（Sprint 3 §9）"
                )
            )
        }
    }

    private func validateAnchor(_ anchor: FaceAnchor, into issues: inout [ContentValidationIssue]) {
        let path = "anchors.\(anchor.id)"
        if anchor.toleranceRadius <= 0 {
            issues.append(.init(severity: .error, path: path, message: "toleranceRadius 必须 > 0"))
        }
        if anchor.toleranceRadius > 0.6 {
            issues.append(.init(severity: .warning, path: path, message: "toleranceRadius 超过 0.6 瞳距，容差圈会大到失去指示意义"))
        }
        if anchor.confidenceThreshold < 0 || anchor.confidenceThreshold > 1 {
            issues.append(.init(severity: .error, path: path, message: "confidenceThreshold 必须在 0…1"))
        }
        if anchor.rule.referencedLandmarks.isEmpty {
            issues.append(.init(severity: .error, path: path, message: "geometryRule 没有引用任何 landmark"))
        }
    }
}
