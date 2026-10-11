import SwiftUI
import CopilotCore
import CopilotUI
#if os(macOS)
import MacIntegration
#endif

@main
struct AppleCopilotApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppleCopilotApplicationDelegate.self) private var delegate
    #endif
    @State private var environment: CopilotEnvironment = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return .preview() }
        #endif
        return .live()
    }()
    #if os(macOS)
    @FocusedValue(\.copilotActions) private var actions
    @FocusedValue(\.copilotSettingsActions) private var settingsActions
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Scene {
        #if os(macOS)
        mainWindow.defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新翻译") {
                    environment.startNewTranslation()
                    openWindow(id: "main")
                }.keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { show(.settings) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("保存设置") { settingsActions?.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(settingsActions?.canSave != true)
            }
            CommandMenu("翻译") {
                Button("翻译工作区") { show(.translate) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("历史记录") { show(.history) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("发送") { actions?.send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(actions?.canSend != true || actions?.isWorking == true)
                Button("停止生成") { actions?.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(actions?.isWorking != true)
            }
            SidebarCommands()
        }
        #else
        mainWindow
        #endif
    }

    private var mainWindow: some Scene {
        #if os(macOS)
        Window("Apple Copilot", id: "main") {
            AppRootView().environment(environment)
                .frame(minWidth: 600, minHeight: 500)
                .onAppear { delegate.environment = environment }
        }
        #else
        WindowGroup {
            AppRootView().environment(environment)
        }
        #endif
    }

    #if os(macOS)
    private func show(_ section: AppSection) {
        environment.section = section
        openWindow(id: "main")
    }
    #endif
}
