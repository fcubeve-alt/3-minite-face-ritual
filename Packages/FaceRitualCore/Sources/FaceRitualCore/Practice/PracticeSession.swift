import Foundation

public enum PracticeMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case coach
    case arMirror
    case watch

    public var id: String { rawValue }
}

/// 规格 §16 的 PracticeSession。
public struct PracticeSession: Codable, Hashable, Sendable, Identifiable {
    public var id: PracticeSessionID
    public var routineID: RoutineID
    public var routineTitle: String
    public var routineType: RoutineType
    public var startedAt: Date
    public var completedAt: Date?
    public var completed: Bool
    public var secondsCompleted: Double
    public var mode: PracticeMode
    public var arMirrorUsed: Bool
    public var faceLockLossCount: Int
    /// 首次 Face Lock 耗时（秒）。规格 §17 的 AR 指标之一。
    public var timeToFirstFaceLock: Double?
    /// 记录当时使用的 provider，方便回溯 POC 数据。
    public var faceProviderID: String?
    /// AR 中途退回 Coach（规格 §4：识别失败不得阻塞 routine）。
    /// 与 `guidanceFallback` 事件对应，是判断 AR 可用性的重要信号。
    public var didFallBackToCoach: Bool
    public var contentVersion: String

    public init(
        id: PracticeSessionID = PracticeSessionID(rawValue: UUID().uuidString),
        routineID: RoutineID,
        routineTitle: String,
        routineType: RoutineType,
        startedAt: Date,
        completedAt: Date? = nil,
        completed: Bool = false,
        secondsCompleted: Double = 0,
        mode: PracticeMode,
        arMirrorUsed: Bool = false,
        faceLockLossCount: Int = 0,
        timeToFirstFaceLock: Double? = nil,
        faceProviderID: String? = nil,
        didFallBackToCoach: Bool = false,
        contentVersion: String = "unknown"
    ) {
        self.id = id
        self.routineID = routineID
        self.routineTitle = routineTitle
        self.routineType = routineType
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.completed = completed
        self.secondsCompleted = secondsCompleted
        self.mode = mode
        self.arMirrorUsed = arMirrorUsed
        self.faceLockLossCount = faceLockLossCount
        self.timeToFirstFaceLock = timeToFirstFaceLock
        self.faceProviderID = faceProviderID
        self.didFallBackToCoach = didFallBackToCoach
        self.contentVersion = contentVersion
    }

    public var minutesCompleted: Double { secondsCompleted / 60 }
}

// MARK: - 向前兼容的解码

extension PracticeSession {
    enum CodingKeys: String, CodingKey {
        case id, routineID, routineTitle, routineType, startedAt, completedAt
        case completed, secondsCompleted, mode, arMirrorUsed, faceLockLossCount
        case timeToFirstFaceLock, faceProviderID, didFallBackToCoach, contentVersion
    }

    /// 手写解码，而不是用合成实现。
    ///
    /// 原因：练习记录是**用户数据**。若用合成 Codable，以后每加一个非可选字段，
    /// 旧记录就会整体解码失败 —— 而 FilePracticeStore 解码失败时返回空数组，
    /// 等于静默清空用户的全部历史。这里让缺失字段一律取默认值，
    /// 新增字段永远不会破坏已存在的记录。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(PracticeSessionID.self, forKey: .id),
            routineID: try container.decode(RoutineID.self, forKey: .routineID),
            routineTitle: try container.decodeIfPresent(String.self, forKey: .routineTitle) ?? "",
            routineType: try container.decodeIfPresent(RoutineType.self, forKey: .routineType) ?? .morning,
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            completedAt: try container.decodeIfPresent(Date.self, forKey: .completedAt),
            completed: try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false,
            secondsCompleted: try container.decodeIfPresent(Double.self, forKey: .secondsCompleted) ?? 0,
            mode: try container.decodeIfPresent(PracticeMode.self, forKey: .mode) ?? .coach,
            arMirrorUsed: try container.decodeIfPresent(Bool.self, forKey: .arMirrorUsed) ?? false,
            faceLockLossCount: try container.decodeIfPresent(Int.self, forKey: .faceLockLossCount) ?? 0,
            timeToFirstFaceLock: try container.decodeIfPresent(Double.self, forKey: .timeToFirstFaceLock),
            faceProviderID: try container.decodeIfPresent(String.self, forKey: .faceProviderID),
            didFallBackToCoach: try container.decodeIfPresent(Bool.self, forKey: .didFallBackToCoach) ?? false,
            contentVersion: try container.decodeIfPresent(String.self, forKey: .contentVersion) ?? "unknown"
        )
    }
}

/// 规格 §12：按月展示次数/分钟数，**保留连续天数但不惩罚断签**。
public struct MonthlyStats: Sendable, Hashable {
    public let year: Int
    public let month: Int
    public let sessionCount: Int
    public let completedCount: Int
    public let totalMinutes: Double
    /// 本月有练习的不同日期数。
    public let activeDays: Int
    /// 当前连续天数。仅作正向展示，UI 不得用它制造断签焦虑。
    public let currentStreakDays: Int

    public init(
        year: Int,
        month: Int,
        sessionCount: Int,
        completedCount: Int,
        totalMinutes: Double,
        activeDays: Int,
        currentStreakDays: Int
    ) {
        self.year = year
        self.month = month
        self.sessionCount = sessionCount
        self.completedCount = completedCount
        self.totalMinutes = totalMinutes
        self.activeDays = activeDays
        self.currentStreakDays = currentStreakDays
    }

    public static func empty(year: Int, month: Int) -> MonthlyStats {
        MonthlyStats(year: year, month: month, sessionCount: 0, completedCount: 0, totalMinutes: 0, activeDays: 0, currentStreakDays: 0)
    }
}

public enum PracticeStatsCalculator {

    public static func monthlyStats(
        sessions: [PracticeSession],
        year: Int,
        month: Int,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> MonthlyStats {
        let inMonth = sessions.filter { session in
            let components = calendar.dateComponents([.year, .month], from: session.startedAt)
            return components.year == year && components.month == month
        }
        let completed = inMonth.filter(\.completed)
        let minutes = inMonth.reduce(0.0) { $0 + $1.minutesCompleted }
        let days = Set(inMonth.map { calendar.startOfDay(for: $0.startedAt) })

        return MonthlyStats(
            year: year,
            month: month,
            sessionCount: inMonth.count,
            completedCount: completed.count,
            totalMinutes: minutes,
            activeDays: days.count,
            currentStreakDays: currentStreak(sessions: sessions, calendar: calendar, now: now)
        )
    }

    /// 从今天（或昨天，容许当天还没练）往回数连续有练习的天数。
    public static func currentStreak(
        sessions: [PracticeSession],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        guard days.isEmpty == false else { return 0 }

        let today = calendar.startOfDay(for: now)
        var cursor = today
        if days.contains(today) == false {
            // 今天还没练不算断 —— 从昨天开始数。
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today), days.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
