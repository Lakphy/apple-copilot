import Foundation

/// A persisted conversation role; system instructions are supplied separately.
public enum MessageRole: String, Codable, Sendable {
    case user, assistant
}

/// An immutable message whose stable identity is retained from streaming through persistence.
public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let createdAt: Date

    public init(id: UUID = UUID(), role: MessageRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

/// Source text, completed message pairs, and the provider configuration captured at creation.
public struct Conversation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceText: String
    public let configuration: ProviderConfiguration
    public var messages: [ChatMessage]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), sourceText: String, configuration: ProviderConfiguration,
        messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.configuration = configuration
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A whitespace-normalized source excerpt for history rows.
    ///
    /// - Complexity: O(*n*) in the source text's length.
    public var title: String {
        let flattened = sourceText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(flattened.prefix(70))
    }

    /// The first completed assistant response, if translation has succeeded.
    ///
    /// - Complexity: O(*n*) in the number of messages.
    public var translation: String? { messages.first(where: { $0.role == .assistant })?.content }
}
