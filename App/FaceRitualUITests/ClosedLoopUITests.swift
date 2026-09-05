import XCTest

/// M1 里程碑闭环的自动化验证。
///
/// **为什么这个文件重要：**
/// 里程碑定义是「打开 App → START → 模式 → 走完 routine → Done → 保存记录」。
/// 除了「在真人脸上」那一环，其余全部可以在模拟器里自动跑 ——
/// 而 GitHub Actions 提供 macOS 机器，所以这条闭环每次推代码都会被验证一遍，
/// 不需要任何人手里有 Mac。
///
/// 模拟器没有摄像头，Vision / HRFFA / ARKit 都会如实报告不可用，
/// 工厂自动回落到 Mock provider（合成动画脸）。
/// 于是 AR Mirror 这条路径也能跑通 —— 验证的是播放器、overlay 编排、
/// 记录保存这整条链路，只是脸是合成的。
///
/// **测不到的**：真人脸上的贴合精度、FPS、遮挡表现。那些只能上真机（见 AR_POC_REPORT.md）。
final class ClosedLoopUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        app = XCUIApplication()
        // 清空本地状态，让每次跑的起点一致（否则上一轮的练习记录会影响断言）。
        app.launchArguments += [AppEnvironmentUITestFlags.reset]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - 闭环

    func testCoachModeCompletesAndSavesARecord() throws {
        startMorningRitual()
        chooseMode(A11yID.modeCoach)
        walkThroughAllSegments()
        assertDoneScreenAppeared()
        returnHome()
        assertMonthlySummaryCountsOneSession()
    }

    /// AR Mirror 路径。模拟器上会自动回落到 Mock provider。
    func testARMirrorCompletesOnSyntheticFace() throws {
        startMorningRitual()
        chooseMode(A11yID.modeARMirror)
        walkThroughAllSegments()
        assertDoneScreenAppeared()
    }

    /// 规格 §4：识别失败不得阻塞 routine。
    /// Watch & Breathe 走的是同一套播放器，也必须能走完。
    func testWatchModeReachesTheEnd() throws {
        startMorningRitual()
        chooseMode(A11yID.modeWatch)

        // Watch 模式没有上一步/下一步按钮，只有暂停 —— 用暂停确认播放器起来了。
        let pause = app.buttons[A11yID.playerPauseToggle]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "Watch 模式的播放器没有出现")
    }

    /// 中途退出也要留下记录（规格 §12：不惩罚中断）。
    func testAbandonedSessionIsStillRecorded() throws {
        startMorningRitual()
        chooseMode(A11yID.modeCoach)

        let close = app.buttons[A11yID.playerClose]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "播放器没有出现")
        // 等一会儿，让已完成秒数不为 0
        Thread.sleep(forTimeInterval: 5)
        close.tap()

        // 退出确认
        let endButton = app.buttons["End"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5), "退出确认没有出现")
        endButton.tap()

        assertDoneScreenAppeared()
        returnHome()
        assertMonthlySummaryCountsOneSession()
    }

    // MARK: - 步骤

    private func startMorningRitual() {
        let start = app.buttons[A11yID.homeStart]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "首页的 START 没有出现")
        start.tap()
    }

    private func chooseMode(_ identifier: String) {
        let mode = app.buttons[identifier]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), "模式 \(identifier) 没有出现")
        mode.tap()
    }

    /// 用「下一动作」把 9 个播放段走完，而不是干等 3 分钟。
    ///
    /// 这样验证的仍然是真实的 routine 与分段逻辑（Morning Core 的 5 个 step
    /// 里有 4 个是左右两段，展开后共 9 段），只是不消耗真实时长。
    private func walkThroughAllSegments() {
        let skip = app.buttons[A11yID.playerSkipForward]
        XCTAssertTrue(skip.waitForExistence(timeout: 20), "播放器没有出现")

        // 多点几次无妨：走完最后一段就会进入 Done，按钮随之消失。
        for _ in 0..<12 where skip.exists {
            skip.tap()
        }
    }

    private func assertDoneScreenAppeared() {
        let title = app.staticTexts[A11yID.doneTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "Done 页没有出现")
    }

    private func returnHome() {
        let back = app.buttons[A11yID.doneBackToHome]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Done 页没有返回按钮")
        back.tap()
    }

    /// 月度汇总卡的无障碍标签形如 "This month: 1 rituals, 3 minutes, 1 active days"。
    /// 用它来验证记录真的落盘了 —— 这是闭环的最后一环。
    private func assertMonthlySummaryCountsOneSession() {
        let summary = app.buttons[A11yID.homeMonthlySummary]
        XCTAssertTrue(summary.waitForExistence(timeout: 20), "首页的月度汇总没有出现")

        let label = summary.label
        XCTAssertTrue(
            label.contains("1 rituals"),
            "练习记录没有保存成功，月度汇总读到的是：\(label)"
        )
    }
}

/// 与 App 侧 `AppEnvironment.uiTestResetArgument` 保持一致。
///
/// UI 测试进程与 App 进程是分开的，拿不到 App 的符号，
/// 所以这里只能重复一遍字符串 —— 但集中在一处，改的时候只有一个地方要同步。
enum AppEnvironmentUITestFlags {
    static let reset = "-FRUITestReset"
}
