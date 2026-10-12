import SwiftUI
import CopilotCore

#Preview("已翻译，可追问") {
    NavigationStack { TranslateView() }
        .environment(CopilotEnvironment.preview())
}

#Preview("Markdown、代码与 Mermaid") {
    NavigationStack { TranslateView() }
        .environment(CopilotEnvironment.preview(markdown: true))
}

#Preview("空白翻译") {
    let environment = CopilotEnvironment.preview()
    environment.session.newConversation()
    return NavigationStack { TranslateView() }.environment(environment)
}

#Preview("请求错误") {
    PreviewRequestState(fails: true)
}

#Preview("等待回复") {
    PreviewRequestState(fails: false)
}

#Preview("系统翻译内容 · 窄弹窗") {
    TranslationOverlayView(
        selectedText: "Good design makes complex things simple.",
        finish: { _ in }, expand: {}
    )
    .environment(CopilotEnvironment.preview())
    .frame(width: 340, height: 500)
}

#Preview("追问 · 多行") {
    @Previewable @State var draft = "请解释 complex 的意思。\n再用更自然的中文改写。"
    GlassComposer(text: $draft, isWorking: false, send: {}, cancel: {})
        .frame(width: 360)
        .padding(.vertical)
}

#Preview("追问 · 最大字号") {
    @Previewable @State var draft = "请解释词义"
    GlassComposer(text: $draft, isWorking: false, send: {}, cancel: {})
        .dynamicTypeSize(.accessibility5)
        .frame(width: 360)
}

private struct PreviewRequestState: View {
    let fails: Bool
    @State private var store: ConversationStore
    private let settings: SettingsStore

    init(fails: Bool) {
        self.fails = fails
        let settings = SettingsStore(repository: MemorySettingsRepository(), credentials: MemoryCredentialStore())
        self.settings = settings
        _store = State(
            initialValue: ConversationStore(
                client: PendingPreviewClient(fails: fails),
                repository: MemoryConversationRepository(), settings: settings))
    }

    var body: some View {
        ConversationDetail(store: store)
            .task {
                await settings.load()
                settings.apiKey = "preview-only"
                await settings.save()
                await store.translate("Good design makes complex things simple.")
            }
    }
}

private struct PendingPreviewClient: LanguageModelClient {
    let fails: Bool
    func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String
    {
        if fails { throw CopilotError.httpStatus(429) }
        try await Task.sleep(for: .seconds(3600))
        return "好的设计让复杂的事情变得简单。"
    }
}
