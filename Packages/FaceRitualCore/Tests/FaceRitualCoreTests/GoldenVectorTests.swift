import XCTest
@testable import FaceRitualCore

/// 与 `tools/golden/generate_golden.py` 的独立参考实现交叉验证。
///
/// 两套实现（Swift / Python）由不同代码路径算出同一批数值，
/// 同时算错同一处的概率远低于单边实现 —— 这是几何层的主要正确性保障。
final class GoldenVectorTests: XCTestCase {

    /// 视图坐标容差（points）。两边都用 Double，差异只来自 JSON 的 6 位小数舍入。
    private let viewTolerance = 1e-4
    /// 归一化坐标容差（瞳距）。
    private let localTolerance = 1e-6

    /// 不变性容差（瞳距）。
    ///
    /// 定这个数字要在两个方向之间取平衡，两边都有实际后果：
    ///
    /// - **下界（不能太小）**：Swift 是从 golden 文件里的坐标重建几何的，
    ///   而文件按 9 位小数存储。瞳距最小的用例只有 42px，
    ///   视图坐标上的舍入除以 42 后会放大 —— 实测量化噪声约 2e-11。
    ///   容差低于这个数，测试就会因为文件精度而假失败。
    ///   （第一版设成 1e-9、文件只存 6 位，CI 上就是这么挂的：
    ///   预测漂移 2.326e-08，实测 2.33e-08，分毫不差。）
    ///
    /// - **上界（不能太大）**：1 个瞳距在屏幕上约 60px，
    ///   所以 1e-6 瞳距 ≈ 0.00006 像素 —— 肉眼绝无可能看见。
    ///
    /// 取 1e-6：比量化噪声高约 5 万倍（不会假失败），
    /// 又比任何真实缺陷小得多（嘴角镜像那个 bug 造成的偏差是 28%）。
    static let invarianceTolerance = 1e-6

    private var fixture: GoldenFixture!
    private var bundle: ContentBundle!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try GoldenFixture.load()
        bundle = try BundledContent.makeRepository(failOnValidationError: false).load()
    }

    // MARK: - 合成示意脸

    /// 运行时画示意图用的那张合成脸，必须与 golden 数据里的 `reference` 用例一致。
    ///
    /// 为什么重要：golden vector 验证的是「几何算得对不对」，
    /// 而 App 在没有示范视频时**真正画在屏幕上**的，是用 `SyntheticFace` 算出来的位置。
    /// 两者一旦漂开，golden 就在验证一张没人用的脸 —— 测试还是绿的，屏幕上却是错的。
    ///
    /// `reference` 用例的参数：双眼中点 (200, 300)、瞳距 100、roll 0。
    func testSyntheticFaceMatchesGoldenFixture() throws {
        let reference = try XCTUnwrap(
            fixture.cases.first { $0.name == "reference" },
            "golden 数据里应有名为 reference 的用例"
        )
        XCTAssertEqual(reference.interocularDistance, 100, accuracy: 1e-9)
        XCTAssertEqual(reference.rollDegrees, 0, accuracy: 1e-9)

        // frame.origin 按定义就是双眼中点 —— fixture 的 Case 里没有单独的 eyeMidpoint 字段。
        let geometry = SyntheticFace.makeGeometry(
            center: Point2D(x: reference.frame.origin[0], y: reference.frame.origin[1]),
            interocular: reference.interocularDistance
        )

        XCTAssertEqual(
            geometry.landmarks.count, reference.landmarks.count,
            "合成脸的 landmark 数量与 golden 数据不一致"
        )

        for (name, expected) in reference.landmarks {
            let mark = try XCTUnwrap(
                SemanticLandmark(rawValue: name),
                "golden 数据里的 \(name) 不是已知 landmark"
            )
            let sample = try XCTUnwrap(
                geometry.landmarks[mark],
                "合成脸缺少 \(name) —— 屏幕上会少画一些位置"
            )
            XCTAssertEqual(sample.point.x, expected[0], accuracy: viewTolerance, "\(name).x")
            XCTAssertEqual(sample.point.y, expected[1], accuracy: viewTolerance, "\(name).y")
        }
    }

    /// 内容里定义的**每一个**位置都要能在合成脸上解析出来。
    ///
    /// 这条才是真正要守的东西：之前示意图查的是一张手写的 9 个位置表，
    /// 而内容有 27 个位置 —— 15 个有轨迹的动作只画得出 4 个，
    /// 其余 11 个屏幕上什么都没有。而视频到位之前，示意图就是全部画面。
    func testEveryContentAnchorResolvesOnTheSyntheticFace() throws {
        let geometry = SyntheticFace.makeGeometry(center: Point2D(x: 200, y: 300), interocular: 100)
        let frame = try XCTUnwrap(FaceFrame(geometry: geometry))
        let resolver = FaceAnchorResolver()

        for (id, anchor) in bundle.anchors.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard case .success = resolver.resolve(anchor, geometry: geometry, frame: frame) else {
                XCTFail("位置 \(id) 在示意脸上解析不出来 —— 用到它的动作会画不出路径")
                continue
            }
        }
    }

    /// 每个有轨迹的动作都要能画出路径。
    ///
    /// 直接断言用户会看到什么，而不是断言中间数据结构 ——
    /// 「屏幕上有没有东西」才是这条回落路径的意义。
    func testEveryPathMovementCanBeDrawnOnTheSyntheticFace() throws {
        let geometry = SyntheticFace.makeGeometry(center: Point2D(x: 200, y: 300), interocular: 100)
        let frame = try XCTUnwrap(FaceFrame(geometry: geometry))
        let resolver = FaceAnchorResolver()
        let sampler = PathSampler()

        for move in bundle.sortedMoves where move.movement.pathType.drawsPath {
            let movement = move.movement
            guard let startID = movement.startAnchorID,
                  let startAnchor = bundle.anchors[startID],
                  case let .success(start) = resolver.resolve(startAnchor, geometry: geometry, frame: frame)
            else {
                XCTFail("\(move.id) 的起点画不出来")
                continue
            }
            var end: Point2D?
            if let endID = movement.endAnchorID {
                guard let endAnchor = bundle.anchors[endID],
                      case let .success(resolved) = resolver.resolve(endAnchor, geometry: geometry, frame: frame)
                else {
                    XCTFail("\(move.id) 的终点画不出来")
                    continue
                }
                end = resolved.viewPoint
            }

            let path = sampler.makePath(
                movement: movement, start: start.viewPoint, end: end, frame: frame
            )
            XCTAssertFalse(path.points.isEmpty, "\(move.id) 采样出来是空路径")
        }
    }

    // MARK: - FaceFrame

    func testFaceFrameMatchesReference() throws {
        for testCase in fixture.cases {
            let geometry = testCase.makeGeometry()
            let frame = try XCTUnwrap(FaceFrame(geometry: geometry), "用例 \(testCase.name) 应能建立 FaceFrame")

            XCTAssertEqual(frame.scale, testCase.frame.scale, accuracy: viewTolerance, "\(testCase.name) scale")
            XCTAssertEqual(frame.origin.x, testCase.frame.origin[0], accuracy: viewTolerance, "\(testCase.name) origin.x")
            XCTAssertEqual(frame.origin.y, testCase.frame.origin[1], accuracy: viewTolerance, "\(testCase.name) origin.y")
            XCTAssertEqual(frame.xAxis.dx, testCase.frame.xAxis[0], accuracy: viewTolerance, "\(testCase.name) xAxis.dx")
            XCTAssertEqual(frame.xAxis.dy, testCase.frame.xAxis[1], accuracy: viewTolerance, "\(testCase.name) xAxis.dy")
            XCTAssertEqual(frame.yAxis.dx, testCase.frame.yAxis[0], accuracy: viewTolerance, "\(testCase.name) yAxis.dx")
            XCTAssertEqual(frame.yAxis.dy, testCase.frame.yAxis[1], accuracy: viewTolerance, "\(testCase.name) yAxis.dy")
        }
    }

    func testFaceFrameRoundTripsThroughLocalSpace() throws {
        for testCase in fixture.cases {
            let frame = try XCTUnwrap(FaceFrame(geometry: testCase.makeGeometry()))
            for sample in [Point2D(x: 0, y: 0), Point2D(x: 0.5, y: -0.3), Point2D(x: -1.2, y: 1.7)] {
                let roundTripped = frame.toLocal(view: frame.toView(local: sample))
                XCTAssertEqual(roundTripped.x, sample.x, accuracy: 1e-9)
                XCTAssertEqual(roundTripped.y, sample.y, accuracy: 1e-9)
            }
        }
    }

    // MARK: - Anchor 解析

    func testAnchorsResolveToReferencePositions() throws {
        let resolver = FaceAnchorResolver()

        for testCase in fixture.cases {
            let geometry = testCase.makeGeometry()
            let frame = try XCTUnwrap(FaceFrame(geometry: geometry))

            for (anchorID, expected) in testCase.anchors {
                let anchor = try XCTUnwrap(
                    bundle.anchors[FaceAnchorID(rawValue: anchorID)],
                    "内容包里应存在 anchor \(anchorID)（含自动镜像）"
                )
                let result = resolver.resolve(anchor, geometry: geometry, frame: frame)
                guard case let .success(resolved) = result else {
                    XCTFail("\(testCase.name)/\(anchorID) 解析失败: \(result)")
                    continue
                }
                XCTAssertEqual(resolved.viewPoint.x, expected.view[0], accuracy: viewTolerance, "\(testCase.name)/\(anchorID) view.x")
                XCTAssertEqual(resolved.viewPoint.y, expected.view[1], accuracy: viewTolerance, "\(testCase.name)/\(anchorID) view.y")
                XCTAssertEqual(resolved.localPoint.x, expected.local[0], accuracy: localTolerance, "\(testCase.name)/\(anchorID) local.x")
                XCTAssertEqual(resolved.localPoint.y, expected.local[1], accuracy: localTolerance, "\(testCase.name)/\(anchorID) local.y")
                XCTAssertEqual(
                    resolved.toleranceRadiusPoints,
                    expected.toleranceRadiusPoints,
                    accuracy: viewTolerance,
                    "\(testCase.name)/\(anchorID) tolerance"
                )
            }
        }
    }

    /// M1 里程碑真正要证明的性质：
    /// 同一个 anchor，在不同脸型（尺度）、不同画面位置、不同头部倾斜下，
    /// 在**脸部局部坐标系**里必须落在同一点。
    ///
    /// 注意这只覆盖平面内变换（尺度 / 平移 / roll）。
    /// 出平面的 yaw / pitch 稳定性只能在真机上测（见 AR_POC_REPORT.md）。
    func testAnchorPositionsAreInvariantAcrossScaleTranslationAndRoll() throws {
        let resolver = FaceAnchorResolver()
        var localsByAnchor: [String: [Point2D]] = [:]

        for testCase in fixture.cases {
            let geometry = testCase.makeGeometry()
            let frame = try XCTUnwrap(FaceFrame(geometry: geometry))
            for anchor in bundle.anchors.values {
                guard case let .success(resolved) = resolver.resolve(anchor, geometry: geometry, frame: frame) else {
                    continue
                }
                localsByAnchor[anchor.id.rawValue, default: []].append(resolved.localPoint)
            }
        }

        XCTAssertFalse(localsByAnchor.isEmpty, "应至少解析出一个 anchor")

        for (anchorID, locals) in localsByAnchor {
            guard let reference = locals.first else { continue }
            XCTAssertEqual(locals.count, fixture.cases.count, "\(anchorID) 应在每个用例中都解析成功")
            for local in locals.dropFirst() {
                XCTAssertEqual(
                    local.distance(to: reference),
                    0,
                    accuracy: GoldenVectorTests.invarianceTolerance,
                    "\(anchorID) 在不同尺度/位置/倾斜下漂移了"
                )
            }
        }
    }

    // MARK: - 路径采样

    func testMotionPathsMatchReference() throws {
        let resolver = FaceAnchorResolver()
        let sampler = PathSampler()
        // 必须与 tools/golden/generate_golden.py 的 GOLDEN_ROUTINE_ID 一致。
        let morning = try XCTUnwrap(bundle.routine(id: RoutineID(rawValue: "morning_prototype_b")))

        for testCase in fixture.cases {
            let geometry = testCase.makeGeometry()
            let frame = try XCTUnwrap(FaceFrame(geometry: geometry))

            for expected in testCase.paths {
                let step = try XCTUnwrap(
                    morning.steps.first { $0.id.rawValue == expected.stepID },
                    "参考 routine 应包含 step \(expected.stepID)"
                )
                let movement = step.movement
                let startID = try XCTUnwrap(movement.startAnchorID)
                let startPoint = try resolvedPoint(startID, resolver: resolver, geometry: geometry, frame: frame)
                let endPoint = try movement.endAnchorID.map {
                    try resolvedPoint($0, resolver: resolver, geometry: geometry, frame: frame)
                }

                let path = sampler.makePath(movement: movement, start: startPoint, end: endPoint, frame: frame)

                let label = "\(testCase.name)/\(expected.stepID)"
                XCTAssertEqual(path.kind.rawValue, expected.kind, "\(label) kind")
                XCTAssertEqual(path.points.count, expected.pointCount, "\(label) pointCount")

                assertPoint(path.points.first, expected.first, label: "\(label) first")
                assertPoint(path.points[path.points.count / 2], expected.middle, label: "\(label) middle")
                assertPoint(path.points.last, expected.last, label: "\(label) last")

                if let expectedCenter = expected.center {
                    assertPoint(path.center, expectedCenter, label: "\(label) center")
                } else {
                    XCTAssertNil(path.center, "\(label) 不应有 center")
                }
            }
        }
    }

    /// 移动光点按弧长参数化 —— 等间隔的 progress 必须走出等长的弧段。
    /// 否则圆弧和贝塞尔上的节奏提示会忽快忽慢。
    func testPathProgressIsArcLengthUniform() throws {
        let sampler = PathSampler()
        let frame = FaceFrame(
            origin: Point2D(x: 200, y: 300),
            xAxis: Vector2D(dx: 1, dy: 0),
            yAxis: Vector2D(dx: 0, dy: 1),
            scale: 100
        )
        let movement = MovementSpec(
            startAnchorID: "a",
            endAnchorID: "b",
            pathType: .curve,
            pathGeometry: PathGeometry(controlOffsets: [PathControlOffset(along: 0.5, perpendicular: -0.6)])
        )
        let path = sampler.makePath(
            movement: movement,
            start: Point2D(x: 100, y: 400),
            end: Point2D(x: 320, y: 250),
            frame: frame
        )

        let steps = 20
        var lengths: [Double] = []
        for index in 0..<steps {
            let a = path.point(atProgress: Double(index) / Double(steps))
            let b = path.point(atProgress: Double(index + 1) / Double(steps))
            lengths.append(a.distance(to: b))
        }
        let expected = path.totalLength / Double(steps)
        for length in lengths {
            // 折线离散化带来的偏差应远小于 2%。
            XCTAssertEqual(length, expected, accuracy: expected * 0.02)
        }
    }

    // MARK: - Helpers

    private func resolvedPoint(
        _ id: FaceAnchorID,
        resolver: FaceAnchorResolver,
        geometry: FaceGeometry,
        frame: FaceFrame
    ) throws -> Point2D {
        let anchor = try XCTUnwrap(bundle.anchors[id], "缺少 anchor \(id)")
        guard case let .success(resolved) = resolver.resolve(anchor, geometry: geometry, frame: frame) else {
            throw XCTSkip("anchor \(id) 解析失败")
        }
        return resolved.viewPoint
    }

    private func assertPoint(_ actual: Point2D?, _ expected: [Double], label: String) {
        guard let actual else {
            XCTFail("\(label): 期望有点，实际为 nil")
            return
        }
        XCTAssertEqual(actual.x, expected[0], accuracy: viewTolerance, "\(label).x")
        XCTAssertEqual(actual.y, expected[1], accuracy: viewTolerance, "\(label).y")
    }
}

/// 语义 landmark 的镜像不变量。
///
/// 这组测试是补上一个真实 bug 之后加的：
/// 曾经有 `mouthLeftCorner` 这种把侧别写在名字中间的命名，
/// 而 `mirrored` 用 `hasPrefix("left")` 判定侧别 —— 于是嘴角**不会翻转**。
/// 后果是右脸 Cheek Lift 的起点被算到脸中间，路径长度左右差了 38%。
///
/// golden vector 验的是「同一个 anchor 在不同尺度/位置/倾斜下不漂移」，
/// 是另一条性质，抓不到这个。所以需要这组独立的不变量。
final class SemanticLandmarkMirrorTests: XCTestCase {

    func testMirroringIsAnInvolution() {
        for landmark in SemanticLandmark.allCases {
            XCTAssertEqual(
                landmark.mirrored.mirrored,
                landmark,
                "\(landmark.rawValue) 镜像两次应回到自身"
            )
        }
    }

    /// 名字里带 left/right 的点，必须真的能镜像到**另一个**点。
    /// 这正是当初漏掉的那条：`mouthLeftCorner.mirrored == mouthLeftCorner`。
    func testEverySidedLandmarkMirrorsToADifferentLandmark() {
        for landmark in SemanticLandmark.allCases where landmark.side != .none {
            XCTAssertNotEqual(
                landmark.mirrored,
                landmark,
                "\(landmark.rawValue) 有侧别却镜像到了自己 —— 对侧点缺失或命名不符合约定"
            )
            XCTAssertEqual(
                landmark.mirrored.side,
                landmark.side == .left ? .right : .left,
                "\(landmark.rawValue) 镜像后侧别不对"
            )
        }
    }

    func testMidlineLandmarksMirrorToThemselves() {
        for landmark in SemanticLandmark.allCases where landmark.side == .none {
            XCTAssertEqual(landmark.mirrored, landmark, "\(landmark.rawValue) 是中线点，不应改变")
            XCTAssertTrue(landmark.isMidline)
        }
    }

    /// 侧别必须能从名字判断出来，且左右两侧成对存在。
    func testSidedLandmarksComeInPairs() {
        let sided = SemanticLandmark.allCases.filter { $0.side != .none }
        let lefts = sided.filter { $0.side == .left }
        let rights = sided.filter { $0.side == .right }
        XCTAssertEqual(lefts.count, rights.count, "左右侧 landmark 数量应相等")

        for left in lefts {
            XCTAssertTrue(
                rights.contains(left.mirrored),
                "\(left.rawValue) 找不到对应的右侧点"
            )
        }
    }

    /// 内容里用到的每个 anchor，其左右两版必须解析到**镜像对称**的位置。
    ///
    /// 这条直接对应那个 bug 的表现：左右路径长度不一致。
    func testLeftAndRightAnchorsResolveSymmetrically() throws {
        let bundle = try BundledContent.makeRepository(failOnValidationError: false).load()
        let resolver = FaceAnchorResolver()
        let fixture = try GoldenFixture.load()

        // 用正脸用例（roll = 0），左右对称才有意义。
        guard let testCase = fixture.cases.first(where: { $0.rollDegrees == 0 && $0.name == "reference" }) else {
            throw XCTSkip("缺少 reference 用例")
        }
        let geometry = testCase.makeGeometry()
        let frame = try XCTUnwrap(FaceFrame(geometry: geometry))

        for anchor in bundle.anchors.values where anchor.side == .left {
            let mirroredID = anchor.id.mirrored
            guard let rightAnchor = bundle.anchors[mirroredID] else {
                XCTFail("\(anchor.id) 没有对应的右侧 anchor")
                continue
            }
            guard
                case let .success(left) = resolver.resolve(anchor, geometry: geometry, frame: frame),
                case let .success(right) = resolver.resolve(rightAnchor, geometry: geometry, frame: frame)
            else {
                XCTFail("\(anchor.id) 或其镜像解析失败")
                continue
            }

            // 合成脸左右对称，所以两侧的局部坐标应满足 x 相反、y 相同。
            XCTAssertEqual(
                left.localPoint.x, -right.localPoint.x, accuracy: 1e-9,
                "\(anchor.id) 与 \(mirroredID) 的横向位置不对称"
            )
            XCTAssertEqual(
                left.localPoint.y, right.localPoint.y, accuracy: 1e-9,
                "\(anchor.id) 与 \(mirroredID) 的纵向位置不一致"
            )
        }
    }
}

// MARK: - Fixture 解码

struct GoldenFixture: Decodable {
    let sampleCount: Int
    let cases: [Case]

    struct Case: Decodable {
        let name: String
        let interocularDistance: Double
        let rollDegrees: Double
        let landmarks: [String: [Double]]
        let frame: Frame
        let anchors: [String: Anchor]
        let paths: [Path]

        /// 把 golden 里的 landmark 还原成 FaceGeometry。
        func makeGeometry() -> FaceGeometry {
            var table: [SemanticLandmark: LandmarkSample] = [:]
            for (name, coordinates) in landmarks {
                guard let mark = SemanticLandmark(rawValue: name) else { continue }
                table[mark] = LandmarkSample(point: Point2D(x: coordinates[0], y: coordinates[1]))
            }
            return FaceGeometry(
                providerID: "golden",
                timestamp: 0,
                trackingState: .locked,
                pose: HeadPose(rollDegrees: rollDegrees),
                landmarks: table,
                boundingBox: Rect2D(x: 0, y: 0, width: 400, height: 700),
                viewSize: Size2D(width: 400, height: 800),
                overallConfidence: 1.0
            )
        }
    }

    struct Frame: Decodable {
        let origin: [Double]
        let xAxis: [Double]
        let yAxis: [Double]
        let scale: Double
    }

    struct Anchor: Decodable {
        let view: [Double]
        let local: [Double]
        let toleranceRadiusPoints: Double
    }

    struct Path: Decodable {
        let stepID: String
        let kind: String
        let pointCount: Int
        let first: [Double]
        let middle: [Double]
        let last: [Double]
        let center: [Double]?
    }

    static func load() throws -> GoldenFixture {
        guard let url = Bundle.module.url(forResource: "golden_vectors", withExtension: "json") else {
            throw NSError(
                domain: "GoldenFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "缺少 golden_vectors.json —— 先运行 python tools/golden/generate_golden.py"]
            )
        }
        return try JSONDecoder().decode(GoldenFixture.self, from: try Data(contentsOf: url))
    }
}
