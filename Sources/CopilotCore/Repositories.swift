import Foundation
import Darwin

public protocol SettingsRepository: Sendable {
    func load() async throws -> ProviderConfiguration
    func save(_ configuration: ProviderConfiguration) async throws
}

public protocol ConversationRepository: Sendable {
    func history(query: String) async throws -> [Conversation]
    func load(id: UUID) async throws -> Conversation?
    /// Commits complete turns and merges any independently committed messages for the same ID.
    func upsert(_ conversation: Conversation) async throws -> Conversation
    func delete(id: UUID) async throws
}

public actor FileSettingsRepository: SettingsRepository {
    private let rootURL: URL
    public init(rootURL: URL) { self.rootURL = rootURL }

    public func load() throws -> ProviderConfiguration {
        try withFileLock(rootURL: rootURL) {
            let file = rootURL.appendingPathComponent("settings.json")
            guard FileManager.default.fileExists(atPath: file.path) else { return .default }
            do { return try JSONDecoder().decode(ProviderConfiguration.self, from: Data(contentsOf: file)) }
            catch { throw CopilotError.storageUnavailable }
        }
    }

    public func save(_ configuration: ProviderConfiguration) throws {
        try configuration.validate()
        try withFileLock(rootURL: rootURL) {
            try writeJSON(configuration, to: rootURL.appendingPathComponent("settings.json"))
        }
    }
}

/// Each conversation has its own atomic JSON file. A filesystem lock serializes read/merge/write
/// across app and extension processes; writing one history item cannot overwrite another item.
public actor FileConversationRepository: ConversationRepository {
    private let rootURL: URL
    public init(rootURL: URL) { self.rootURL = rootURL }
    private var directory: URL { rootURL.appendingPathComponent("Conversations", isDirectory: true) }
    private func file(id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func tombstone(id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".deleted") }

    public func history(query: String = "") throws -> [Conversation] {
        try withFileLock(rootURL: rootURL) {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            do {
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                let conversations = try files.filter { $0.pathExtension == "json" }.map {
                    try JSONDecoder().decode(Conversation.self, from: Data(contentsOf: $0))
                }
                return filteredHistory(conversations, query: query)
            } catch { throw CopilotError.storageUnavailable }
        }
    }

    public func load(id: UUID) throws -> Conversation? {
        try withFileLock(rootURL: rootURL) { try readConversation(id: id) }
    }

    public func upsert(_ conversation: Conversation) throws -> Conversation {
        try Task.checkCancellation()
        return try withFileLock(rootURL: rootURL) {
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { throw CopilotError.storageUnavailable }
            guard !FileManager.default.fileExists(atPath: tombstone(id: conversation.id).path) else {
                throw CopilotError.conversationDeleted
            }
            let merged = try mergeConversation(conversation, existing: readConversation(id: conversation.id))
            try Task.checkCancellation()
            try writeJSON(merged, to: file(id: merged.id))
            return merged
        }
    }

    public func delete(id: UUID) throws {
        try withFileLock(rootURL: rootURL) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                // The tombstone prevents a late in-flight response in another process resurrecting it.
                try Data().write(to: tombstone(id: id), options: .atomic)
                if FileManager.default.fileExists(atPath: file(id: id).path) {
                    try FileManager.default.removeItem(at: file(id: id))
                }
            } catch { throw CopilotError.storageUnavailable }
        }
    }

    private func readConversation(id: UUID) throws -> Conversation? {
        guard !FileManager.default.fileExists(atPath: tombstone(id: id).path),
              FileManager.default.fileExists(atPath: file(id: id).path) else { return nil }
        do { return try JSONDecoder().decode(Conversation.self, from: Data(contentsOf: file(id: id))) }
        catch { throw CopilotError.storageUnavailable }
    }
}

private func withFileLock<T>(rootURL: URL, operation: () throws -> T) throws -> T {
    do { try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true) }
    catch { throw CopilotError.storageUnavailable }
    let lockURL = rootURL.appendingPathComponent(".repository.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw CopilotError.storageUnavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw CopilotError.storageUnavailable }
    defer { flock(descriptor, LOCK_UN) }
    return try operation()
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    } catch { throw CopilotError.storageUnavailable }
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
