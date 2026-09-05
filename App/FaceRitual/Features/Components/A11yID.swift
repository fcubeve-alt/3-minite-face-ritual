import Foundation

/// UI 自动化测试用的控件标识。
///
/// 用常量而不是在测试里写字符串字面量：改名时测试会**编译失败**，
/// 而不是在 CI 上静默地找不到控件然后超时。
///
/// 这些 identifier 不影响 VoiceOver（它读的是 accessibilityLabel），
/// 纯粹是给自动化测试定位用的。
enum A11yID {
    static let homeStart = "home.start"
    static let homeQuickRitual = "home.quickRitual"
    static let homeMonthlySummary = "home.monthlySummary"

    static let modeCoach = "mode.coach"
    static let modeARMirror = "mode.arMirror"
    static let modeWatch = "mode.watch"

    static let playerPauseToggle = "player.pauseToggle"
    static let playerSkipForward = "player.skipForward"
    static let playerClose = "player.close"

    static let doneTitle = "done.title"
    static let doneBackToHome = "done.backToHome"

    static func mode(_ raw: String) -> String { "mode.\(raw)" }
}
