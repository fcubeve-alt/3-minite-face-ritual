import Foundation

/// 分析事件。规格 §15 要求的五个 AR 事件全部在列，且**只能**通过这个枚举上报 ——
/// 没有自由字符串事件名，避免埋点漂移。
public enum AnalyticsEvent: Sendable {
    // 生命周期
    case appOpened(isFirstLaunch: Bool)
    case homeViewed(greeting: String)

    // Routine 流程
    case routineStarted(routineID: RoutineID, type: RoutineType, mode: PracticeMode)
    case routineCompleted(routineID: RoutineID, mode: PracticeMode, secondsCompleted: Double)
    case routineAbandoned(routineID: RoutineID, mode: PracticeMode, secondsCompleted: Double, atStepIndex: Int)
    case modeSelected(mode: PracticeMode, routineID: RoutineID)

    // 规格 §15 指定的 AR 事件
    case arMirrorStarted(routineID: RoutineID, providerID: String)
    case arStepCompleted(routineID: RoutineID, stepID: RoutineStepID, quality: GuidanceQuality)
    case faceLockLost(routineID: RoutineID, stepID: RoutineStepID?, hint: GuidanceHint)
    case guidanceFallback(routineID: RoutineID, from: PracticeMode, to: PracticeMode, reason: String)
    case watchModeUsed(routineID: RoutineID)

    // AR 质量指标（规格 §17）
    case faceLockAcquired(providerID: String, secondsToLock: Double)
    case arSessionQuality(providerID: String, averageFPS: Double, averageLatencyMS: Double, lockLossCount: Int)

    // 权限 / 订阅 / 提醒
    case cameraPermissionRequested
    case cameraPermissionResult(granted: Bool)
    case paywallViewed(source: String)
    case purchaseAttempted(productID: String)
    case purchaseResult(productID: String, success: Bool)
    case mockUnlockToggled(enabled: Bool)
    case reminderScheduled(kind: String, hour: Int, minute: Int)
    case reminderCancelled(kind: String)

    // 内容健康
    case contentValidationIssues(errorCount: Int, warningCount: Int)

    public var name: String {
        switch self {
        case .appOpened: return "app_opened"
        case .homeViewed: return "home_viewed"
        case .routineStarted: return "routine_started"
        case .routineCompleted: return "routine_completed"
        case .routineAbandoned: return "routine_abandoned"
        case .modeSelected: return "mode_selected"
        case .arMirrorStarted: return "arMirrorStarted"
        case .arStepCompleted: return "arStepCompleted"
        case .faceLockLost: return "faceLockLost"
        case .guidanceFallback: return "guidanceFallback"
        case .watchModeUsed: return "watchModeUsed"
        case .faceLockAcquired: return "face_lock_acquired"
        case .arSessionQuality: return "ar_session_quality"
        case .cameraPermissionRequested: return "camera_permission_requested"
        case .cameraPermissionResult: return "camera_permission_result"
        case .paywallViewed: return "paywall_viewed"
        case .purchaseAttempted: return "purchase_attempted"
        case .purchaseResult: return "purchase_result"
        case .mockUnlockToggled: return "mock_unlock_toggled"
        case .reminderScheduled: return "reminder_scheduled"
        case .reminderCancelled: return "reminder_cancelled"
        case .contentValidationIssues: return "content_validation_issues"
        }
    }

    public var parameters: [String: String] {
        switch self {
        case let .appOpened(isFirstLaunch):
            return ["is_first_launch": String(isFirstLaunch)]
        case let .homeViewed(greeting):
            return ["greeting": greeting]
        case let .routineStarted(routineID, type, mode):
            return ["routine_id": routineID.rawValue, "type": type.rawValue, "mode": mode.rawValue]
        case let .routineCompleted(routineID, mode, seconds):
            return ["routine_id": routineID.rawValue, "mode": mode.rawValue, "seconds": String(format: "%.1f", seconds)]
        case let .routineAbandoned(routineID, mode, seconds, stepIndex):
            return [
                "routine_id": routineID.rawValue,
                "mode": mode.rawValue,
                "seconds": String(format: "%.1f", seconds),
                "step_index": String(stepIndex)
            ]
        case let .modeSelected(mode, routineID):
            return ["mode": mode.rawValue, "routine_id": routineID.rawValue]
        case let .arMirrorStarted(routineID, providerID):
            return ["routine_id": routineID.rawValue, "provider": providerID]
        case let .arStepCompleted(routineID, stepID, quality):
            return ["routine_id": routineID.rawValue, "step_id": stepID.rawValue, "quality": quality.rawValue]
        case let .faceLockLost(routineID, stepID, hint):
            return ["routine_id": routineID.rawValue, "step_id": stepID?.rawValue ?? "", "hint": hint.rawValue]
        case let .guidanceFallback(routineID, from, to, reason):
            return ["routine_id": routineID.rawValue, "from": from.rawValue, "to": to.rawValue, "reason": reason]
        case let .watchModeUsed(routineID):
            return ["routine_id": routineID.rawValue]
        case let .faceLockAcquired(providerID, seconds):
            return ["provider": providerID, "seconds_to_lock": String(format: "%.2f", seconds)]
        case let .arSessionQuality(providerID, fps, latency, lockLoss):
            return [
                "provider": providerID,
                "avg_fps": String(format: "%.1f", fps),
                "avg_latency_ms": String(format: "%.1f", latency),
                "lock_loss_count": String(lockLoss)
            ]
        case .cameraPermissionRequested:
            return [:]
        case let .cameraPermissionResult(granted):
            return ["granted": String(granted)]
        case let .paywallViewed(source):
            return ["source": source]
        case let .purchaseAttempted(productID):
            return ["product_id": productID]
        case let .purchaseResult(productID, success):
            return ["product_id": productID, "success": String(success)]
        case let .mockUnlockToggled(enabled):
            return ["enabled": String(enabled)]
        case let .reminderScheduled(kind, hour, minute):
            return ["kind": kind, "hour": String(hour), "minute": String(minute)]
        case let .reminderCancelled(kind):
            return ["kind": kind]
        case let .contentValidationIssues(errorCount, warningCount):
            return ["errors": String(errorCount), "warnings": String(warningCount)]
        }
    }
}

public protocol AnalyticsService: AnyObject {
    func track(_ event: AnalyticsEvent)
}

/// 控制台实现。M1 不接任何第三方 SDK ——
/// 接入前需要 Owner 决定隐私政策与数据处理方（规格 §19）。
public final class ConsoleAnalyticsService: AnalyticsService {
    private let isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        let params = event.parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[analytics] \(event.name) \(params)")
    }
}

/// 记录到内存，供 Debug 页与测试断言使用。
public final class RecordingAnalyticsService: AnalyticsService {
    public private(set) var recorded: [(name: String, parameters: [String: String])] = []
    private let forward: AnalyticsService?
    private let limit: Int

    public init(forward: AnalyticsService? = nil, limit: Int = 500) {
        self.forward = forward
        self.limit = limit
    }

    public func track(_ event: AnalyticsEvent) {
        recorded.append((event.name, event.parameters))
        if recorded.count > limit { recorded.removeFirst(recorded.count - limit) }
        forward?.track(event)
    }

    public func names() -> [String] { recorded.map(\.name) }

    public func clear() { recorded.removeAll() }
}
