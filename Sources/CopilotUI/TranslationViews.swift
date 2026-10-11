import SwiftUI
import CopilotCore

public struct TranslateView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var source: String { environment.sourceDraft }

    private var translationActionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    public init() {}

    public var body: some View {
        @Bindable var state = environment
        Group {
            if environment.session.conversation != nil {
                ConversationDetail(store: environment.session, draft: $state.questionDraft)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let message = environment.startupMessage {
                            InlineNotice(title: "需要配置共享权限", message: message)
                        }
                        SourceEditor(text: $state.sourceDraft)
                        translationActionsLayout {
                            Text("译为 \(environment.settings.savedConfiguration.targetLanguage)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
                            Button("翻译", systemImage: "character.bubble") {
                                Task { await environment.session.translate(source) }
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.regular)
                            .fixedSize(horizontal: true, vertical: false)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || environment.session.isWorking || environment.startupMessage != nil)
                        }
                        if environment.session.isWorking {
                            ProgressView("正在翻译…")
                            Button("停止生成") { environment.session.cancel() }.buttonStyle(.glass)
                        }
                        if let error = environment.session.errorMessage {
                            InlineNotice(title: "未能完成翻译", message: error)
                        }
                        if !environment.settings.hasSavedAPIKey {
                            Button("配置模型与密钥", systemImage: "key") {
                                environment.section = .settings
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .focusedSceneValue(\.copilotActions, CopilotActions(
                    send: { Task { await environment.session.translate(source) } },
                    cancel: environment.session.cancel,
                    canSend: !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    isWorking: environment.session.isWorking))
                #endif
            }
        }
        .navigationTitle("翻译")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新翻译", systemImage: "square.and.pencil") {
                    environment.startNewTranslation()
                }
                .help("开始新的翻译（⌘N）")
                .accessibilityLabel("新翻译")
            }
        }
    }
}

private struct SourceEditor: View {
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("原文").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(.background.secondary, in: .rect(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("输入或粘贴要翻译的文本")
                            .font(.body).foregroundStyle(.secondary)
                            .padding(.horizontal, 17).padding(.vertical, 20)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("要翻译的原文")
                .writingToolsBehavior(.complete)
        }
    }
}

public struct ConversationDetail: View {
    public let store: ConversationStore
    private let onFocus: () -> Void
    private let onSettings: (() -> Void)?
    private let replaceTranslation: ((String) -> Void)?
    private let contentPadding: CGFloat
    private let externalDraft: Binding<String>?
    @State private var question = ""
    @State private var retryQuestion: String?
    @State private var isNearBottom = true
    @State private var focusRevision = 0

    public init(store: ConversationStore, onFocus: @escaping () -> Void = {},
                onSettings: (() -> Void)? = nil, replaceTranslation: ((String) -> Void)? = nil,
                contentPadding: CGFloat = 20, draft: Binding<String>? = nil) {
        self.store = store
        self.onFocus = onFocus
        self.onSettings = onSettings
        self.replaceTranslation = replaceTranslation
        self.contentPadding = contentPadding
        self.externalDraft = draft
    }

    private var questionBinding: Binding<String> { externalDraft ?? $question }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let conversation = store.conversation {
                        ConversationTranscript(conversation: conversation,
                                               onSettings: onSettings, replaceTranslation: replaceTranslation)
                    }
                    if let pending = store.pendingMessage, store.conversation?.messages.isEmpty == false {
                        VStack(alignment: .leading) {
                            Text("追问").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            Text(pending).textSelection(.enabled)
                        }
                    }
                    if store.isWorking {
                        ProgressView(store.conversation?.messages.isEmpty == true ? "正在翻译…" : "正在思考…")
                            .accessibilityLabel("正在等待模型回复")
                        if store.conversation?.messages.isEmpty == true {
                            Button("停止生成", systemImage: "stop.fill") { store.cancel() }.buttonStyle(.glass)
                        }
                    }
                    if store.requestState == .cancelled {
                        Label("已停止生成，可以重新发送。", systemImage: "stop.circle").foregroundStyle(.secondary)
                    }
                    if let error = store.errorMessage {
                        InlineNotice(title: "未能获得回复", message: error)
                        if let retryQuestion, store.conversation?.messages.isEmpty == false {
                            Button("重试追问", systemImage: "arrow.clockwise") {
                                Task { await store.ask(retryQuestion) }
                            }
                            .buttonStyle(.glass)
                            .disabled(store.isWorking)
                        }
                    }
                    if let conversation = store.conversation, conversation.messages.isEmpty && !store.isWorking {
                        Button("重试翻译", systemImage: "arrow.clockwise") {
                            Task { await store.translate(conversation.sourceText, targetLanguage: conversation.configuration.targetLanguage) }
                        }.buttonStyle(.glassProminent)
                        if let onSettings {
                            Button("设置模型与密钥", systemImage: "gearshape", action: onSettings)
                                .buttonStyle(.glass)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: 760)
                .padding(contentPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 80
            } action: { _, value in isNearBottom = value }
            .onChange(of: store.conversation?.messages.count) { _, _ in
                if isNearBottom { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: store.isWorking) { _, _ in
                if isNearBottom { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: focusRevision) { _, _ in
                if isNearBottom { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.conversation?.messages.isEmpty == false {
                GlassComposer(text: questionBinding, isWorking: store.isWorking, onFocus: {
                    onFocus()
                    focusRevision += 1
                },
                              send: send, cancel: store.cancel)
                    .frame(maxWidth: 800)
                    .frame(maxWidth: .infinity)
            }
        }
        .onDisappear {
            if store.conversation?.messages.isEmpty == false,
               questionBinding.wrappedValue.isEmpty, let pending = store.pendingMessage {
                questionBinding.wrappedValue = pending
            }
            store.cancel()
        }
        .onChange(of: store.conversation?.id) { _, _ in questionBinding.wrappedValue = ""; retryQuestion = nil }
        .onChange(of: store.requestState) { _, state in
            if (state == .failed || state == .cancelled), questionBinding.wrappedValue.isEmpty, let retryQuestion {
                questionBinding.wrappedValue = retryQuestion
            }
        }
        #if os(macOS)
        .focusedSceneValue(\.copilotActions, CopilotActions(
            send: {
                if let conversation = store.conversation, conversation.messages.isEmpty {
                    Task { await store.translate(conversation.sourceText, targetLanguage: conversation.configuration.targetLanguage) }
                } else { send() }
            }, cancel: store.cancel,
            canSend: store.conversation?.messages.isEmpty == true || !questionBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isWorking: store.isWorking))
        #endif
    }

    private func send() {
        let value = questionBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        retryQuestion = value
        questionBinding.wrappedValue = ""
        Task { await store.ask(value) }
    }
}

/// The system sheet and the Mac Services panel already own their title and
/// close controls. The extension supplies only the translation and its actions.
public struct TranslationOverlayView: View {
    @Environment(CopilotEnvironment.self) private var environment
    private let selectedText: String
    private let targetLanguage: String?
    private let allowsReplacement: Bool
    private let finish: (String?) -> Void
    private let expand: () -> Void
    private let settingsPresentationChanged: (Bool) -> Void
    @State private var store: ConversationStore?
    @State private var isEditingSettings = false
    @State private var question = ""

    public init(selectedText: String, targetLanguage: String? = nil,
                allowsReplacement: Bool = false,
                finish: @escaping (String?) -> Void,
                expand: @escaping () -> Void,
                settingsPresentationChanged: @escaping (Bool) -> Void = { _ in }) {
        self.selectedText = selectedText
        self.targetLanguage = targetLanguage
        self.allowsReplacement = allowsReplacement
        self.finish = finish
        self.expand = expand
        self.settingsPresentationChanged = settingsPresentationChanged
    }

    public var body: some View {
        Group {
            if isEditingSettings {
                SettingsEditor(onClose: { isEditingSettings = false })
            } else if let store, store.conversation != nil {
                ConversationDetail(store: store, onFocus: expand,
                                   onSettings: { isEditingSettings = true; expand() },
                                   replaceTranslation: replacementAction,
                                   contentPadding: 16, draft: $question)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        SourceText(text: selectedText)
                        if let message = environment.startupMessage {
                            InlineNotice(title: "需要配置共享权限", message: message)
                        }
                        if let store, let error = store.errorMessage {
                            InlineNotice(title: "未能完成翻译", message: error)
                            Button("重试翻译", systemImage: "arrow.clockwise") {
                                Task { await store.translate(selectedText, targetLanguage: targetLanguage) }
                            }
                            .buttonStyle(.glassProminent)
                        }
                        if store?.isWorking == true { ProgressView("正在翻译…") }
                        if !environment.settings.hasSavedAPIKey {
                            Button("配置模型与密钥", systemImage: "key") { isEditingSettings = true; expand() }
                                .buttonStyle(.glass)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: selectedText) {
            store?.cancel()
            guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await environment.load()
            guard !Task.isCancelled else { return }
            let session = environment.makeConversationStore()
            store = session
            if environment.startupMessage == nil && environment.settings.hasSavedAPIKey {
                await session.translate(selectedText, targetLanguage: targetLanguage)
            }
        }
        .onChange(of: isEditingSettings) { oldValue, value in
            settingsPresentationChanged(value)
            if oldValue, !value, environment.settings.hasSavedAPIKey,
               store?.conversation == nil, let store {
                Task { await store.translate(selectedText, targetLanguage: targetLanguage) }
            }
        }
        .onDisappear { store?.cancel() }
    }

    private func replace(_ translation: String) {
        store?.cancel()
        finish(translation)
    }

    private var replacementAction: ((String) -> Void)? {
        guard allowsReplacement else { return nil }
        return { translation in replace(translation) }
    }
}
