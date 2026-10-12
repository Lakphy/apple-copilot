import Foundation

public actor FileSettingsRepository: SettingsRepository {
    private let rootURL: URL
    public init(rootURL: URL) { self.rootURL = rootURL }

    public func load() throws -> ProviderConfiguration {
        try withFileLock(rootURL: rootURL) {
            let file = rootURL.appendingPathComponent("settings.json")
            guard FileManager.default.fileExists(atPath: file.path) else { return .default }
            do { return try JSONDecoder().decode(ProviderConfiguration.self, from: Data(contentsOf: file)) } catch {
                throw CopilotError.storageUnavailable
            }
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
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch {
                throw CopilotError.storageUnavailable
            }
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
            FileManager.default.fileExists(atPath: file(id: id).path)
        else { return nil }
        do { return try JSONDecoder().decode(Conversation.self, from: Data(contentsOf: file(id: id))) } catch {
            throw CopilotError.storageUnavailable
        }
    }
}
