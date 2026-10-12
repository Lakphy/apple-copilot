import Foundation

public actor MemorySettingsRepository: SettingsRepository {
    private var configuration: ProviderConfiguration
    public init(configuration: ProviderConfiguration = .default) { self.configuration = configuration }
    public func load() -> ProviderConfiguration { configuration }
    public func save(_ configuration: ProviderConfiguration) { self.configuration = configuration }
}

public actor MemoryConversationRepository: ConversationRepository {
    private var conversations: [UUID: Conversation]
    private var deleted: Set<UUID> = []
    public init(conversations: [Conversation] = []) {
        self.conversations = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
    }
    public func history(query: String = "") -> [Conversation] {
        filteredHistory(Array(conversations.values), query: query)
    }
    public func load(id: UUID) -> Conversation? { conversations[id] }
    public func upsert(_ conversation: Conversation) throws -> Conversation {
        try Task.checkCancellation()
        guard !deleted.contains(conversation.id) else { throw CopilotError.conversationDeleted }
        let merged = try mergeConversation(conversation, existing: conversations[conversation.id])
        conversations[conversation.id] = merged
        return merged
    }
    public func delete(id: UUID) {
        deleted.insert(id)
        conversations.removeValue(forKey: id)
    }
}
