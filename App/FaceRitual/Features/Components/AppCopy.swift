import Foundation

/// 全部**用户可见**文案集中在这里。
///
/// 两个原因：
///
/// 1. 目标用户是欧美用户（规格 §3），主流程要用易理解的动作语言（规格 §14）。
///    散在各个视图里的中文提示对他们没有意义。
///
/// 2. 规格 §19 把「最终文案、免责声明、摄像头权限说明、订阅条款」列为 Owner 待办。
///    集中在一个文件里，Owner 与法务改一处就够，不必翻遍 UI 代码。
///
/// **不在这里的**：Settings → Developer、Diagnostics、ARKit 标定这些开发面，
/// 只有团队自己看，保留中文更省事。
///
/// 标了 ⚠️ 的条目上线前需要 Owner 或法务确认。
enum AppCopy {

    // MARK: - 通用

    static let cancel = "Cancel"
    static let close = "Close"
    static let openSettings = "Open Settings"

    /// ⚠️ 医学免责声明 —— 规格 §4「不做医学承诺」。上线前需法务确认。
    static let medicalDisclaimer =
        "This app offers everyday self-care guidance. "
        + "It is not a medical diagnosis, treatment advice, or a promise of results."

    // MARK: - Home（规格 §5.1）

    static let greetingMorning = "Good morning"
    static let greetingEvening = "Good evening"
    /// 规格 §21 的一句话定位。
    static let homeTagline = "Follow the coach. Mirror on your face. Done."
    static let start = "START"
    static let quickRituals = "Quick Rituals"
    static let arGuidanceAvailable = "AR Mirror guidance available"

    static let statRituals = "rituals"
    static let statMinutes = "minutes"
    static let statDays = "days"

    /// M1 期间必须让用户一眼看出内容不是正式的。正式内容替换后这条会随角标一起消失。
    static let mockContentNotice =
        "Every movement and face position in this build is placeholder test data, "
        + "used only to validate the app. Real content will be selected and reviewed "
        + "by the owner and qualified professionals."
    static let mockBadgeFull = "MOCK CONTENT · not reviewed"
    static let mockBadgeShort = "MOCK"

    // MARK: - Routine 详情与模式选择（规格 §6）

    static let howToPractice = "How do you want to practice?"
    static let inThisRitual = "In this ritual"
    static let experimentalTag = "Experimental"

    static let coachModeSubtitle = "Watch a demonstration. No camera."
    static let arMirrorModeSubtitle = "See the spot, path and direction on your own face."
    static let watchModeSubtitle = "Just watch the path animation. No hands needed."

    // MARK: - 摄像头（规格 §4：用户主动开启，可随时关闭）

    static let cameraNeededTitle = "Camera access needed"
    /// ⚠️ 与 Info.plist 的 NSCameraUsageDescription 语义要一致。上线前需 Owner 确认。
    static let cameraNeededMessage =
        "AR Mirror uses the front camera to show movement paths on your own face. "
        + "You can also continue with Coach mode, which never uses the camera."
    static let useCoachInstead = "Use Coach instead"

    // MARK: - 播放器

    static let getReady = "Get ready"
    static let exitTitle = "End this session?"
    /// 规格 §12：不惩罚中断。
    static let exitMessage = "What you've done so far will be saved."
    static let keepPracticing = "Keep practicing"
    static let endSession = "End"

    // MARK: - AR Mirror

    static let watchModeTitle = "Just watch and breathe."
    /// ⚠️ 规格 §6.3 明确不得宣称「看了等于做了」。这句话的措辞不能随意放宽。
    static let watchModeDisclaimer =
        "This is movement preview and visual relaxation. "
        + "It is not the same as actually doing the massage."

    /// 规格 §4：识别失败不得阻塞 routine —— 所以这是建议，不是拦截。
    static let arFallbackPrompt = "The lighting or angle here may not suit AR."
    static let arFallbackAction = "Switch to Coach — the timer keeps running"
    static let arFellBackNotice = "Switched to Coach. This session still counts."

    /// AR 出错时给用户的**中性**说明。
    ///
    /// 刻意不透出底层错误（「缺少 HRFFA.mlmodelc」这种）——
    /// 那些是给我们自己看的，用户看了既不理解也做不了什么。
    /// 技术细节只在 Debug 图层打开时显示。
    static let arUnavailable = "AR guidance isn't available right now."

    // MARK: - 购买

    /// 同理：不把 StoreKit 的原始错误摊给用户。
    static let purchaseFailed = "The purchase couldn't be completed. Please try again."

    // MARK: - 完成

    static let doneTitle = "Done."
    static let savedTitle = "Saved."
    static let backToHome = "Back to home"
    static let thisMonthShort = "this month"

    // MARK: - 记录（规格 §12：不制造断签焦虑）

    static let historyTitle = "History"
    static let thisMonth = "This month"
    static let recent = "Recent"
    static let activeDays = "active days"
    static let dayStreak = "day streak"
    static let partialSession = "partial"
    static let historyEmptyTitle = "No sessions yet"
    static let historyEmptyBody = "Finish a ritual and it will show up here."

    // MARK: - 设置

    static let settingsTitle = "Settings"
    static let sectionPractice = "Practice"
    static let voiceCues = "Voice cues"
    static let haptics = "Haptics"

    static let sectionReminders = "Reminders"
    /// 规格 §12：提醒文案避免焦虑与羞耻感。
    static let remindersFooter =
        "Reminders are a gentle nudge to look after yourself. Missing one costs you nothing."
    static let reminderTime = "Time"

    static let sectionSubscription = "Subscription"
    static let subscriptionStatus = "Status"
    static let statusPremium = "Premium"
    static let statusFree = "Free"

    static let sectionCamera = "Camera"
    static let cameraPermission = "Camera permission"
    static let manageInSystemSettings = "Manage in system settings"
    static let mirrorPreview = "Mirror the preview"
    static let cameraFooter =
        "The camera turns on only when you open AR Mirror, and you can close it any time. "
        + "Coach mode never uses the camera."

    static let permissionAllowed = "Allowed"
    static let permissionDenied = "Denied"
    static let permissionRestricted = "Restricted"
    static let permissionNotAsked = "Not asked"

    static let sectionAbout = "About"
    static let contentVersion = "Content version"
    static let clearHistory = "Clear practice history"
    static let clearHistoryTitle = "Clear all practice records?"
    static let clearHistoryMessage = "This cannot be undone."
    static let clearHistoryConfirm = "Clear"

    // MARK: - Paywall（规格 §11）

    static let premium = "Premium"
    static let restore = "Restore"
    static let morningIsFreeForever = "Morning Ritual is free forever"
    static let premiumUnlocks = "Premium unlocks the Evening Ritual and all Quick Rituals."

    static let benefitMorningTitle = "Morning Core"
    static let benefitMorningSubtitle = "Included for free users, forever"
    static let benefitEveningTitle = "Evening Ritual"
    static let benefitEveningSubtitle = "About five minutes to wind down"
    static let benefitQuickTitle = "All Quick Rituals"
    static let benefitQuickSubtitle = "De-Puff · Tired Eyes and more"
    static let benefitARTitle = "AR Mirror in every ritual"
    static let benefitARSubtitle = "Free users can already try it in Morning Core"

    /// ⚠️ 规格 §11 的价格是「待测试」的工作价格。上线前必须由 Owner 敲定。
    static let pricePlaceholderNotice =
        "Prices shown are placeholders for testing. Final pricing, the annual plan "
        + "and subscription terms are confirmed before launch."

    // MARK: - 无障碍
    //
    // 播放器全是纯图标按钮。不给标签的话 VoiceOver 只会念「按钮」，
    // 用户根本无法操作 —— 这不是加分项，是能不能用的问题。

    static let a11yClose = "Close"
    static let a11yPause = "Pause"
    static let a11yResume = "Resume"
    static let a11yPreviousMove = "Previous move"
    static let a11yNextMove = "Next move"
    static let a11ySettings = "Settings"
    /// 参数：剩余秒数、总动作数里的第几个。
    static func a11yTimeRemaining(seconds: Int) -> String {
        "\(seconds) seconds left in this move"
    }

    static func a11yProgress(current: Int, total: Int) -> String {
        "Move \(current) of \(total)"
    }

    /// AR overlay 是纯视觉的，对 VoiceOver 没有意义 —— 整体隐藏，
    /// 由语音提示（voiceCue）承担同样的信息。
    static let a11yCameraPreview = "Camera preview with movement guidance"

    /// 月度汇总卡是一个包着多段文字的按钮。
    /// 不合成一条的话 VoiceOver 会念成「3、rituals、9、minutes…」这种碎片。
    static func a11yMonthlySummary(rituals: Int, minutes: Int, days: Int) -> String {
        "This month: \(rituals) rituals, \(minutes) minutes, \(days) active days"
    }

    static let a11yOpensHistory = "Opens your practice history"

    // MARK: - 内容加载失败（正常情况下用户看不到）

    static let contentUnavailableTitle = "Content could not be loaded"
    static let contentUnavailableBody =
        "Check routines.json / anchors.json / content_meta.json under Resources."
}
