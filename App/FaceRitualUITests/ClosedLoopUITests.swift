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

    /// 摄像头是**可选**的：模拟器上根本没有前置摄像头，
    /// 而整套 routine 必须照样能走完 —— 这正是砍掉 AR 之后最重要的一条性质。
    ///
    /// （原来这里有 testARMirrorCompletesOnSyntheticFace 与 testWatchModeReachesTheEnd，
    /// 随 AR Mirror / Watch & Breathe 于 2026-09-07 一并移除。）
    func testRoutineCompletesWithoutCamera() throws {
        startMorningRitual()
        chooseMode(A11yID.modeCoach)
        walkThroughAllSegments()
        assertDoneScreenAppeared()
    }

    /// 镜像可以关掉，关掉之后播放器仍然正常工作。
    func testMirrorCanBeTurnedOff() throws {
        startMorningRitual()
        chooseMode(A11yID.modeCoach)

        let toggle = waitForHittable(A11yID.playerMirrorToggle, message: "镜像开关没有出现")
        toggle.tap()

        // 关掉镜像之后播放器照常 —— 用跳过按钮确认它还在工作。
        let skip = waitForHittable(A11yID.playerSkipForward, message: "关掉镜像后播放器不见了")
        XCTAssertTrue(skip.isHittable, "关掉镜像不应影响播放控制")
    }

    /// 中途退出也要留下记录（规格 §12：不惩罚中断）。
    func testAbandonedSessionIsStillRecorded() throws {
        startMorningRitual()
        chooseMode(A11yID.modeCoach)

        let close = waitForHittable(A11yID.playerClose, message: "播放器没有出现")
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

    /// 按 identifier 找元素，**不限定类型**。
    ///
    /// 不用 `app.buttons[id]`：SwiftUI 把 `Button` 渲染成什么类型的可访问元素，
    /// 取决于 buttonStyle 和 label 的结构 —— 带自定义内容的 `.plain` 按钮
    /// 有时会落到 `otherElements` 而不是 `buttons`。
    /// 限定类型查询会因此找不到，而报错只说「没出现」，看不出真正原因。
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 找不到元素时，把当前界面的可访问层级作为附件传出去。
    ///
    /// 没有这个的话，CI 上只会得到一句「没出现」，然后就得再跑一轮去猜 ——
    /// 而 macOS runner 的每一轮都要花掉可观的额度。
    private func waitFor(
        _ identifier: String,
        timeout: TimeInterval = 20,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let target = element(identifier)
        if target.waitForExistence(timeout: timeout) == false {
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "界面层级-\(identifier)"
            dump.lifetime = .keepAlways
            add(dump)

            XCTFail(
                "\(message)（identifier: \(identifier)）。当前界面层级已作为附件附上，"
                + "前 2000 字符：\n\(String(app.debugDescription.prefix(2000)))",
                file: file,
                line: line
            )
        }
        return target
    }

    /// 等元素**可点**，而不只是「存在」。
    ///
    /// SwiftUI 在视图还在做转场动画时就把元素放进了可访问层级 ——
    /// 那时 `exists` 已经是 true，但点下去是空的（或者更糟：点在了动画中间态上，
    /// 于是嵌套的 fullScreenCover 因为「上一个转场还没结束」被丢弃）。
    ///
    /// 本机上动画只有 0.3 秒左右，几乎撞不到；CI 的模拟器动画慢得多，
    /// 窗口能有一两秒 —— 所以这类竞态**只会在 CI 上偶发**，最难查。
    /// 2026-09-06 的 run 34035131613 就是这么挂的：三个测试过、一个卡在首页。
    @discardableResult
    private func waitForHittable(
        _ identifier: String,
        timeout: TimeInterval = 20,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let target = waitFor(identifier, timeout: timeout, message: message, file: file, line: line)
        guard target.exists else { return target }

        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: target
        )
        if XCTWaiter().wait(for: [hittable], timeout: timeout) != .completed {
            XCTFail(
                "\(message)：元素出现了但一直不可点（identifier: \(identifier)）。"
                + "多半是转场动画没结束，或者被别的视图盖住了。",
                file: file,
                line: line
            )
        }
        return target
    }

    private func startMorningRitual() {
        waitForHittable(A11yID.homeStart, message: "首页的 START 没有出现").tap()
    }

    private func chooseMode(_ identifier: String) {
        // 必须等可点：这一行在外层 fullScreenCover 的入场动画期间就已经「存在」了，
        // 那时候点它，内层 fullScreenCover（播放器）会因为
        // 「上一个转场还在进行」而被 UIKit 丢掉 —— 表现就是停在原地什么也没发生。
        waitForHittable(identifier, message: "模式选择行没有出现").tap()
    }

    /// 用「下一动作」把 9 个播放段走完，而不是干等 3 分钟。
    ///
    /// 这样验证的仍然是真实的 routine 与分段逻辑（Morning Core 的 5 个 step
    /// 里有 4 个是左右两段，展开后共 9 段），只是不消耗真实时长。
    private func walkThroughAllSegments() {
        let skip = waitForHittable(A11yID.playerSkipForward, message: "播放器没有出现")
        let doneTitle = element(A11yID.doneTitle)

        // 不能用 `skip.exists` 当循环条件：
        // routine 走完后 Done 页以 fullScreenCover 盖上来，播放器界面还在它下面，
        // 元素依然「存在」但已经点不到了 —— XCUITest 会尝试把它滚动到可见处，
        // 然后报 "Failed to scroll to visible"。
        // 所以改成：Done 一出现就停，并用 isHittable 而不是 exists。
        for _ in 0..<15 {
            if doneTitle.exists { return }
            guard skip.isHittable else { return }
            skip.tap()
        }
    }

    private func assertDoneScreenAppeared() {
        _ = waitFor(A11yID.doneTitle, message: "Done 页没有出现")
    }

    private func returnHome() {
        waitForHittable(A11yID.doneBackToHome, message: "Done 页没有返回按钮").tap()

        // 断言**真的**回到了首页，而不是「首页的控件恰好还在无障碍树里」。
        //
        // 详情页以前是盖在首页上的 fullScreenCover，首页控件一直留在树里，
        // 于是下面那条月度汇总断言在根本没回到首页时也能通过 ——
        // 而真实用户会被留在详情页，还得再按一次关闭。
        // 改成导航推入之后，用「详情页的控件必须消失」把这条断言变成真的。
        let modeRow = element(A11yID.modeCoach)
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: modeRow
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 10), .completed,
            "返回后仍然停在 routine 详情页 —— 没有真的回到首页"
        )
    }

    /// 月度汇总卡的无障碍标签形如 "This month: 1 rituals, 3 minutes, 1 active days"。
    /// 用它来验证记录真的落盘了 —— 这是闭环的最后一环。
    private func assertMonthlySummaryCountsOneSession() {
        let summary = waitFor(A11yID.homeMonthlySummary, message: "首页的月度汇总没有出现")
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
