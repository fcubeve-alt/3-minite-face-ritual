import SwiftUI
import FaceRitualCore

/// 把 `ARGuidanceFrame` 画到用户自己的脸上。
///
/// 规格 §6.2 要求的全部元素：
///   ● 起点 / ◎ 终点 / 路径（直线·曲线·弧线·圆周）/ 动态方向 / 移动光点
///   / 手势提示 / 节奏 / 左右侧
///
/// 用 SwiftUI `Canvas` 而不是 SceneKit/Metal：
/// 这些都是 2D 屏幕空间图元，Canvas 一次绘制全部搞定，
/// 没有额外的渲染管线、没有和相机预览的层级同步问题，真机调试也简单得多。
struct AROverlayRenderer: View {

    let frame: ARGuidanceFrame
    /// 倒计时、次数、左右侧文字由 `ARMirrorHUD` 负责 ——
    /// 这里只画贴在脸上的东西，两者分开更容易分别调试。
    let showsDebugOverlay: Bool

    var body: some View {
        Canvas { context, size in
            guard frame.overlays.isEmpty == false else { return }

            context.opacity = frame.overlayOpacity

            for overlay in frame.overlays {
                draw(overlay: overlay, in: &context, size: size)
            }

            if showsDebugOverlay {
                drawDebug(in: &context)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: frame.overlayOpacity)
    }

    // MARK: - 单条轨迹

    private func draw(overlay: MotionOverlay, in context: inout GraphicsContext, size: CGSize) {
        let accent = OverlayPalette.accent(for: overlay.side)

        drawPath(overlay: overlay, context: &context, accent: accent)
        drawDirectionArrows(overlay: overlay, context: &context, accent: accent)
        drawEndMarker(overlay: overlay, context: &context, accent: accent)
        drawStartMarker(overlay: overlay, context: &context, accent: accent)
        drawMovingDot(overlay: overlay, context: &context, accent: accent)
        drawGestureHint(overlay: overlay, context: &context, accent: accent)
    }

    /// 路径本体：底层虚线 + 已走过部分的实线拖尾。
    private func drawPath(overlay: MotionOverlay, context: inout GraphicsContext, accent: Color) {
        guard overlay.path.points.count > 1 else { return }

        var path = Path()
        path.move(to: overlay.path.points[0].cgPoint)
        for point in overlay.path.points.dropFirst() {
            path.addLine(to: point.cgPoint)
        }

        // 底层：完整路径，半透明虚线 —— 告诉用户「整条路线长这样」。
        context.stroke(
            path,
            with: .color(accent.opacity(0.35)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [6, 7])
        )

        // 上层：本次循环已走过的部分，实线拖尾 —— 告诉用户「现在走到哪」。
        let trail = trailPath(of: overlay.path, upTo: frame.cyclePhase)
        context.stroke(
            trail,
            with: .linearGradient(
                Gradient(colors: [accent.opacity(0.15), accent]),
                startPoint: overlay.path.start.cgPoint,
                endPoint: overlay.path.point(atProgress: frame.cyclePhase).cgPoint
            ),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        )
    }

    /// 取路径的前 `progress` 段。圆周动作也靠它形成「一圈一圈画出来」的效果。
    private func trailPath(of motionPath: MotionPath, upTo progress: Double) -> Path {
        var path = Path()
        guard motionPath.points.count > 1 else { return path }

        let clamped = clamp(progress, 0, 1)
        // 拖尾保留最近 35% 的路径，太长会糊成一团，太短看不出方向。
        let tailStart = max(0, clamped - 0.35)

        let steps = 48
        path.move(to: motionPath.point(atProgress: tailStart).cgPoint)
        for index in 1...steps {
            let t = tailStart + (clamped - tailStart) * Double(index) / Double(steps)
            path.addLine(to: motionPath.point(atProgress: t).cgPoint)
        }
        return path
    }

    /// 沿路径均匀放几个箭头，指示运动方向。
    /// 规格 §6.2：方向要用**动态箭头 / 移动光点**，不是静态文字。
    private func drawDirectionArrows(overlay: MotionOverlay, context: inout GraphicsContext, accent: Color) {
        guard overlay.path.points.count > 1, overlay.path.totalLength > 24 else { return }

        let arrowCount = overlay.path.kind == .circle ? 4 : 3
        for index in 0..<arrowCount {
            // 让箭头随相位缓慢流动，比静止箭头更容易读出方向。
            let base = (Double(index) + 0.5) / Double(arrowCount)
            let t = (base + frame.cyclePhase * 0.5).truncatingRemainder(dividingBy: 1.0)
            let point = overlay.path.point(atProgress: t)
            let tangent = overlay.path.tangent(atProgress: t)
            context.fill(
                arrowHead(at: point, direction: tangent, size: 9),
                with: .color(accent.opacity(0.7))
            )
        }
    }

    private func arrowHead(at point: Point2D, direction: Vector2D, size: Double) -> Path {
        let unit = direction.normalized
        let normal = unit.rotatedClockwise90
        let tip = point + (unit * size)
        let left = point + (normal * (size * 0.5)) + (unit * (-size * 0.35))
        let right = point + (normal * (-size * 0.5)) + (unit * (-size * 0.35))

        var path = Path()
        path.move(to: tip.cgPoint)
        path.addLine(to: left.cgPoint)
        path.addLine(to: right.cgPoint)
        path.closeSubpath()
        return path
    }

    /// ● 起点：实心圆 + 随节奏脉冲的容差圈。
    private func drawStartMarker(overlay: MotionOverlay, context: inout GraphicsContext, accent: Color) {
        let center = overlay.start.cgPoint

        // 容差圈：这个动作允许的位置范围（anchor.toleranceRadius）。
        // 它表达「大概这一带」，而不是「必须精确命中这一点」。
        let pulse = 0.9 + 0.1 * sin(frame.cyclePhase * 2 * .pi)
        let toleranceRadius = overlay.toleranceRadius * pulse
        context.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - toleranceRadius,
                y: center.y - toleranceRadius,
                width: toleranceRadius * 2,
                height: toleranceRadius * 2
            )),
            with: .color(accent.opacity(0.30)),
            lineWidth: 1.5
        )

        let radius: CGFloat = 9
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(accent)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.white.opacity(0.9)),
            lineWidth: 2
        )
    }

    /// ◎ 终点：双环。press / hold 没有终点，画同心呼吸环表示「停留」。
    private func drawEndMarker(overlay: MotionOverlay, context: inout GraphicsContext, accent: Color) {
        guard let end = overlay.end else {
            drawHoldIndicator(at: overlay.start, context: &context, accent: accent)
            return
        }
        let center = end.cgPoint
        for radius in [CGFloat(12), CGFloat(6)] {
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(radius > 8 ? accent : .white.opacity(0.9)),
                lineWidth: 2.5
            )
        }
    }

    /// hold / press：同心呼吸环，节奏与 tempo 一致。
    private func drawHoldIndicator(at point: Point2D, context: inout GraphicsContext, accent: Color) {
        let center = point.cgPoint
        let phase = frame.cyclePhase
        for index in 0..<2 {
            let offset = (phase + Double(index) * 0.5).truncatingRemainder(dividingBy: 1.0)
            let radius = 12 + offset * 26
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(accent.opacity((1 - offset) * 0.6)),
                lineWidth: 2
            )
        }
    }

    /// 沿路径移动的光点 —— 节奏的主要载体。
    private func drawMovingDot(overlay: MotionOverlay, context: inout GraphicsContext, accent: Color) {
        guard overlay.path.points.count > 1 else { return }
        let point = overlay.path.point(atProgress: frame.cyclePhase).cgPoint

        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)),
            with: .radialGradient(
                Gradient(colors: [accent.opacity(0.45), accent.opacity(0)]),
                center: point,
                startRadius: 0,
                endRadius: 14
            )
        )
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
            with: .color(.white)
        )
    }

    /// 手势提示：单指 / 双指 / 指腹 / 手掌 / 工具。
    /// 用简单图元而不是写实插画 —— 贴在脸上时越简单越不遮挡视线。
    private func drawGestureHint(overlay: MotionOverlay, context: inout GraphicsContext, accent: Color) {
        guard overlay.gesture != .none else { return }

        let anchor = overlay.start.cgPoint
        let origin = CGPoint(x: anchor.x, y: anchor.y - 34)

        switch overlay.gesture {
        case .singleFinger:
            drawFingerDots(count: 1, at: origin, context: &context, accent: accent)
        case .twoFinger:
            drawFingerDots(count: 2, at: origin, context: &context, accent: accent)
        case .fingertips:
            drawFingerDots(count: 3, at: origin, context: &context, accent: accent)
        case .palm:
            let rect = CGRect(x: origin.x - 13, y: origin.y - 9, width: 26, height: 18)
            context.stroke(Path(roundedRect: rect, cornerRadius: 7), with: .color(accent.opacity(0.85)), lineWidth: 2)
        case .tool:
            let rect = CGRect(x: origin.x - 12, y: origin.y - 5, width: 24, height: 10)
            context.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(accent.opacity(0.85)), lineWidth: 2)
            context.stroke(
                Path { $0.move(to: CGPoint(x: origin.x, y: origin.y + 5)); $0.addLine(to: CGPoint(x: origin.x, y: origin.y + 12)) },
                with: .color(accent.opacity(0.85)),
                lineWidth: 2
            )
        case .none:
            break
        }
    }

    private func drawFingerDots(count: Int, at origin: CGPoint, context: inout GraphicsContext, accent: Color) {
        let spacing: CGFloat = 9
        let totalWidth = spacing * CGFloat(count - 1)
        for index in 0..<count {
            let x = origin.x - totalWidth / 2 + spacing * CGFloat(index)
            context.fill(
                Path(ellipseIn: CGRect(x: x - 3.5, y: origin.y - 3.5, width: 7, height: 7)),
                with: .color(accent.opacity(0.9))
            )
        }
    }

    // MARK: - Debug

    private func drawDebug(in context: inout GraphicsContext) {
        for (_, point) in frame.debugLandmarks {
            let rect = CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)
            context.fill(Path(ellipseIn: rect), with: .color(.green.opacity(0.75)))
        }
        guard let faceFrame = frame.debugFrame else { return }

        // 画出脸部坐标系的两条轴 —— 一眼就能看出 roll 是否被正确吸收。
        let origin = faceFrame.origin.cgPoint
        let xEnd = faceFrame.toView(local: Point2D(x: 1, y: 0)).cgPoint
        let yEnd = faceFrame.toView(local: Point2D(x: 0, y: 1)).cgPoint
        context.stroke(
            Path { $0.move(to: origin); $0.addLine(to: xEnd) },
            with: .color(.red.opacity(0.8)),
            lineWidth: 2
        )
        context.stroke(
            Path { $0.move(to: origin); $0.addLine(to: yEnd) },
            with: .color(.blue.opacity(0.8)),
            lineWidth: 2
        )
    }
}

enum OverlayPalette {
    /// 左右侧用不同色调，让「现在做哪一侧」不需要读文字就能看出来。
    static func accent(for side: BodySide) -> Color {
        switch side {
        case .left: return Color(red: 0.45, green: 0.83, blue: 0.98)
        case .right: return Color(red: 1.00, green: 0.72, blue: 0.42)
        case .both, .none, .leftThenRight: return Color(red: 0.72, green: 0.85, blue: 1.00)
        }
    }
}
