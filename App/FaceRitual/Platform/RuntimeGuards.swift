import AVFoundation
import UIKit

// MARK: - 屏幕常亮

/// 练习期间阻止自动锁屏。
///
/// 这不是锦上添花：Morning Core 是 3 分钟，Evening Core 是 5 分钟，
/// 而用户全程双手在脸上、**不会碰屏幕**。默认的自动锁屏会在动作做到一半时黑屏，
/// 整个 routine 就断了。
///
/// 用引用计数而不是直接置标志位：AR 与 Coach 可能先后持有，
/// 谁先释放都不该把还在播放的那个也一起解掉。
final class ScreenWakeLock {

    static let shared = ScreenWakeLock()

    private var holders = 0

    private init() {}

    func acquire() {
        holders += 1
        apply()
    }

    func release() {
        holders = max(0, holders - 1)
        apply()
    }

    /// 应用进入后台时无条件放开 —— 后台持有没有意义，也可能被系统清掉。
    func releaseAll() {
        holders = 0
        apply()
    }

    private func apply() {
        UIApplication.shared.isIdleTimerDisabled = holders > 0
    }
}

// MARK: - 音频会话

/// 语音提示的音频会话策略。
///
/// 默认行为会把用户正在放的音乐**整个掐掉** —— 而「一边听自己的歌一边做 3 分钟护理」
/// 恰恰是这个产品最可能的使用场景（规格 §4：低摩擦）。
///
/// 所以：说话时把别人的音量压低（duck），说完立刻还回去。
enum VoiceAudioSession {

    private static var isActive = false

    /// 开始说话前调用。
    static func begin() {
        guard isActive == false else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback + .duckOthers：静音键打开时也能听见提示，
            // 同时把背景音乐压低而不是停掉。
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true)
            isActive = true
        } catch {
            // 配置失败不该让语音功能整个失效 —— 顶多是没有 duck 效果。
            isActive = false
        }
    }

    /// 说完后调用，把音量还给别的 App。
    static func end() {
        guard isActive else { return }
        isActive = false
        // 放到后台线程：setActive(false) 可能阻塞，不能卡住播放器的主循环。
        DispatchQueue.global(qos: .utility).async {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        }
    }
}
