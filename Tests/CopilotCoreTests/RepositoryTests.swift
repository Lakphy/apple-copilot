import Foundation
import Testing
@testable import CopilotCore

@Suite("Durable cross-process history")
struct RepositoryTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func settingsRoundTripContainsNoSecret() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileSettingsRepository(rootURL: root)
        var config = ProviderConfiguration.default
        config.translationPrompt = "Translate {targetLanguage}, preserving paragraph breaks."
        try await repository.save(config)
        #expect(try await repository.load() == config)
        let body = try String(contentsOf: root.appendingPathComponent("settings.json"), encoding: .utf8)
        #expect(!body.contains("apiKey"))
    }

    @Test func independentWritersDoNotOverwriteOtherHistoryItems() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = FileConversationRepository(rootURL: root)
        let second = FileConversationRepository(rootURL: root)
        let one = Conversation(sourceText: "one", configuration: .default)
        let two = Conversation(sourceText: "two", configuration: .default)
        let snapshotOne = one
        let snapshotTwo = two
        async let savedOne = first.upsert(snapshotOne)
        async let savedTwo = second.upsert(snapshotTwo)
        _ = try await (savedOne, savedTwo)
        #expect(try await first.history().count == 2)
        #expect(try await second.load(id: one.id) == one)
    }

    @Test func concurrentStaleCopiesMergeMessagesWithoutDroppingTurns() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = FileConversationRepository(rootURL: root)
        let second = FileConversationRepository(rootURL: root)
        var one = Conversation(sourceText: "hello", configuration: .default)
        one.messages = [ChatMessage(role: .user, content: "hello"), ChatMessage(role: .assistant, content: "你好")]
        var two = one
        one.messages.append(contentsOf: [ChatMessage(role: .user, content: "first"), ChatMessage(role: .assistant, content: "first reply")])
        two.messages.append(contentsOf: [ChatMessage(role: .user, content: "second"), ChatMessage(role: .assistant, content: "second reply")])
        let snapshotOne = one
        let snapshotTwo = two
        async let savedOne = first.upsert(snapshotOne)
        async let savedTwo = second.upsert(snapshotTwo)
        _ = try await (savedOne, savedTwo)
        let merged = try #require(try await first.load(id: one.id))
        #expect(merged.messages.count == 6)
        #expect(Set(merged.messages.map(\.content)) == ["hello", "你好", "first", "first reply", "second", "second reply"])
    }

    @Test func deletingPreventsALateRequestFromResurrectingHistory() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileConversationRepository(rootURL: root)
        let conversation = Conversation(sourceText: "discard", configuration: .default)
        _ = try await repository.upsert(conversation)
        try await repository.delete(id: conversation.id)
        #expect(try await repository.load(id: conversation.id) == nil)
        await #expect(throws: CopilotError.conversationDeleted) { try await repository.upsert(conversation) }
    }

    @Test func searchFindsFollowUpContentAndPreservesSnapshot() async throws {
        let repository = MemoryConversationRepository()
        let config = ProviderConfiguration(model: "my-model", translationPrompt: "My original prompt", targetLanguage: "French")
        let conversation = Conversation(sourceText: "hello", configuration: config, messages: [ChatMessage(role: .assistant, content: "Bonjour")])
        _ = try await repository.upsert(conversation)
        let history = await repository.history(query: "Bonjour")
        #expect(history.first?.configuration == config)
        #expect(history.count == 1)
    }
}
