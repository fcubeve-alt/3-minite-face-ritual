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

    // MARK: - ⚠️ 免责与安全（草稿，待 Owner + 法务确认）
    //
    // 措辞原则，改动时请守住：
    // 1. 只说「不是什么」，不说「有什么用」—— 规格 §4/§13 禁止任何功效、抗衰、
    //    穴位疗效或「年轻 X 岁」类表述。
    // 2. 不写具体禁忌（哪种皮肤病不能做、按多大力）—— 那是 Owner + 专业人员的事（规格 §20），
    //    这里只做「有疑问就去问专业人士」的转介。
    // 3. 提到眼周与颈部是因为规格 §14 自己点了这两处需要安全限制，
    //    这是指出敏感区域，不是规定手法。

    /// 短版：设置页与 Paywall 页脚。
    static let medicalDisclaimer =
        "Face Ritual is a self-care routine guide, not a medical service. "
        + "It doesn't diagnose or treat anything, and makes no promises about how your face will look."

    /// 长版：Settings → About & Safety 里完整展示。
    ///
    /// 短版塞不下的部分放这里 —— 免责声明缩成一行小字既没人看，也保护不了任何人。
    static let safetyAndDisclaimerBody = """
        Face Ritual guides you through short facial care routines. \
        It is not a medical device and does not provide medical advice.

        The app does not diagnose, treat, cure, or prevent any condition, \
        and makes no claim about changes to your appearance.

        Use a light touch, and stop if anything hurts. \
        The skin around the eyes and the front of the neck are sensitive areas.

        If you have a skin or health condition, have recently had an injury or \
        procedure on your face, or are unsure whether these movements are right for you, \
        check with a qualified professional before you start.

        Face Ritual is not a substitute for professional care.
        """

    static let safetyScreenTitle = "About & Safety"

    // MARK: - Home（规格 §5.1）

    static let greetingMorning = "Good morning"
    static let greetingEvening = "Good evening"
    /// 规格 §21 的一句话定位。
    static let homeTagline = "Follow the coach. Mirror on your face. Done."
    static let start = "START"
    static let quickRituals = "Quick Rituals"
    /// 次级列表现在同时装 Evening Ritual 与 Quick Rituals，
    /// 所以标题不能再叫 "Quick Rituals"。
    static let moreRituals = "More rituals"
    /// 跟练形态的一句话说明。取代了原来的「AR Mirror guidance available」——
    /// AR 于 2026-09-07 砍掉。
    static let followAlongAvailable = "Follow along with the video, mirror optional"

    // MARK: - Follow-along player（2026-09-07 起的主形态）

    /// 示范视频还没到位时显示。刻意说「素材还没上」而不是报错 ——
    /// 这一段本来就能照常做完，只是暂时看的是示意图形。
    static let coachVideoPending = "Demo video coming soon"
    static let mirrorTitle = "You"
    static let coachTitle = "Follow along"
    /// 摄像头是可选的：不开也能做完整套。
    static let mirrorOptionalNote = "The mirror is optional. You can follow along without it."
    static let mirrorDeniedNote = "Camera access is off. You can still follow along — turn it on in Settings if you want to see yourself."
    static let mirrorUnavailableNote = "No front camera on this device."
    static let mirrorEnable = "Turn on the mirror"
    static let mirrorToggleOn = "Show me"
    static let mirrorToggleOff = "Hide me"
    static let a11yMirrorPreview = "Your camera, shown as a mirror"

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

    /// ⚠️ 必须与 `project.yml` 里的 `NSCameraUsageDescription` 语义一致 ——
    /// 两处说法不一样，审核会当成误导。
    ///
    /// 「画面留在设备上」这句是**经代码验证的事实**，不是营销话术：
    /// 整个工程没有任何联网 API（唯一的出网 import 是 StoreKit，只走支付），
    /// 唯一的写盘是本地练习记录。`check_architecture.py` 有一条规则锁住这个前提 ——
    /// 谁哪天加了网络请求，检查会直接失败并指回这句文案。
    static let cameraNeededMessage =
        "AR Mirror needs the front camera to draw the movement path on your own face. "
        + "The video stays on your device — nothing is recorded or sent anywhere. "
        + "You can also keep going with Coach mode, which never uses the camera."
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

    /// ⚠️ 规格 §6.3：定位是 ritual preview / guided awareness / visual relaxation，
    /// **明确不得宣称「看了等于做了」**，也不得宣称获得实际按摩的机械刺激效果。
    ///
    /// 第一句必须是无歧义的否定，且要放在最前面 —— 用户可能只读第一行。
    /// 后半句给出这个模式真正的价值（学路线 + 放松片刻），
    /// 这样既不夸大也不显得是在劝退。措辞不要往「等同」的方向松动。
    static let watchModeDisclaimer =
        "Watching isn't the same as doing. "
        + "Following the path with your eyes is a way to learn it — and to take a slow minute for yourself."

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

    /// ⚠️ 当前构建用的占位提示。规格 §11 的 $4.99/月是「待测试」的工作价格。
    ///
    /// 上线前这条要被下面的 `subscriptionDisclosure` 替换掉 ——
    /// 它只是在提醒「现在看到的数字不作数」，不是合规披露。
    static let pricePlaceholderNotice =
        "Pricing here is a placeholder for testing. Final pricing, the annual plan "
        + "and subscription terms are set before launch."

    /// ⚠️ 上线必备：App Store 审核指南 3.1.2 要求 Paywall 上必须写清这几项，
    /// 少一项就会被拒。这是**模板**，价格与周期由 StoreKit 返回值填入。
    ///
    /// 除了这段文字，Paywall 上还必须有两个**可点击**的链接：
    /// Terms of Use (EULA) 与 Privacy Policy —— 两个 URL 都是 Owner 待提供项（规格 §19）。
    /// 缺链接同样会被拒，所以 `PaywallView` 里留了位置但暂时指向占位。
    static func subscriptionDisclosure(price: String, period: String) -> String {
        """
        \(price) per \(period), billed to your Apple ID at confirmation of purchase.

        The subscription renews automatically unless you turn off auto-renew at least \
        24 hours before the end of the current period. Your account is charged for renewal \
        within 24 hours before the period ends.

        You can manage or cancel your subscription in your Apple ID account settings.
        """
    }

    static let termsOfUse = "Terms of Use"
    static let privacyPolicy = "Privacy Policy"

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
