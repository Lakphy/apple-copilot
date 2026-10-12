import Foundation

/// Persists nonsecret provider preferences independently of credentials.
public protocol SettingsRepository: Sendable {
    /// Returns saved preferences, or defaults when no configuration has been stored.
    func load() async throws -> ProviderConfiguration
    /// Stores the given nonsecret provider preferences.
    func save(_ configuration: ProviderConfiguration) async throws
}

/// Persists completed conversations and reconciles concurrent app/extension writes.
public protocol ConversationRepository: Sendable {
    /// Returns matching conversations ordered by most recently updated first.
    func history(query: String) async throws -> [Conversation]
    /// Returns a conversation, or nil when it does not exist or has been deleted.
    func load(id: UUID) async throws -> Conversation?
    /// Commits complete turns and merges any independently committed messages for the same ID.
    func upsert(_ conversation: Conversation) async throws -> Conversation
    /// Deletes a conversation and prevents a late writer from resurrecting it.
    func delete(id: UUID) async throws
}

func mergeConversation(_ incoming: Conversation, existing: Conversation?) throws -> Conversation {
    guard var existing else { return incoming }
    guard existing.configuration == incoming.configuration, existing.sourceText == incoming.sourceText else {
        throw CopilotError.conversationConflict
    }
    let knownIDs = Set(existing.messages.map(\.id))
    existing.messages.append(contentsOf: incoming.messages.filter { !knownIDs.contains($0.id) })
    existing.updatedAt = max(existing.updatedAt, incoming.updatedAt)
    return existing
}

func filteredHistory(_ conversations: [Conversation], query: String) -> [Conversation] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return conversations.filter { conversation in
        query.isEmpty || conversation.sourceText.localizedStandardContains(query)
            || conversation.messages.contains { $0.content.localizedStandardContains(query) }
    }.sorted { $0.updatedAt > $1.updatedAt }
}
