import SwiftUI
import CopilotCore

public struct AppRootView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {}

    public var body: some View {
        Group {
            #if os(macOS)
            HistoryView(isWorkspace: true)
            #else
            GeometryReader { geometry in
                if horizontalSizeClass == .regular && geometry.size.width >= 760 {
                    HistoryView(isWorkspace: true)
                } else {
                    compactNavigation
                }
            }
            #endif
        }
        .background(CopilotSurface.page, ignoresSafeAreaEdges: .all)
        .task { await environment.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await environment.settings.refresh()
                    if environment.section != .history { await environment.session.loadHistory() }
                }
            }
        }
    }

    #if os(iOS)
    private var compactNavigation: some View {
        @Bindable var state = environment
        return TabView(selection: $state.section) {
            Tab("翻译", systemImage: AppSection.translate.symbol, value: AppSection.translate) {
                NavigationStack { TranslateView() }
            }
            Tab("历史", systemImage: AppSection.history.symbol, value: AppSection.history) {
                HistoryView()
            }
            Tab("设置", systemImage: AppSection.settings.symbol, value: AppSection.settings) {
                NavigationStack { SettingsView() }
            }
        }
    }
    #endif
}
