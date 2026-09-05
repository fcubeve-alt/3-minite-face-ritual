import SwiftUI
import FaceRitualCore

/// Coach 模式（规格 §6.1）。不使用摄像头。
///
/// M1 用**占位素材**：正式 Virtual Coach 视频还没有，
/// 但这不该阻塞系统联调 —— 所以这里画一个由同一份 MovementSpec 驱动的
/// 示意动画，等真实视频到位后换掉 `CoachStageView` 的实现即可。
struct CoachPlayerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: RoutineSessionViewModel

    @State private var showExitConfirm = false
    @State private var showDone = false

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

                CoachStageView(
                    segment: viewModel.currentSegment,
                    cyclePhase: viewModel.segmentProgress
                )
                .frame(maxHeight: .infinity)

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
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.abandon() }
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
                        placeholderNotice(assetName: segment.step.mediaAsset)
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

    private func placeholderNotice(assetName: String?) -> some View {
        VStack(spacing: 4) {
            Text("COACH PLACEHOLDER")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            if let assetName {
                Text(assetName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary.opacity(0.7))
            }
        }
    }
}

/// 抽象脸部示意图 —— 用与 AR 相同的 MovementSpec 画出起点、终点和方向。
///
/// 这里用的是一张**标准比例的示意脸**，不是用户自己的脸；
/// 它的作用是「第一次学动作」（规格 §6.1），精确定位交给 AR Mirror。
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
