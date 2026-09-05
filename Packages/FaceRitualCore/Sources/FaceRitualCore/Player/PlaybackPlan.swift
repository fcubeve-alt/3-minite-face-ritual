import Foundation

/// 播放段 —— routine step 展开后的最小播放单位。
///
/// `side == .leftThenRight` 的 step 在这里被展开成两段，
/// 于是 `RoutinePlayerEngine` 本身完全不需要理解左右语义。
public struct PlaybackSegment: Sendable, Hashable, Identifiable {
    public let id: String
    public let stepIndex: Int
    public let segmentIndexInStep: Int
    public let segmentCountInStep: Int
    public let step: RoutineStep
    /// 已确定的一侧（不会再是 `.leftThenRight`）。
    public let side: BodySide
    public let durationSeconds: Double
    /// 相对整个 routine 起点的偏移。
    public let startOffsetSeconds: Double

    public var isFirstSegmentOfStep: Bool { segmentIndexInStep == 0 }
    public var isLastSegmentOfStep: Bool { segmentIndexInStep == segmentCountInStep - 1 }

    /// 该段实际使用的 MovementSpec：anchor 引用按本段的解剖学侧自动改写。
    /// 内容作者只写一侧（如 `temple_left`），另一侧由系统推导。
    public var resolvedMovement: MovementSpec {
        var movement = step.movement
        movement.startAnchorID = movement.startAnchorID?.resolved(for: side)
        movement.endAnchorID = movement.endAnchorID?.resolved(for: side)
        return movement
    }

    /// `side == .both` 时需要同时绘制的镜像 MovementSpec；其余情况返回 nil。
    public var mirroredMovementForBothSides: MovementSpec? {
        guard side == .both else { return nil }
        var movement = step.movement
        movement.startAnchorID = movement.startAnchorID?.mirrored
        movement.endAnchorID = movement.endAnchorID?.mirrored
        return movement
    }
}

/// 一次播放的完整计划。构建后不可变。
public struct PlaybackPlan: Sendable, Hashable {
    public let routine: Routine
    public let segments: [PlaybackSegment]
    public let totalDurationSeconds: Double
    /// routine 开始前的准备倒计时（秒）。
    public let prepareCountdownSeconds: Double

    public init(routine: Routine, prepareCountdownSeconds: Double = 3) {
        self.routine = routine
        self.prepareCountdownSeconds = prepareCountdownSeconds

        var built: [PlaybackSegment] = []
        var offset = 0.0
        for (stepIndex, step) in routine.steps.enumerated() {
            let sides: [BodySide]
            switch step.side {
            case .leftThenRight:
                sides = [.left, .right]
            default:
                sides = [step.side]
            }
            let perSegmentDuration = step.durationSeconds / Double(sides.count)
            for (segmentIndex, side) in sides.enumerated() {
                built.append(
                    PlaybackSegment(
                        id: "\(step.id.rawValue)#\(segmentIndex)",
                        stepIndex: stepIndex,
                        segmentIndexInStep: segmentIndex,
                        segmentCountInStep: sides.count,
                        step: step,
                        side: side,
                        durationSeconds: perSegmentDuration,
                        startOffsetSeconds: offset
                    )
                )
                offset += perSegmentDuration
            }
        }
        self.segments = built
        self.totalDurationSeconds = offset
    }

    public var isEmpty: Bool { segments.isEmpty }

    public func segment(at index: Int) -> PlaybackSegment? {
        segments.indices.contains(index) ? segments[index] : nil
    }
}
