import SwiftUI
import FaceRitualCore

/// 极简视觉基调 —— 规格 §4「极简：打开后尽快进入练习」。
/// 品牌视觉是 Owner 待决策项（规格 §19），所以这里只定义中性、可整体替换的一层。
enum Theme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let surfaceElevated = Color(red: 0.16, green: 0.17, blue: 0.21)
    static let accent = Color(red: 0.55, green: 0.80, blue: 0.95)
    static let accentWarm = Color(red: 1.00, green: 0.76, blue: 0.52)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.30)

    static let cornerRadius: CGFloat = 20
}

/// 内容未经专业审核的角标。
///
/// 这个组件的存在是**产品安全措施**，不是装饰：
/// M1 的全部动作与位置都是 Mock，必须在界面上一眼可见，
/// 绝不能让测试内容看起来像正式的护理指导。
struct MockContentBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 9 : 10, weight: .bold))
            Text(compact ? AppCopy.mockBadgeShort : AppCopy.mockBadgeFull)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Theme.warning.opacity(0.14), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct CardBackground: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(elevated ? Theme.surfaceElevated : Theme.surface)
            )
    }
}

extension View {
    func cardBackground(elevated: Bool = false) -> some View {
        modifier(CardBackground(elevated: elevated))
    }
}

/// 圆形进度环。倒计时与整体进度都用它。
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 4
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamp(progress, 0, 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
    }
}

extension BodySide {
    /// 屏幕上的短标签。
    var shortLabel: String? {
        switch self {
        case .left: return "LEFT"
        case .right: return "RIGHT"
        case .both: return "BOTH"
        case .none, .leftThenRight: return nil
        }
    }
}

extension GuidanceHint {
    /// 提示文案。刻意都是**中性引导**，不含任何「你做错了」的意味（规格 §10）。
    var message: String? {
        switch self {
        case .none: return nil
        case .faceNotFound: return "Looking for your face"
        case .moveCloser: return "Move a little closer"
        case .moveFurther: return "Move back a little"
        case .centerFace: return "Center your face in the frame"
        case .reduceHeadTurn: return "Face the screen"
        case .handCoveringFace: return "Guide is holding position"
        case .holdStill: return "Hold steady for a moment"
        }
    }
}

extension PracticeMode {
    var displayName: String {
        switch self {
        case .coach: return "Coach"
        case .arMirror: return "AR Mirror"
        case .watch: return "Watch & Breathe"
        }
    }

    var subtitle: String {
        switch self {
        case .coach: return AppCopy.coachModeSubtitle
        case .arMirror: return AppCopy.arMirrorModeSubtitle
        case .watch: return AppCopy.watchModeSubtitle
        }
    }

    var iconName: String {
        switch self {
        case .coach: return "play.rectangle.fill"
        case .arMirror: return "faceid"
        case .watch: return "eye.fill"
        }
    }
}

/// 左右侧的配色。
///
/// 让「现在做哪一侧」不用读文字就能看出来 —— 播放器顶部的进度条与
/// 示意动画都用它。
///
/// 原本定义在 AROverlayRenderer 里，那个文件随 AR Mirror 一起删了；
/// 但这套配色和 AR 无关，是跟练播放器仍在用的东西，所以搬到设计系统里。
enum OverlayPalette {
    static func accent(for side: BodySide) -> Color {
        switch side {
        case .left: return Color(red: 0.45, green: 0.83, blue: 0.98)
        case .right: return Color(red: 1.00, green: 0.72, blue: 0.42)
        case .both, .none, .leftThenRight: return Color(red: 0.72, green: 0.85, blue: 1.00)
        }
    }
}
