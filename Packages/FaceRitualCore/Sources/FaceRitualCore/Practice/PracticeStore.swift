import Foundation

/// 练习记录持久化抽象。
/// M1 用本地 JSON 文件；后续换 CoreData / CloudKit / 后端时业务层零改动。
public protocol PracticeStore: AnyObject {
    func allSessions() -> [PracticeSession]
    func save(_ session: PracticeSession) throws
    func delete(id: PracticeSessionID) throws
    func deleteAll() throws
}

public extension PracticeStore {
    func recentSessions(limit: Int) -> [PracticeSession] {
        Array(allSessions().sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    func monthlyStats(year: Int, month: Int, calendar: Calendar = .current, now: Date = Date()) -> MonthlyStats {
        PracticeStatsCalculator.monthlyStats(sessions: allSessions(), year: year, month: month, calendar: calendar, now: now)
    }

    func currentMonthStats(calendar: Calendar = .current, now: Date = Date()) -> MonthlyStats {
        let components = calendar.dateComponents([.year, .month], from: now)
        return monthlyStats(year: components.year ?? 0, month: components.month ?? 0, calendar: calendar, now: now)
    }
}

/// 单文件 JSON 存储。
///
/// 选它而不是 CoreData：M1 的数据量是「每天几条记录」，
/// 引入 CoreData 只会增加迁移负担和真机调试噪音。
public final class FilePracticeStore: PracticeStore {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.faceritual.practicestore")
    private var cache: [PracticeSession]?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认落在 Application Support（不会被 iCloud 备份排除，也不会被系统清理）。
    public static func makeDefault(fileManager: FileManager = .default) throws -> FilePracticeStore {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("FaceRitual", isDirectory: true)
        if fileManager.fileExists(atPath: directory.path) == false {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return FilePracticeStore(fileURL: directory.appendingPathComponent("practice_sessions.json"))
    }

    public func allSessions() -> [PracticeSession] {
        queue.sync {
            if let cache { return cache }
            let loaded = readFromDisk()
            cache = loaded
            return loaded
        }
    }

    public func save(_ session: PracticeSession) throws {
        try queue.sync {
            var sessions = cache ?? readFromDisk()
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.append(session)
            }
            try writeToDisk(sessions)
            cache = sessions
        }
    }

    public func delete(id: PracticeSessionID) throws {
        try queue.sync {
            var sessions = cache ?? readFromDisk()
            sessions.removeAll { $0.id == id }
            try writeToDisk(sessions)
            cache = sessions
        }
    }

    public func deleteAll() throws {
        try queue.sync {
            try writeToDisk([])
            cache = []
        }
    }

    // MARK: - 磁盘

    /// 上一次读盘是否遇到了损坏的记录文件。Debug 页可以展示它。
    public private(set) var lastReadWasCorrupted = false

    private func readFromDisk() -> [PracticeSession] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let sessions = try decoder.decode([PracticeSession].self, from: data)
            lastReadWasCorrupted = false
            return sessions
        } catch {
            // 记录损坏不能让用户开不了 App —— 但也不能直接丢掉。
            // 先把坏文件改名留存，用户的数据仍有机会人工恢复，
            // 之后的写入才不会覆盖掉它。
            lastReadWasCorrupted = true
            quarantineCorruptedFile()
            return []
        }
    }

    private func quarantineCorruptedFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("practice_sessions.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    private func writeToDisk(_ sessions: [PracticeSession]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// 内存实现，用于单元测试、SwiftUI Preview 与 UI 演示。
public final class InMemoryPracticeStore: PracticeStore {
    private var sessions: [PracticeSession]

    public init(sessions: [PracticeSession] = []) {
        self.sessions = sessions
    }

    public func allSessions() -> [PracticeSession] { sessions }

    public func save(_ session: PracticeSession) throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    public func delete(id: PracticeSessionID) throws {
        sessions.removeAll { $0.id == id }
    }

    public func deleteAll() throws {
        sessions.removeAll()
    }
}
