import XCTest
import FaceRitualCore
@testable import FaceRitual

/// 示范视频的文件名约定。
///
/// 这条约定同时存在于**三个地方**：
///   1. `GoldMove.makeStep` 生成 `mediaAsset`（GM-01 → coach_gm_01）
///   2. `tools/check_coach_videos.py` 按同一规则检查素材到位情况
///   3. `docs/COACH_VIDEO_SPEC.md` 告诉做视频的人怎么命名
///
/// 三处漂开的后果很隐蔽：App 找不到文件 → **回落到示意动画** → 看起来一切正常，
/// 只是视频没播，不报错、不崩溃。所以要有测试盯着。
final class CoachVideoAssetTests: XCTestCase {

    private func loadBundle() throws -> ContentBundle {
        try BundledContent.makeRepository(failOnValidationError: false).load()
    }

    /// 每个动作都要有 mediaAsset，否则那个动作永远播不了视频。
    func testEveryStepHasAMediaAsset() throws {
        let bundle = try loadBundle()
        for routine in bundle.routines {
            for step in routine.steps {
                XCTAssertNotNil(
                    step.mediaAsset,
                    "\(routine.id)/\(step.id) 没有 mediaAsset —— 这一步永远播不了示范视频"
                )
            }
        }
    }

    /// 命名规则必须与文档和 Python 检查器一致：GM-01 → coach_gm_01。
    ///
    /// 写死几个期望值而不是复述规则 —— 复述规则的测试只会证明「代码等于它自己」。
    func testAssetNameConventionMatchesTheSpec() throws {
        let bundle = try loadBundle()
        let expectations = [
            ("GM-01", "coach_gm_01"),
            ("GM-08", "coach_gm_08"),
            ("GM-20", "coach_gm_20"),
        ]
        for (moveID, expectedAsset) in expectations {
            let move = try XCTUnwrap(
                bundle.moves[GoldMoveID(rawValue: moveID)],
                "动作库里没有 \(moveID)"
            )
            let step = move.makeStep(stepID: "probe")
            XCTAssertEqual(
                step.mediaAsset, expectedAsset,
                "\(moveID) 的视频文件名应为 \(expectedAsset).mp4"
                + "（docs/COACH_VIDEO_SPEC.md 与 tools/check_coach_videos.py 都按这个规则）"
            )
        }
    }

    /// 同一个动作在不同 routine 里必须指向同一个文件 ——
    /// 否则同一段示范要做两份素材。
    func testSameMoveAlwaysMapsToTheSameAsset() throws {
        let bundle = try loadBundle()
        var assetByMove: [GoldMoveID: String] = [:]
        for routine in bundle.routines {
            for step in routine.steps {
                guard let moveID = step.sourceMoveID, let asset = step.mediaAsset else { continue }
                if let existing = assetByMove[moveID] {
                    XCTAssertEqual(existing, asset, "\(moveID) 在不同 routine 里指向了不同的视频文件")
                } else {
                    assetByMove[moveID] = asset
                }
            }
        }
        XCTAssertFalse(assetByMove.isEmpty)
    }

    /// 缺素材必须是**可用状态**，不是错误。
    ///
    /// 视频是后补的，播放器要在没有任何视频时照常工作 ——
    /// 这正是「先上架、素材后补」这条路走得通的前提。
    func testMissingVideosResolveToNilRatherThanCrashing() {
        XCTAssertNil(
            LoopingVideoPlayer.resolve(assetName: "coach_gm_01_definitely_not_bundled"),
            "找不到文件时应返回 nil，由播放器回落到示意动画"
        )
    }

    /// 素材进度统计按**去重后的资源名**算，不按 step 数。
    /// Prototype A 里 GM-11 出现两次，不该被算成两段视频。
    func testAvailabilityCountsDistinctAssets() throws {
        let bundle = try loadBundle()
        let routine = try XCTUnwrap(bundle.routine(id: "morning_prototype_a"))
        let status = LoopingVideoPlayer.availability(for: routine.steps)

        let distinct = Set(routine.steps.compactMap(\.mediaAsset)).count
        XCTAssertEqual(status.total, distinct, "总数应为去重后的资源数")
        XCTAssertLessThan(status.total, routine.steps.count, "Prototype A 有重复动作，去重后应更少")
    }
}
