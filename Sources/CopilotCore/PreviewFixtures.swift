import Foundation

/// Preview rendering never makes a live API request.
public struct PreviewLanguageModelClient: LanguageModelClient {
    public init() {}
    public func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws
        -> String
    {
        try Task.checkCancellation()
        return messages.count == 1 ? "好的设计让复杂的事情变得简单。" : "这里的 simple 强调易于理解与使用，可以译为“简单”或“简洁”。"
    }
}

public enum CopilotPreviewFixtures {
    public static let conversation = Conversation(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        sourceText: "Good design makes complex things simple.", configuration: .default,
        messages: [
            ChatMessage(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
                role: .user, content: "Good design makes complex things simple.",
                createdAt: Date(timeIntervalSince1970: 1_750_000_000)),
            ChatMessage(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
                role: .assistant, content: "好的设计让复杂的事情变得简单。",
                createdAt: Date(timeIntervalSince1970: 1_750_000_001)),
        ], createdAt: Date(timeIntervalSince1970: 1_750_000_000), updatedAt: Date(timeIntervalSince1970: 1_750_000_001)
    )

    @MainActor public static func settings() -> SettingsStore {
        SettingsStore(repository: MemorySettingsRepository(), credentials: MemoryCredentialStore())
    }

    @MainActor public static func conversations(settings: SettingsStore) -> ConversationStore {
        let store = ConversationStore(
            client: PreviewLanguageModelClient(),
            repository: MemoryConversationRepository(conversations: [conversation]), settings: settings)
        store.select(conversation)
        return store
    }
}
