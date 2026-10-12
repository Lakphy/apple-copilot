import Foundation
import Observation

public enum RequestState: String, Sendable {
    case idle, working, cancelled, failed
}

@MainActor
@Observable
public final class ConversationStore {
    public private(set) var conversation: Conversation?
    public private(set) var history: [Conversation] = []
    public private(set) var requestState: RequestState = .idle
    public private(set) var pendingUserMessage: ChatMessage?
    public var pendingMessage: String? { pendingUserMessage?.content }
    /// Transient output is readable/copyable, but enters history only after a complete response.
    public private(set) var streamingMessage: ChatMessage?
    public private(set) var errorMessage: String?
    public private(set) var historyErrorMessage: String?
    public private(set) var isLoadingHistory = false

    @ObservationIgnored private let client: any LanguageModelClient
    @ObservationIgnored private let repository: any ConversationRepository
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var operation: Task<Conversation, any Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var historyGeneration = UUID()
    @ObservationIgnored private var historyQuery = ""
    @ObservationIgnored private var streamedText = ""
    @ObservationIgnored private var lastStreamPublication = ContinuousClock.now

    public var isWorking: Bool { requestState == .working }

    public init(client: any LanguageModelClient, repository: any ConversationRepository, settings: SettingsStore) {
        self.client = client
        self.repository = repository
        self.settings = settings
    }

    public func translate(_ text: String, targetLanguage: String? = nil) async {
        guard !isWorking else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "请输入要翻译的文字。"
            requestState = .failed
            return
        }
        var configuration = settings.savedConfiguration
        if let targetLanguage, !targetLanguage.isEmpty { configuration.targetLanguage = targetLanguage }
        let draft = Conversation(sourceText: text, configuration: configuration)
        conversation = draft
        await perform(text: text, in: draft)
    }

    public func ask(_ text: String) async {
        guard !isWorking, let conversation else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !conversation.messages.isEmpty else {
            errorMessage = "请先完成翻译，再继续追问。"
            requestState = .failed
            return
        }
        await perform(text: text, in: conversation)
    }

    public func select(_ conversation: Conversation) {
        cancel()
        streamingMessage = nil
        self.conversation = conversation
        requestState = .idle
        errorMessage = nil
    }

    public func newConversation() {
        cancel()
        streamingMessage = nil
        conversation = nil
        requestState = .idle
        errorMessage = nil
    }

    public func cancel() {
        guard isWorking else { return }
        publishStream()
        generation = UUID()
        operation?.cancel()
        operation = nil
        pendingUserMessage = nil
        requestState = .cancelled
        errorMessage = nil
    }

    public func loadHistory(query: String = "") async {
        let token = UUID()
        historyGeneration = token
        historyQuery = query
        isLoadingHistory = true
        historyErrorMessage = nil
        do {
            let loaded = try await repository.history(query: query)
            guard historyGeneration == token else { return }
            history = loaded
        } catch {
            guard historyGeneration == token else { return }
            historyErrorMessage = safeMessage(for: error)
        }
        if historyGeneration == token { isLoadingHistory = false }
    }

    public func delete(_ id: UUID) async {
        if conversation?.id == id { newConversation() }
        do {
            try await repository.delete(id: id)
            history.removeAll { $0.id == id }
            historyErrorMessage = nil
        } catch { historyErrorMessage = safeMessage(for: error) }
    }

    public func clearError() { errorMessage = nil }

    private func perform(text: String, in draft: Conversation) async {
        let token = UUID()
        generation = token
        requestState = .working
        let userMessage = ChatMessage(role: .user, content: text)
        pendingUserMessage = userMessage
        streamedText = ""
        streamingMessage = ChatMessage(role: .assistant, content: "")
        lastStreamPublication = .now
        errorMessage = nil
        let settings = settings
        let client = client
        let repository = repository
        let task = Task<Conversation, any Error> { [self] in
            let key = try await settings.credential(for: draft.configuration)
            try Task.checkCancellation()
            let messages = draft.messages + [userMessage]
            try await client.stream(configuration: draft.configuration, apiKey: key, messages: messages) {
                [weak self] delta in
                try await self?.receive(delta, generation: token)
            }
            try Task.checkCancellation()
            guard self.generation == token else { throw CancellationError() }
            self.publishStream()
            guard let response = self.streamingMessage,
                !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw CopilotError.emptyResponse }
            var completed = draft
            completed.messages = messages + [response]
            completed.updatedAt = Date()
            // A failed/cancelled request never persists a lone user message.
            return try await repository.upsert(completed)
        }
        operation = task
        do {
            let completed = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard generation == token else { return }
            conversation = completed
            streamingMessage = nil
            pendingUserMessage = nil
            operation = nil
            requestState = .idle
            await loadHistory(query: historyQuery)
        } catch {
            guard generation == token else { return }
            publishStream()
            pendingUserMessage = nil
            operation = nil
            if error is CancellationError || Task.isCancelled {
                requestState = .cancelled
            } else {
                requestState = .failed
                errorMessage = safeMessage(for: error)
            }
        }
    }

    private func receive(_ delta: String, generation token: UUID) throws {
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        let first = streamedText.isEmpty
        streamedText += delta
        if first || lastStreamPublication.duration(to: .now) >= .milliseconds(50) { publishStream() }
    }

    private func publishStream() {
        guard !streamedText.isEmpty else { streamingMessage = nil; return }
        if let message = streamingMessage {
            streamingMessage = ChatMessage(
                id: message.id, role: .assistant, content: streamedText, createdAt: message.createdAt)
        }
        lastStreamPublication = .now
    }
}
