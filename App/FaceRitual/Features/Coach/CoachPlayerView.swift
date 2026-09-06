import SwiftUI
import FaceRitualCore

/// 跟练播放器 —— **上面老师做，下面你跟着做**。
///
/// 2026-09-07 产品方向调整之后，这是唯一的练习形态。
/// 之前还有 AR Mirror（把路线贴在脸上）和 Watch & Breathe，
/// 实测下来路线贴不稳，而"贴不准的指引没有意义"，所以砍掉了。
///
/// 现在的分工干净得多：
///   上半屏 = 示范视频（素材没到位时回落到示意动画，流程不断）
///   下半屏 = 纯镜像，**不做任何人脸识别**
///
/// 下半屏只要回答"我做的像不像"，那只需要一面镜子。
/// 没有跟踪就没有漂移、没有丢锁、没有降级策略 —— 一整类问题从需求上消失了。
/// 摄像头因此是**可选**的：不开也能跟着视频做完整套。
struct CoachPlayerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: RoutineSessionViewModel

    @State private var showExitConfirm = false
    @State private var showDone = false

    @StateObject private var mirror = MirrorPreviewController()
    /// 镜像默认开着 —— 跟练时看不到自己就少了一半意义。
    /// 但它必须能关：有人不想在早上看见自己的脸，那也完全能把 routine 做完。
    @AppStorage("player.showMirror") private var showMirror = true

    /// autoclosure：`@StateObject` 只在首次构建时求值，重绘不会重复建 view model。
    init(viewModel: @autoclosure @escaping () -> RoutineSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                PlayerHeader(viewModel: viewModel) { showExitConfirm = true }
                    .padding(.top, 8)

                followAlongStage

                PlayerControls(viewModel: viewModel)
            }

            if let remaining = viewModel.prepareCountdown {
                PrepareCountdownOverlay(remaining: remaining)
            }
        }
        .modifier(ExitConfirmationModifier(isPresented: $showExitConfirm) {
            viewModel.abandon()
            showDone = true
        })
        .fullScreenCover(isPresented: $showDone, onDismiss: { dismiss() }) {
            DoneView(session: viewModel.completedSession, routine: viewModel.routine)
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            if finished { showDone = true }
        }
        .onAppear {
            viewModel.start()
            if showMirror { mirror.start() }
        }
        .onDisappear {
            mirror.stop()
            viewModel.abandon()
        }
        .onChange(of: showMirror) { _, wanted in
            wanted ? mirror.start() : mirror.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.handleReturnedToForeground(viewSize: .zero)
            case .inactive, .background:
                viewModel.handleEnteredBackground()
            @unknown default:
                break
            }
        }
        .statusBarHidden()
    }
}

private extension CoachPlayerView {

    /// 上下分屏。上半屏给老师，下半屏给你。
    ///
    /// 6:4 而不是对半：示范画面需要看清手指位置，比自己的镜像更需要面积。
    /// 关掉镜像时上半屏自然占满，不留空洞。
    var followAlongStage: some View {
        GeometryReader { proxy in
            VStack(spacing: 10) {
                labelled(AppCopy.coachTitle) {
                    CoachVideoStage(
                        segment: viewModel.currentSegment,
                        cyclePhase: viewModel.segmentProgress
                    )
                }
                .frame(height: showMirror ? proxy.size.height * 0.58 : proxy.size.height)

                if showMirror {
                    labelled(AppCopy.mirrorTitle) { mirrorStage }
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if title == AppCopy.mirrorTitle {
                    Button(showMirror ? AppCopy.mirrorToggleOff : AppCopy.mirrorToggleOn) {
                        showMirror.toggle()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityIdentifier(A11yID.playerMirrorToggle)
                }
            }
            content()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    /// 镜像区。摄像头拿不到时给一句人话，而不是黑屏或报错 ——
    /// 这一段本来就是可选的。
    @ViewBuilder
    var mirrorStage: some View {
        ZStack {
            Color.black
            switch mirror.state {
            case .running:
                MirrorPreviewRepresentable(controller: mirror)
                    .accessibilityLabel(AppCopy.a11yMirrorPreview)
            case .needsPermission:
                // 只有点了这个按钮才会弹系统权限框。
                VStack(spacing: 10) {
                    mirrorNotice(AppCopy.mirrorOptionalNote)
                    Button(AppCopy.mirrorEnable) { mirror.requestAccess() }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.horizontal, 40)
                        .accessibilityIdentifier(A11yID.playerMirrorEnable)
                }
            case .denied:
                mirrorNotice(AppCopy.mirrorDeniedNote)
            case .unavailable:
                mirrorNotice(AppCopy.mirrorUnavailableNote)
            case .idle:
                mirrorNotice(AppCopy.mirrorOptionalNote)
            }
        }
    }

    func mirrorNotice(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 24)
    }
}

/// Coach 的画面区。
///
/// 当前是占位实现：用一个抽象的脸部轮廓 + 同一份 MovementSpec 驱动的方向示意。
/// **它与 AR overlay 读的是同一个 `movement`** —— 规格 §4「一个动作真源」，
/// 所以不会出现「老师往上、脸上路线往下」的矛盾。
struct CoachStageView: View {
    let segment: PlaybackSegment?
    let cyclePhase: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.surface)

                if let segment {
                    VStack(spacing: 20) {
                        CoachSchematic(
                            movement: segment.resolvedMovement,
                            side: segment.side,
                            phase: cyclePhase
                        )
                        .frame(width: min(proxy.size.width * 0.62, 260))
                        .frame(height: min(proxy.size.width * 0.62, 260) * 1.25)

                        if let note = segment.step.safetyNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

}

/// 抽象脸部示意图 —— 由 MovementSpec 画出起点、终点和方向。
///
/// 用的是一张**标准比例的示意脸**，不是用户自己的脸。
/// 它现在的角色是**示范视频未到位时的回落**：动作的几何本来就在数据里，
/// 素材还没补齐之前先用它把流程撑住，视频放进 bundle 就自动换成视频。
private struct CoachSchematic: View {
    let movement: MovementSpec
    let side: BodySide
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let accent = OverlayPalette.accent(for: side)
            let faceRect = CGRect(
                x: size.width * 0.12,
                y: size.height * 0.06,
                width: size.width * 0.76,
                height: size.height * 0.88
            )

            // 脸廓
            context.stroke(
                Path(ellipseIn: faceRect),
                with: .color(Theme.textTertiary.opacity(0.5)),
                lineWidth: 1.5
            )
            // 双眼
            let eyeY = faceRect.minY + faceRect.height * 0.36
            for dx in [-0.19, 0.19] {
                let center = CGPoint(x: faceRect.midX + faceRect.width * dx, y: eyeY)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 2.5, width: 8, height: 5)),
                    with: .color(Theme.textTertiary.opacity(0.6))
                )
            }

            // 用示意脸构造一个 FaceFrame，然后走与 AR 完全相同的 PathSampler。
            let interocular = faceRect.width * 0.38
            let frame = FaceFrame(
                origin: Point2D(x: Double(faceRect.midX), y: Double(eyeY)),
                xAxis: Vector2D(dx: 1, dy: 0),
                yAxis: Vector2D(dx: 0, dy: 1),
                scale: Double(interocular)
            )

            guard let start = CoachSchematic.schematicPoint(for: movement.startAnchorID, frame: frame) else { return }
            let end = CoachSchematic.schematicPoint(for: movement.endAnchorID, frame: frame)

            let path = PathSampler().makePath(movement: movement, start: start, end: end, frame: frame)
            guard path.points.count > 1 else {
                context.fill(
                    Path(ellipseIn: CGRect(x: start.x - 7, y: start.y - 7, width: 14, height: 14)),
                    with: .color(accent)
                )
                return
            }

            var line = Path()
            line.move(to: path.points[0].cgPoint)
            for point in path.points.dropFirst() { line.addLine(to: point.cgPoint) }
            context.stroke(
                line,
                with: .color(accent.opacity(0.55)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 6])
            )

            let dot = path.point(atProgress: phase.truncatingRemainder(dividingBy: 1.0)).cgPoint
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(.white))
            context.fill(
                Path(ellipseIn: CGRect(x: path.start.x - 6, y: path.start.y - 6, width: 12, height: 12)),
                with: .color(accent)
            )
            if let last = path.points.last {
                context.stroke(
                    Path(ellipseIn: CGRect(x: last.x - 9, y: last.y - 9, width: 18, height: 18)),
                    with: .color(accent),
                    lineWidth: 2.5
                )
            }
        }
    }

    /// 示意脸上的 anchor 近似位置（脸部局部坐标，单位=瞳距）。
    ///
    /// 这只是 Coach 示意用的粗略布局，**不是** anchors.json 的定义 ——
    /// 真实定位一律由 AR Mirror 按用户自己的 Face Geometry 计算。
    private static let schematicAnchors: [String: Point2D] = [
        "glabella_center": Point2D(x: 0.00, y: -0.28),
        "brow_inner_left": Point2D(x: -0.22, y: -0.32),
        "brow_inner_right": Point2D(x: 0.22, y: -0.32),
        "temple_left": Point2D(x: -1.08, y: -0.08),
        "temple_right": Point2D(x: 1.08, y: -0.08),
        "cheek_mid_left": Point2D(x: -0.72, y: 0.55),
        "cheek_mid_right": Point2D(x: 0.72, y: 0.55),
        "jaw_angle_left": Point2D(x: -0.64, y: 1.39),
        "jaw_angle_right": Point2D(x: 0.64, y: 1.39)
    ]

    static func schematicPoint(for id: FaceAnchorID?, frame: FaceFrame) -> Point2D? {
        guard let id, let local = schematicAnchors[id.rawValue] else { return nil }
        return frame.toView(local: local)
    }
}
