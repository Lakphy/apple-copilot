import SwiftUI
import CopilotCore

public struct AppRootView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @State private var visibility: NavigationSplitViewVisibility = .all
    #endif

    public init() {}

    public var body: some View {
        @Bindable var state = environment
        Group {
            #if os(macOS)
            NavigationSplitView(columnVisibility: $visibility) {
                List(selection: $state.section) {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.symbol).tag(section)
                    }
                }
                .navigationTitle("Apple Copilot")
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 260)
            } detail: {
                switch environment.section {
                case .history:
                    HistoryView()
                case .translate:
                    NavigationStack { TranslateView() }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
            #else
            TabView(selection: $state.section) {
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
            .tabViewStyle(.sidebarAdaptable)
            #endif
        }
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
}
