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

    private var fixture: GoldenFixture!
    private var bundle: ContentBundle!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = try GoldenFixture.load()
        bundle = try BundledContent.makeRepository(failOnValidationError: false).load()
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
                    accuracy: 1e-9,
                    "\(anchorID) 在不同尺度/位置/倾斜下漂移了"
                )
            }
        }
    }

    // MARK: - 路径采样

    func testMotionPathsMatchReference() throws {
        let resolver = FaceAnchorResolver()
        let sampler = PathSampler()
        let morning = try XCTUnwrap(bundle.routine(id: RoutineID(rawValue: "morning_core")))

        for testCase in fixture.cases {
            let geometry = testCase.makeGeometry()
            let frame = try XCTUnwrap(FaceFrame(geometry: geometry))

            for expected in testCase.paths {
                let step = try XCTUnwrap(
                    morning.steps.first { $0.id.rawValue == expected.stepID },
                    "morning_core 应包含 step \(expected.stepID)"
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
