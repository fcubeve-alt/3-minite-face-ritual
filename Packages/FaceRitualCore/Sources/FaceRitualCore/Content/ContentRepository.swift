import Foundation

/// 一次加载得到的完整内容包。
public struct ContentBundle: Sendable {
    public let meta: ContentMeta
    public let routines: [Routine]
    /// 已展开左右镜像后的 anchor 表。
    public let anchors: [FaceAnchorID: FaceAnchor]
    /// Gold Motion Library。动作的唯一真源（文档二 §2/§4）。
    public let moves: [GoldMoveID: GoldMove]

    public init(
        meta: ContentMeta,
        routines: [Routine],
        anchors: [FaceAnchorID: FaceAnchor],
        moves: [GoldMoveID: GoldMove] = [:]
    ) {
        self.meta = meta
        self.routines = routines
        self.anchors = anchors
        self.moves = moves
    }

    /// 按 Gold Move ID 排序的动作库，供 Debug 页与专家审阅使用。
    public var sortedMoves: [GoldMove] {
        moves.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// 尚未通过 Expert Gate 的动作。Sprint 3 文档开头即声明全部动作仍需人工专家审核。
    public var movesAwaitingExpertGate: [GoldMove] {
        sortedMoves.filter { $0.reviewStatus.isPublishable == false }
    }

    public func routine(id: RoutineID) -> Routine? {
        routines.first { $0.id == id }
    }

    public func routines(ofType type: RoutineType) -> [Routine] {
        routines.filter { $0.type == type }
    }

    public var morningCore: Routine? {
        routines.first { $0.type == .morning && $0.isPremium == false }
    }

    public var eveningCore: Routine? {
        routines.first { $0.type == .evening }
    }

    public var quickRituals: [Routine] {
        routines(ofType: .quick)
    }

    /// 内容包里是否还有未经专业审核的条目。
    /// UI 用它显示 MOCK 角标；发布前的 CI 用它拦截。
    public var containsUnreviewedContent: Bool {
        if meta.reviewStatus.isPublishable == false { return true }
        if routines.contains(where: { $0.reviewStatus.isPublishable == false }) { return true }
        if routines.contains(where: { $0.steps.contains { $0.reviewStatus.isPublishable == false } }) { return true }
        if anchors.values.contains(where: { $0.reviewStatus.isPublishable == false }) { return true }
        if moves.values.contains(where: { $0.reviewStatus.isPublishable == false }) { return true }
        return false
    }
}

public enum ContentLoadError: Error, CustomStringConvertible {
    case resourceNotFound(String)
    case schemaVersionMismatch(found: Int, expected: Int)
    case decodingFailed(resource: String, underlying: String)
    case validationFailed([ContentValidationIssue])

    public var description: String {
        switch self {
        case let .resourceNotFound(name):
            return "内容资源缺失: \(name)"
        case let .schemaVersionMismatch(found, expected):
            return "内容 schema 版本不匹配: 文件 \(found)，代码期望 \(expected)"
        case let .decodingFailed(resource, underlying):
            return "内容解码失败 \(resource): \(underlying)"
        case let .validationFailed(issues):
            return "内容校验失败:\n" + issues.map { "  - " + $0.description }.joined(separator: "\n")
        }
    }
}

/// 内容来源抽象。
///
/// UI / 播放器 / AR 全部只依赖这个协议 ——
/// 换成远程内容、A/B 内容或 Owner 审核后的正式内容包时，业务层零改动。
public protocol ContentRepository: AnyObject, Sendable {
    func load() throws -> ContentBundle
}

/// 从一组 JSON 数据加载。与文件系统解耦，便于测试。
public final class JSONContentRepository: ContentRepository, @unchecked Sendable {

    public struct Source: Sendable {
        public let metaData: Data
        public let routinesData: Data
        public let anchorsData: Data
        /// Gold Motion Library。
        public let movesData: Data

        public init(metaData: Data, routinesData: Data, anchorsData: Data, movesData: Data) {
            self.metaData = metaData
            self.routinesData = routinesData
            self.anchorsData = anchorsData
            self.movesData = movesData
        }
    }

    private let source: Source
    private let validator: ContentValidator
    /// 校验失败时是否抛错。DEBUG 建议 true（早发现），Release 建议 false（不让用户白屏）。
    private let failOnValidationError: Bool
    private var cached: ContentBundle?

    public init(source: Source, validator: ContentValidator = ContentValidator(), failOnValidationError: Bool = true) {
        self.source = source
        self.validator = validator
        self.failOnValidationError = failOnValidationError
    }

    public func load() throws -> ContentBundle {
        if let cached { return cached }

        let decoder = JSONDecoder()
        let meta: ContentMeta
        do {
            meta = try decoder.decode(ContentMeta.self, from: source.metaData)
        } catch {
            throw ContentLoadError.decodingFailed(resource: "content_meta.json", underlying: String(describing: error))
        }
        guard meta.schemaVersion == ContentSchema.currentVersion else {
            throw ContentLoadError.schemaVersionMismatch(found: meta.schemaVersion, expected: ContentSchema.currentVersion)
        }

        // 先解动作库 —— routine 只是引用它的时间线。
        let moveList: [GoldMove]
        do {
            moveList = try decoder.decode(MovesFile.self, from: source.movesData).moves
        } catch {
            throw ContentLoadError.decodingFailed(resource: "moves.json", underlying: String(describing: error))
        }
        var moveTable: [GoldMoveID: GoldMove] = [:]
        for move in moveList { moveTable[move.id] = move }

        let blueprints: [RoutineBlueprint]
        do {
            blueprints = try decoder.decode(RoutinesFile.self, from: source.routinesData).routines
        } catch {
            throw ContentLoadError.decodingFailed(resource: "routines.json", underlying: String(describing: error))
        }

        let routines: [Routine]
        do {
            routines = try blueprints.map { try ContentAssembler.assemble(blueprint: $0, moves: moveTable) }
        } catch {
            throw ContentLoadError.decodingFailed(resource: "routines.json", underlying: String(describing: error))
        }

        let declaredAnchors: [FaceAnchor]
        do {
            declaredAnchors = try decoder.decode(AnchorsFile.self, from: source.anchorsData).anchors
        } catch {
            throw ContentLoadError.decodingFailed(resource: "anchors.json", underlying: String(describing: error))
        }

        // 内容作者只写一侧，另一侧自动镜像 —— 避免两侧定义漂移。
        var anchorTable: [FaceAnchorID: FaceAnchor] = [:]
        for anchor in declaredAnchors {
            anchorTable[anchor.id] = anchor
            if let mirrored = anchor.mirroredToOppositeSide(), anchorTable[mirrored.id] == nil {
                anchorTable[mirrored.id] = mirrored
            }
        }

        let bundle = ContentBundle(
            meta: meta,
            routines: routines,
            anchors: anchorTable,
            moves: moveTable
        )
        let issues = validator.validate(bundle)
        let blocking = issues.filter { $0.severity == .error }
        if blocking.isEmpty == false, failOnValidationError {
            throw ContentLoadError.validationFailed(blocking)
        }
        cached = bundle
        return bundle
    }

    /// 最近一次加载的全部校验问题（含 warning），供 Debug 页展示。
    public func validationIssues() -> [ContentValidationIssue] {
        guard let cached else { return [] }
        return validator.validate(cached)
    }

    private struct RoutinesFile: Decodable { let routines: [RoutineBlueprint] }
    private struct AnchorsFile: Decodable { let anchors: [FaceAnchor] }
    private struct MovesFile: Decodable { let moves: [GoldMove] }
}
