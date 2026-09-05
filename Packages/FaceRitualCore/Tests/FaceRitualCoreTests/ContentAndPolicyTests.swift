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
        XCTAssertEqual(morning.steps.count, 5)
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
            base: .lerp(from: .landmark(.leftEyeCenter), to: .landmark(.mouthLeftCorner), t: 0.55),
            dx: -0.12,
            dy: 0.03
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(AnchorGeometryRule.self, from: data)
        XCTAssertEqual(decoded, rule)
        XCTAssertEqual(decoded.referencedLandmarks, [.leftEyeCenter, .mouthLeftCorner])
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

    private func bundle(routines: [Routine], anchors: [FaceAnchor] = []) -> ContentBundle {
        var table: [FaceAnchorID: FaceAnchor] = [:]
        for anchor in anchors { table[anchor.id] = anchor }
        return ContentBundle(
            meta: ContentMeta(schemaVersion: 1, contentVersion: "test", reviewStatus: .expertReviewed),
            routines: routines,
            anchors: table
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
