import XCTest
@testable import FaceRitualCore

/// 针对**真实内容包**（而不是 fixture）的测试 ——
/// 避免出现「测试用一份、线上用另一份」的漂移。
final class ContentBundleTests: XCTestCase {

    private func loadBundle() throws -> ContentBundle {
        try BundledContent.makeRepository(failOnValidationError: true).load()
    }

    func testShippedContentHasNoValidationErrors() throws {
        let repository = try BundledContent.makeRepository(failOnValidationError: false)
        _ = try repository.load()
        let errors = repository.validationIssues().filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "内容包存在 error 级问题:\n" + errors.map(\.description).joined(separator: "\n"))
    }

    func testMorningCoreIsFreeAndThreeMinutes() throws {
        let morning = try XCTUnwrap(try loadBundle().morningCore)
        XCTAssertFalse(morning.isPremium, "规格 §11：Morning Core 永久免费")
        XCTAssertEqual(morning.totalDurationSeconds, 180, accuracy: 0.001)
        XCTAssertEqual(morning.formattedDuration, "3:00")
    }

    /// Sprint 3 §4 给出三套 Morning 原型，每套都必须正好 3 分钟。
    /// 三套并存是文档的要求（§7「同一批用户交叉体验」），不是重复内容。
    func testAllMorningPrototypesAreExactlyThreeMinutes() throws {
        let morningRoutines = try loadBundle().routines(ofType: .morning)
        XCTAssertEqual(morningRoutines.count, 3, "Sprint 3 §4 定义了 Prototype A / B / C")
        for routine in morningRoutines {
            XCTAssertEqual(
                routine.totalDurationSeconds, 180, accuracy: 0.001,
                "\(routine.id) 总时长应为 180s，实际 \(routine.totalDurationSeconds)"
            )
            XCTAssertFalse(routine.isPremium, "\(routine.id)：Morning 一律免费（规格 §11）")
        }
    }

    /// 动作是资产、routine 只是时间线（文档二 §9）。
    /// Prototype A 里 GM-11 与 GM-18 各出现两次，展开后必须是两个不同的 step，
    /// 但指向同一个动作 —— 否则要么 step id 冲突，要么动作定义被复制了两份。
    func testRepeatedMoveInOneRoutineBecomesDistinctSteps() throws {
        let bundle = try loadBundle()
        let routine = try XCTUnwrap(bundle.routine(id: "morning_prototype_a"))
        let repeated = routine.steps.filter { $0.sourceMoveID?.rawValue == "GM-11" }
        XCTAssertEqual(repeated.count, 2, "Prototype A 的 GM-11 出现两次")
        XCTAssertNotEqual(repeated[0].id, repeated[1].id, "同一动作重复出现时 step id 必须不同")
        XCTAssertEqual(repeated[0].title, repeated[1].title, "两处应引用同一个动作定义")
        XCTAssertEqual(repeated[0].movement, repeated[1].movement)
    }

    /// 每个 step 都必须能追回动作库 —— 校验器靠它检查工具/适用范围约束。
    func testEveryStepTracesBackToAGoldMove() throws {
        let bundle = try loadBundle()
        XCTAssertFalse(bundle.moves.isEmpty, "动作库不应为空")
        for routine in bundle.routines {
            for step in routine.steps {
                let moveID = try XCTUnwrap(step.sourceMoveID, "\(routine.id)/\(step.id) 缺少来源动作")
                XCTAssertNotNil(bundle.moves[moveID], "\(moveID) 不在动作库里")
            }
        }
    }

    /// Sprint 3 §9：Gua Sha / Roller 不得成为免费核心操的必要条件。
    func testNoMorningRoutineRequiresATool() throws {
        let bundle = try loadBundle()
        for routine in bundle.routines(ofType: .morning) {
            for step in routine.steps {
                guard let moveID = step.sourceMoveID, let move = bundle.moves[moveID] else { continue }
                XCTAssertFalse(
                    move.requiresTool.isTool,
                    "\(routine.id)/\(step.id) 用到了需要工具的 \(moveID)"
                )
            }
        }
    }

    /// 安全措辞的英文是翻译，专家审的是中文原文 —— 两者必须并存。
    func testSafetyNotesKeepTheirChineseSource() throws {
        for move in try loadBundle().sortedMoves where move.safetyNote != nil {
            XCTAssertFalse(
                (move.source.stopSignalsZh ?? "").isEmpty,
                "\(move.id) 有英文 safetyNote 却没有中文原文，Expert Gate 无从复核"
            )
        }
    }

    /// Sprint 3 开篇即声明全部动作仍需人工专家审核。
    func testEveryGoldMoveIsStillAwaitingExpertGate() throws {
        let bundle = try loadBundle()
        XCTAssertEqual(
            bundle.movesAwaitingExpertGate.count, bundle.moves.count,
            "有动作被标成 expert_reviewed，但 Expert Gate 尚未进行"
        )
    }

    func testEveryMovementAnchorReferenceResolvesOnBothSides() throws {
        let bundle = try loadBundle()
        for routine in bundle.routines {
            for step in routine.steps {
                let plan = PlaybackPlan(routine: routine)
                for segment in plan.segments where segment.step.id == step.id {
                    let movement = segment.resolvedMovement
                    if let start = movement.startAnchorID {
                        XCTAssertNotNil(bundle.anchors[start], "\(routine.id)/\(step.id) 的 startAnchor \(start) 不存在")
                    }
                    if let end = movement.endAnchorID {
                        XCTAssertNotNil(bundle.anchors[end], "\(routine.id)/\(step.id) 的 endAnchor \(end) 不存在")
                    }
                }
            }
        }
    }

    func testMirroredAnchorsAreGeneratedAutomatically() throws {
        let bundle = try loadBundle()
        XCTAssertNotNil(bundle.anchors["temple_left"])
        XCTAssertNotNil(bundle.anchors["temple_right"], "右侧 anchor 应由系统自动镜像生成")

        let left = try XCTUnwrap(bundle.anchors["temple_left"])
        let right = try XCTUnwrap(bundle.anchors["temple_right"])
        XCTAssertEqual(left.side, .left)
        XCTAssertEqual(right.side, .right)
        XCTAssertEqual(left.toleranceRadius, right.toleranceRadius, "镜像不应改变容差")
        XCTAssertEqual(
            right.rule.referencedLandmarks,
            Set(left.rule.referencedLandmarks.map(\.mirrored)),
            "镜像 anchor 应引用对侧 landmark"
        )
    }

    /// M1 的内容全部是 Mock，必须能被检出 —— 否则测试动作有机会混进正式发布。
    func testShippedContentIsFlaggedAsUnreviewed() throws {
        XCTAssertTrue(
            try loadBundle().containsUnreviewedContent,
            "M1 内容包必须标记为未审核；若这条测试失败，说明有人把 mock 内容标成了 expert_reviewed"
        )
    }

    /// 规格 §10：MVP 阶段任何动作都不得声称支持实时纠错。
    func testNoMovementClaimsRealtimeCorrection() throws {
        for routine in try loadBundle().routines {
            for step in routine.steps {
                XCTAssertNotEqual(
                    step.movement.trackingSupport,
                    .observableCorrectionExperimental,
                    "\(routine.id)/\(step.id) 声称支持实时纠错，违反规格 §10"
                )
            }
        }
    }

    func testLenientDecodingFillsDefaults() throws {
        let json = """
        {
          "id": "minimal",
          "title": "Minimal Step",
          "durationSeconds": 15
        }
        """.data(using: .utf8)!

        let step = try JSONDecoder().decode(RoutineStep.self, from: json)
        XCTAssertEqual(step.side, .none)
        XCTAssertEqual(step.shortCue, "")
        XCTAssertEqual(step.movement.pathType, .line)
        XCTAssertEqual(step.movement.repetitions, 1)
        XCTAssertEqual(step.movement.occlusionPolicy, .continueGuidance)
        XCTAssertEqual(step.reviewStatus, .mockUnreviewed, "未标注审核状态时必须按最保守的 mock 处理")
    }

    func testAnchorGeometryRuleRoundTripsThroughJSON() throws {
        let rule = AnchorGeometryRule.offset(
            base: .lerp(from: .landmark(.leftEyeCenter), to: .landmark(.leftMouthCorner), t: 0.55),
            dx: -0.12,
            dy: 0.03
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(AnchorGeometryRule.self, from: data)
        XCTAssertEqual(decoded, rule)
        XCTAssertEqual(decoded.referencedLandmarks, [.leftEyeCenter, .leftMouthCorner])
    }

    func testMirroringARuleFlipsLandmarksAndHorizontalOffset() {
        let rule = AnchorGeometryRule.offset(base: .landmark(.leftEyeOuter), dx: -0.30, dy: -0.08)
        guard case let .offset(base, dx, dy) = rule.mirrored() else {
            return XCTFail("镜像后应仍是 offset 规则")
        }
        XCTAssertEqual(base, .landmark(.rightEyeOuter))
        XCTAssertEqual(dx, 0.30, accuracy: 1e-12, "dx 必须取反")
        XCTAssertEqual(dy, -0.08, accuracy: 1e-12, "dy 不应改变")
    }
}

final class ContentValidatorTests: XCTestCase {

    private func bundle(
        routines: [Routine],
        anchors: [FaceAnchor] = [],
        moves: [GoldMove] = []
    ) -> ContentBundle {
        var table: [FaceAnchorID: FaceAnchor] = [:]
        for anchor in anchors { table[anchor.id] = anchor }
        var moveTable: [GoldMoveID: GoldMove] = [:]
        for move in moves { moveTable[move.id] = move }
        return ContentBundle(
            meta: ContentMeta(schemaVersion: ContentSchema.currentVersion, contentVersion: "test", reviewStatus: .expertReviewed),
            routines: routines,
            anchors: table,
            moves: moveTable
        )
    }

    private func move(
        id: String,
        tool: ToolRequirement = .none,
        allowed: [RoutineType] = [.morning, .evening, .quick],
        movement: MovementSpec = MovementSpec()
    ) -> GoldMove {
        GoldMove(
            id: GoldMoveID(rawValue: id),
            title: id,
            shortCue: "cue",
            region: .wholeFace,
            defaultDurationSeconds: 15,
            requiresTool: tool,
            allowedRoutineTypes: allowed,
            movement: movement,
            source: GoldMoveSource(documentRef: "test", titleZh: "测试")
        )
    }

    private func step(id: String, duration: Double = 30, movement: MovementSpec = MovementSpec()) -> RoutineStep {
        RoutineStep(id: RoutineStepID(rawValue: id), title: id, durationSeconds: duration, shortCue: "cue", movement: movement)
    }

    func testMissingAnchorReferenceIsAnError() {
        let routine = Routine(
            id: "r",
            title: "r",
            type: .morning,
            isPremium: false,
            steps: [step(id: "s", movement: MovementSpec(startAnchorID: "ghost", endAnchorID: "ghost2", pathType: .line))]
        )
        let issues = ContentValidator().validate(bundle(routines: [routine]))
        let errors = issues.filter { $0.severity == .error }
        XCTAssertTrue(errors.contains { $0.message.contains("ghost") })
    }

    func testPremiumMorningRoutineIsAnError() {
        // 直接构造一个违反 §11 的 routine —— 校验器必须拦下来。
        let routine = Routine(id: "r", title: "r", type: .morning, isPremium: true, steps: [step(id: "s")])
        let issues = ContentValidator().validate(bundle(routines: [routine]))
        XCTAssertTrue(
            issues.contains { $0.severity == .error && $0.message.contains("premium") },
            "Morning routine 标为 premium 必须报 error"
        )
    }

    func testMissingFreeMorningCoreIsAnError() {
        let routine = Routine(id: "r", title: "r", type: .quick, isPremium: true, steps: [step(id: "s")])
        let issues = ContentValidator().validate(bundle(routines: [routine]))
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("Morning Core") })
    }

    func testToolMoveAllowedInMorningIsAnError() {
        let tool = move(id: "T", tool: .guaSha, allowed: [.morning, .quick])
        let routine = Routine(id: "r", title: "r", type: .morning, isPremium: false, steps: [step(id: "s")])
        let issues = ContentValidator().validate(bundle(routines: [routine], moves: [tool]))
        XCTAssertTrue(
            issues.contains { $0.severity == .error && $0.message.contains("不能依赖工具") },
            "工具动作允许出现在 morning routine 必须报 error（Sprint 3 §9）"
        )
    }

    func testUsingAQuickOnlyMoveInAMorningRoutineIsAnError() {
        let quickOnly = move(id: "Q", allowed: [.quick])
        var built = quickOnly.makeStep(stepID: "s")
        built.movement = MovementSpec(pathType: .expression)
        let routine = Routine(id: "r", title: "r", type: .morning, isPremium: false, steps: [built])
        let issues = ContentValidator().validate(bundle(routines: [routine], moves: [quickOnly]))
        XCTAssertTrue(
            issues.contains { $0.severity == .error && $0.message.contains("却出现在 morning") },
            "动作声明的适用范围必须被强制执行"
        )
    }

    func testTapWithoutAnyAnchorIsAnError() {
        let routine = Routine(
            id: "r",
            title: "r",
            type: .morning,
            isPremium: false,
            steps: [step(id: "s", movement: MovementSpec(pathType: .tap))]
        )
        let issues = ContentValidator().validate(bundle(routines: [routine]))
        XCTAssertTrue(
            issues.contains { $0.severity == .error && $0.message.contains("pathType=tap") },
            "tap 没有 focusAnchors 也没有 startAnchor，AR 无处可画"
        )
    }

    /// 表情肌动作没有手部接触，不需要 anchor —— 不得因此被判为错误。
    func testExpressionMoveWithoutAnchorsIsNotAnError() {
        let routine = Routine(
            id: "r",
            title: "r",
            type: .morning,
            isPremium: false,
            steps: [step(id: "s", movement: MovementSpec(pathType: .expression))]
        )
        let issues = ContentValidator().validate(bundle(routines: [routine]))
        XCTAssertFalse(
            issues.contains { $0.severity == .error && $0.path.contains("steps") },
            "表情动作没有 anchor 是正常的，不应报 error"
        )
    }

    func testEmptyMoveLibraryIsAnError() {
        let routine = Routine(id: "r", title: "r", type: .morning, isPremium: false, steps: [step(id: "s")])
        let issues = ContentValidator().validate(bundle(routines: [routine]))
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("动作库为空") })
    }

    func testLinePathWithoutEndAnchorIsAnError() {
        let routine = Routine(
            id: "r",
            title: "r",
            type: .morning,
            isPremium: false,
            steps: [step(id: "s", movement: MovementSpec(startAnchorID: "a", pathType: .line))]
        )
        let anchor = FaceAnchor(id: "a", name: "a", rule: .landmark(.noseTip))
        let issues = ContentValidator().validate(bundle(routines: [routine], anchors: [anchor]))
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("endAnchor") })
    }
}

final class EntitlementPolicyTests: XCTestCase {

    private let morning = Routine(id: "m", title: "m", type: .morning, isPremium: false, steps: [])
    private let evening = Routine(id: "e", title: "e", type: .evening, isPremium: true, steps: [])
    private let quick = Routine(id: "q", title: "q", type: .quick, isPremium: true, steps: [])

    func testMorningCoreIsAlwaysFree() {
        XCTAssertEqual(EntitlementPolicy.decide(routine: morning, level: .free), .allowed)
        // 即使内容 JSON 被误标成 premium，代码层的产品承诺仍然生效。
        let mislabeled = Routine(id: "m2", title: "m2", type: .morning, isPremium: true, steps: [])
        XCTAssertEqual(EntitlementPolicy.decide(routine: mislabeled, level: .free), .allowed)
    }

    func testEveningAndQuickRequirePremiumForFreeUsers() {
        XCTAssertEqual(EntitlementPolicy.decide(routine: evening, level: .free), .requiresPremium)
        XCTAssertEqual(EntitlementPolicy.decide(routine: quick, level: .free), .requiresPremium)
        XCTAssertEqual(EntitlementPolicy.decide(routine: evening, level: .premium), .allowed)
        XCTAssertEqual(EntitlementPolicy.decide(routine: quick, level: .premium), .allowed)
    }

    /// 规格 §11 表格：AR Mirror Guidance 在 Morning Core 内对免费用户开放。
    func testARMirrorIsAvailableToFreeUsersInsideMorningCore() {
        XCTAssertEqual(EntitlementPolicy.decideARMirror(routine: morning, level: .free), .allowed)
        XCTAssertEqual(EntitlementPolicy.decideARMirror(routine: evening, level: .free), .requiresPremium)
    }

    func testMockUnlockFlipsEntitlementLevel() throws {
        let storage = InMemoryEntitlementFlagStorage()
        let service = MockEntitlementService(storage: storage)
        XCTAssertEqual(service.level, .free)

        var observed: [EntitlementLevel] = []
        service.onChange = { observed.append($0) }

        service.setMockUnlocked(true)
        XCTAssertEqual(service.level, .premium)
        XCTAssertEqual(observed, [.premium])
        XCTAssertEqual(EntitlementPolicy.decide(routine: evening, level: service.level), .allowed)

        service.setMockUnlocked(false)
        XCTAssertEqual(service.level, .free)
        XCTAssertEqual(observed, [.premium, .free])
    }

    func testPurchaseOfUnknownProductThrows() async {
        let service = MockEntitlementService(storage: InMemoryEntitlementFlagStorage())
        do {
            try await service.purchase(productID: "not.a.product")
            XCTFail("未知商品应抛错")
        } catch {
            XCTAssertTrue(error is EntitlementError)
        }
    }
}


/// 规格 §15 点名要求的五个 AR analytics 事件。
///
/// 事件名是**对外契约**：POC 与后续留存分析都按这些名字取数。
/// 有人手滑改成 driver-friendly 的命名，报表会静默断掉而不会报错 ——
/// 所以在这里钉死。
final class AnalyticsContractTests: XCTestCase {

    func testSpecRequiredAREventNamesAreExact() {
        let routineID: RoutineID = "r"
        let stepID: RoutineStepID = "s"

        let expected: [(AnalyticsEvent, String)] = [
            (.arMirrorStarted(routineID: routineID, providerID: "vision"), "arMirrorStarted"),
            (.arStepCompleted(routineID: routineID, stepID: stepID, quality: .good), "arStepCompleted"),
            (.faceLockLost(routineID: routineID, stepID: stepID, hint: .handCoveringFace), "faceLockLost"),
            (.guidanceFallback(routineID: routineID, from: .arMirror, to: .coach, reason: "x"), "guidanceFallback"),
            (.watchModeUsed(routineID: routineID), "watchModeUsed")
        ]

        for (event, name) in expected {
            XCTAssertEqual(event.name, name, "规格 §15 指定的事件名不能改")
        }
    }

    /// 规格 §17 的 AR 指标要能算出来，靠的是这两个事件带的参数。
    func testARQualityEventsCarryTheMetricsTheSpecAsksFor() {
        let lock = AnalyticsEvent.faceLockAcquired(providerID: "vision", secondsToLock: 1.25)
        XCTAssertEqual(lock.parameters["provider"], "vision")
        XCTAssertEqual(lock.parameters["seconds_to_lock"], "1.25")

        let quality = AnalyticsEvent.arSessionQuality(
            providerID: "vision",
            averageFPS: 29.4,
            averageLatencyMS: 18.2,
            lockLossCount: 3
        )
        XCTAssertEqual(quality.parameters["avg_fps"], "29.4")
        XCTAssertEqual(quality.parameters["avg_latency_ms"], "18.2")
        XCTAssertEqual(quality.parameters["lock_loss_count"], "3")
    }

    /// 每个事件都必须能取到名字与参数，不能有漏写的 case。
    func testEveryEventProducesNameAndParameters() {
        let samples: [AnalyticsEvent] = [
            .appOpened(isFirstLaunch: true),
            .homeViewed(greeting: "Good morning"),
            .routineStarted(routineID: "r", type: .morning, mode: .coach),
            .routineCompleted(routineID: "r", mode: .arMirror, secondsCompleted: 180),
            .routineAbandoned(routineID: "r", mode: .coach, secondsCompleted: 42, atStepIndex: 2),
            .modeSelected(mode: .watch, routineID: "r"),
            .cameraPermissionRequested,
            .cameraPermissionResult(granted: true),
            .paywallViewed(source: "home"),
            .purchaseAttempted(productID: "p"),
            .purchaseResult(productID: "p", success: false),
            .mockUnlockToggled(enabled: true),
            .reminderScheduled(kind: "morning", hour: 8, minute: 0),
            .reminderCancelled(kind: "evening"),
            .contentValidationIssues(errorCount: 0, warningCount: 1)
        ]

        for event in samples {
            XCTAssertFalse(event.name.isEmpty, "事件缺少名字")
            for (key, value) in event.parameters {
                XCTAssertFalse(key.isEmpty, "\(event.name) 有空参数名")
                XCTAssertFalse(
                    value.contains(where: \.isNewline),
                    "\(event.name) 的参数值不应含换行"
                )
            }
        }
    }
}
