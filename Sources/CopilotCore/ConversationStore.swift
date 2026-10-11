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
    public private(set) var pendingMessage: String?
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
        self.conversation = conversation
        requestState = .idle
        errorMessage = nil
    }

    public func newConversation() {
        cancel()
        conversation = nil
        requestState = .idle
        errorMessage = nil
    }

    public func cancel() {
        guard isWorking else { return }
        generation = UUID()
        operation?.cancel()
        operation = nil
        pendingMessage = nil
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
        pendingMessage = text
        errorMessage = nil
        let userMessage = ChatMessage(role: .user, content: text)
        let settings = settings
        let client = client
        let repository = repository
        let task = Task<Conversation, any Error> {
            let key = try await settings.credential(for: draft.configuration)
            try Task.checkCancellation()
            let messages = draft.messages + [userMessage]
            let response = try await client.complete(configuration: draft.configuration, apiKey: key, messages: messages)
            try Task.checkCancellation()
            var completed = draft
            completed.messages = messages + [ChatMessage(role: .assistant, content: response)]
            completed.updatedAt = Date()
            // A failed/cancelled request never persists a lone user message.
            return try await repository.upsert(completed)
        }
        operation = task
        do {
            let completed = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            guard generation == token else { return }
            conversation = completed
            pendingMessage = nil
            operation = nil
            requestState = .idle
            await loadHistory(query: historyQuery)
        } catch {
            guard generation == token else { return }
            pendingMessage = nil
            operation = nil
            if error is CancellationError || Task.isCancelled {
                requestState = .cancelled
            } else {
                requestState = .failed
                errorMessage = safeMessage(for: error)
            }
        }
    }
}

public enum CopilotPreviewFixtures {
    public static let conversation = Conversation(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        sourceText: "Good design makes complex things simple.", configuration: .default,
        messages: [
            ChatMessage(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
                        role: .user, content: "Good design makes complex things simple.",
                        createdAt: Date(timeIntervalSince1970: 1_750_000_000)),
            ChatMessage(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
                        role: .assistant, content: "好的设计让复杂的事情变得简单。",
                        createdAt: Date(timeIntervalSince1970: 1_750_000_001))
        ], createdAt: Date(timeIntervalSince1970: 1_750_000_000), updatedAt: Date(timeIntervalSince1970: 1_750_000_001)
    )

    @MainActor public static func settings() -> SettingsStore {
        SettingsStore(repository: MemorySettingsRepository(), credentials: MemoryCredentialStore())
    }

    @MainActor public static func conversations(settings: SettingsStore) -> ConversationStore {
        let store = ConversationStore(client: PreviewLanguageModelClient(),
                                      repository: MemoryConversationRepository(conversations: [conversation]), settings: settings)
        store.select(conversation)
        return store
    }
}
