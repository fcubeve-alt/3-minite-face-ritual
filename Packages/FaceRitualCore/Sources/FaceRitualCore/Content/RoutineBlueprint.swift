import Foundation

/// routines.json 的解码形态：**routine 是时间线，动作在库里**。
///
/// 文档二 §9「一次动作资产，多处复用」。
/// Sprint 3 的 Prototype A 里 GM-11 与 GM-18 各出现两次，
/// 三套原型都用 GM-02 —— 内联复制迟早会漂移，所以这里只写引用。
///
/// 解码出来之后由 `ContentAssembler` 把引用解析成运行时的 `Routine`/`RoutineStep`，
/// 播放器那一侧完全不用改。
public struct RoutineBlueprint: Decodable, Sendable {
    public var id: RoutineID
    public var title: String
    public var subtitle: String?
    public var type: RoutineType
    public var isPremium: Bool
    public var steps: [StepReference]
    public var safetyNote: String?
    public var reviewStatus: ContentReviewStatus
    public var version: String

    public struct StepReference: Decodable, Sendable {
        /// 指向 Gold Motion Library 里的动作。
        public var move: GoldMoveID
        /// 覆盖时长。Sprint 3 的原型表里同一动作在不同位置时长不同
        /// （GM-08 在 Prototype B 占 20 秒、在 C 占 20 秒，但 GM-07 只有 15 秒）。
        public var durationSeconds: Double?
        /// 覆盖左右侧。缺省用动作库里的值。
        public var side: BodySide?
        /// 该位置在原型表里的作用说明（「重复强化熟悉感」这类），仅供审阅。
        public var roleNote: String?

        enum CodingKeys: String, CodingKey {
            case move, durationSeconds, side, roleNote
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            move = try container.decode(GoldMoveID.self, forKey: .move)
            durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
            side = try container.decodeIfPresent(BodySide.self, forKey: .side)
            roleNote = try container.decodeIfPresent(String.self, forKey: .roleNote)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, type, isPremium, steps, safetyNote, reviewStatus, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RoutineID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        type = try container.decode(RoutineType.self, forKey: .type)
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        steps = try container.decodeIfPresent([StepReference].self, forKey: .steps) ?? []
        safetyNote = try container.decodeIfPresent(String.self, forKey: .safetyNote)
        reviewStatus = try container.decodeIfPresent(ContentReviewStatus.self, forKey: .reviewStatus) ?? .draft
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "0.0.1"
    }
}

public enum ContentAssemblyError: Error, CustomStringConvertible {
    case unknownMove(routine: RoutineID, move: GoldMoveID)

    public var description: String {
        switch self {
        case let .unknownMove(routine, move):
            return "routine \(routine) 引用了动作库里不存在的动作 \(move)"
        }
    }
}

/// 把「时间线 + 动作库」拼成运行时 Routine。
public enum ContentAssembler {

    public static func assemble(
        blueprint: RoutineBlueprint,
        moves: [GoldMoveID: GoldMove]
    ) throws -> Routine {
        var steps: [RoutineStep] = []
        steps.reserveCapacity(blueprint.steps.count)

        for (index, ref) in blueprint.steps.enumerated() {
            guard let move = moves[ref.move] else {
                throw ContentAssemblyError.unknownMove(routine: blueprint.id, move: ref.move)
            }
            // 同一动作可能在一个 routine 里出现多次（Prototype A 的 GM-11 / GM-18），
            // 所以 step id 必须带上位置序号，否则会重复。
            let stepID = RoutineStepID(
                rawValue: "\(blueprint.id.rawValue)_\(String(format: "%02d", index + 1))_\(ref.move.rawValue)"
            )
            steps.append(
                move.makeStep(
                    stepID: stepID,
                    durationSeconds: ref.durationSeconds,
                    side: ref.side
                )
            )
        }

        return Routine(
            id: blueprint.id,
            title: blueprint.title,
            subtitle: blueprint.subtitle,
            type: blueprint.type,
            isPremium: blueprint.isPremium,
            steps: steps,
            safetyNote: blueprint.safetyNote,
            reviewStatus: blueprint.reviewStatus,
            version: blueprint.version
        )
    }
}
