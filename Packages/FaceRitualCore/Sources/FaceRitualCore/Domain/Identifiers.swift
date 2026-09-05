import Foundation

/// 类型安全的字符串 ID —— 防止 routineId / stepId / anchorId 互相串用。
public protocol StringIdentifier: Hashable, Codable, Sendable, CustomStringConvertible,
    ExpressibleByStringLiteral, RawRepresentable where RawValue == String {
    init(rawValue: String)
}

public extension StringIdentifier {
    init(stringLiteral value: String) { self.init(rawValue: value) }
    var description: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RoutineID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct RoutineStepID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct FaceAnchorID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct PracticeSessionID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
