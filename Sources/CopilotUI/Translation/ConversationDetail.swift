import CopilotCore
import SwiftUI

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
    @State private var scrollPosition = ScrollPosition()
    @State private var isUserScrolling = false
    @State private var hasStreamedRequest = false
    @State private var focusRevision = 0

    public init(
        store: ConversationStore, onFocus: @escaping () -> Void = {},
        onSettings: (() -> Void)? = nil, replaceTranslation: ((String) -> Void)? = nil,
        contentPadding: CGFloat = 20, draft: Binding<String>? = nil
    ) {
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
                        ConversationTranscript(
                            conversation: conversation,
                            onSettings: onSettings, replaceTranslation: replaceTranslation,
                            pendingUserMessage: store.pendingUserMessage,
                            streamingMessage: store.streamingMessage.flatMap { $0.content.isEmpty ? nil : $0 },
                            isWorking: store.isWorking)
                    }
                    if store.isWorking {
                        ProgressView(
                            store.streamingMessage?.content.isEmpty == false
                                ? "正在生成…" : (store.conversation?.messages.isEmpty == true ? "正在翻译…" : "正在思考…")
                        )
                        .accessibilityLabel(store.streamingMessage?.content.isEmpty == false ? "正在生成回复" : "正在等待模型回复")
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
                            Task {
                                await store.translate(
                                    conversation.sourceText, targetLanguage: conversation.configuration.targetLanguage)
                            }
                        }.buttonStyle(.glassProminent)
                        if let onSettings {
                            Button("设置模型与密钥", systemImage: "gearshape", action: onSettings)
                                .buttonStyle(.glass)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .coordinateSpace(name: "transcript")
                // Accept narrow split-column proposals instead of letting the
                // transcript's ideal width push content beyond the window.
                .frame(minWidth: 0, maxWidth: 760)
                .padding(contentPadding)
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            .scrollPosition($scrollPosition)
            .environment(
                \.scrollMarkdownAnchor,
                MarkdownAnchorAction { y in
                    isNearBottom = false
                    scrollPosition.scrollTo(y: max(0, y + contentPadding))
                }
            )
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 80
            } action: { _, value in
                if isUserScrolling { isNearBottom = value }
            }
            .onScrollPhaseChange { _, phase, context in
                isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                if isUserScrolling {
                    isNearBottom = context.geometry.visibleRect.maxY >= context.geometry.contentSize.height - 80
                }
            }
            .onChange(of: store.conversation?.messages.count) { _, _ in
                if isNearBottom { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: store.isWorking) { _, _ in
                if store.isWorking { hasStreamedRequest = true }
                if isNearBottom { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: store.streamingMessage?.content) { _, _ in
                if isNearBottom { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentSize.height
            } action: { _, _ in
                // WebKit reports measured height asynchronously, after Markdown/SVG layout.
                if isNearBottom && hasStreamedRequest { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: focusRevision) { _, _ in
                if isNearBottom { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.conversation?.messages.isEmpty == false {
                GlassComposer(
                    text: questionBinding, isWorking: store.isWorking,
                    onFocus: {
                        onFocus()
                        focusRevision += 1
                    },
                    send: send, cancel: store.cancel
                )
                .frame(minWidth: 0, maxWidth: 800)
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .copilotPageBackground()
        .onDisappear {
            if store.conversation?.messages.isEmpty == false,
                questionBinding.wrappedValue.isEmpty, let pending = store.pendingMessage
            {
                questionBinding.wrappedValue = pending
            }
            store.cancel()
        }
        .onChange(of: store.conversation?.id) { _, _ in
            questionBinding.wrappedValue = ""; retryQuestion = nil
            isNearBottom = true; hasStreamedRequest = store.isWorking
        }
        .onChange(of: store.requestState) { _, state in
            if (state == .failed || state == .cancelled), questionBinding.wrappedValue.isEmpty, let retryQuestion {
                questionBinding.wrappedValue = retryQuestion
            }
        }
        #if os(macOS)
        .focusedSceneValue(
            \.copilotActions,
            CopilotActions(
                send: {
                    if let conversation = store.conversation, conversation.messages.isEmpty {
                        Task {
                            await store.translate(
                                conversation.sourceText, targetLanguage: conversation.configuration.targetLanguage)
                        }
                    } else {
                        send()
                    }
                }, cancel: store.cancel,
                canSend: store.conversation?.messages.isEmpty == true
                    || !questionBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                isWorking: store.isWorking))
        #endif
    }

    private func send() {
        guard !store.isWorking else { return }
        let value = questionBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        retryQuestion = value
        questionBinding.wrappedValue = ""
        Task { await store.ask(value) }
    }
}
