import SwiftUI
import FaceRitualCore

@main
struct FaceRitualApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .preferredColorScheme(.dark)
                .task {
                    environment.analytics.track(.appOpened(isFirstLaunch: environment.settings.isFirstLaunch))
                }
        }
    }
}

/// 导航目的地。用枚举而不是散落的 NavigationLink，
/// 方便之后加 deep link（提醒点进来直接开始 Morning Ritual）。
enum AppRoute: Hashable {
    case routineDetail(RoutineID)
    case history
    case settings
    case debug
}

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let error = environment.contentLoadError {
                    ContentUnavailableStateView(message: error)
                } else {
                    HomeView(path: $path)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case let .routineDetail(id):
                    if let routine = environment.content.routine(id: id) {
                        RoutineDetailView(routine: routine)
                    } else {
                        ContentUnavailableStateView(message: "Routine not found: \(id)")
                    }
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView()
                case .debug:
                    DebugView()
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// 内容加载失败时的兜底页。
/// 显示可读的原因而不是白屏 —— M1 阶段内容 JSON 会频繁替换，
/// 出问题时要能立刻看出是哪一条校验没过。
struct ContentUnavailableStateView: View {
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "doc.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.warning)
                Text(AppCopy.contentUnavailableTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(AppCopy.contentUnavailableBody)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                // 技术细节保留英文且不本地化：这个界面正常情况下用户看不到，
                // 出现时是构建/配置问题，读它的人是我们自己。
                Text("Run `python tools/validate_content.py` on any machine to locate the problem.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
