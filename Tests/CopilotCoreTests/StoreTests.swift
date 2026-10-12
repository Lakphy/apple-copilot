import Foundation
import Testing
@testable import CopilotCore

@Suite("Observable MV state and failure boundaries")
@MainActor
struct StoreTests {
    @Test func saveReadinessUsesValidatedDraftAndEndpointCredentialIdentity() async throws {
        let settings = await configuredSettings()
        #expect(!settings.canSave)
        #expect(settings.canRetainAPIKey)

        settings.configuration.model = "another-model"
        #expect(settings.canSave)
        settings.apiKey = "header\ninjection"
        #expect(!settings.canSave)
        #expect(settings.validationMessage == CopilotError.invalidConfiguration("API Key 不能包含换行。").localizedDescription)
        await settings.save()
        #expect(settings.errorMessage == settings.validationMessage)
        #expect(try await settings.credential() == "fixture-key")

        settings.apiKey = ""
        settings.configuration.baseURL = "https://another-provider.example/v1"
        #expect(!settings.canRetainAPIKey)
        #expect(!settings.canSave)
        settings.apiKey = "replacement-key"
        #expect(settings.canSave)
        settings.configuration.model = " "
        #expect(!settings.canSave)
    }

    private func configuredSettings() async -> SettingsStore {
        let settings = SettingsStore(repository: MemorySettingsRepository(), credentials: MemoryCredentialStore())
        settings.apiKey = "fixture-key"
        await settings.save()
        return settings
    }

    @Test func loadingReportsSavedCredentialWithoutPuttingSecretInField() async throws {
        let credentials = MemoryCredentialStore()
        try await credentials.save("private-key", account: ProviderConfiguration.default.credentialAccount)
        let settings = SettingsStore(repository: MemorySettingsRepository(), credentials: credentials)
        await settings.load()
        #expect(settings.hasSavedAPIKey)
        #expect(settings.apiKey.isEmpty)
        #expect(try await settings.credential() == "private-key")
    }

    @Test func completingDeepSeekURLRetainsSavedKeyAndHistoryCredentialIdentity() async throws {
        let original = ProviderConfiguration(baseURL: "https://api.deepseek.com", model: "deepseek-flash")
        let credentials = MemoryCredentialStore()
        try await credentials.save("fixture-key", account: original.credentialAccount)
        let settings = SettingsStore(
            repository: MemorySettingsRepository(configuration: original), credentials: credentials)
        await settings.load()
        settings.configuration.baseURL = try original.resolvedEndpoint().absoluteString
        await settings.save()
        #expect(settings.errorMessage == nil)
        #expect(!settings.hasUnsavedChanges)
        #expect(settings.savedConfiguration.baseURL == "https://api.deepseek.com/v1/chat/completions")
        #expect(try await settings.credential(for: original) == "fixture-key")
    }

    @Test func refreshingReusedSettingsSwitchesNewTranslationFromLoopbackToDeepSeek() async throws {
        let local = ProviderConfiguration(
            baseURL: "http://localhost:56343/v1", model: "copilot-test-model", allowLocalHTTP: true)
        let repository = MemorySettingsRepository(configuration: local)
        let credentials = MemoryCredentialStore()
        try await credentials.save("local-key", account: local.credentialAccount)
        let settings = SettingsStore(repository: repository, credentials: credentials)
        await settings.load()
        let remote = ProviderConfiguration(baseURL: "https://api.deepseek.com", model: "deepseek-flash")
        await repository.save(remote)
        try await credentials.save("remote-key", account: remote.credentialAccount)
        // Matches the extension re-reading configuration before a new sheet's translation.
        await settings.refresh()
        let client = RecordingClient()
        let store = ConversationStore(client: client, repository: MemoryConversationRepository(), settings: settings)
        await store.translate("test")
        #expect(store.requestState == .idle)
        #expect(await client.requests.first?.configuration == remote)
        #expect(try await settings.credential() == "remote-key")
    }

    @Test func unsavedEndpointEditsCannotReceiveSavedCredential() async throws {
        let settings = await configuredSettings()
        settings.configuration.baseURL = "https://untrusted.example/v1"
        #expect(settings.hasUnsavedChanges)
        #expect(settings.savedConfiguration.baseURL == ProviderConfiguration.default.baseURL)
        #expect(try await settings.credential() == "fixture-key")
        await #expect(throws: CopilotError.providerChanged) {
            try await settings.credential(for: settings.configuration)
        }
        await settings.save()
        #expect(settings.savedConfiguration.baseURL == ProviderConfiguration.default.baseURL)
        #expect(settings.errorMessage == CopilotError.missingAPIKey.localizedDescription)
    }

    @Test func translationAndFollowUpCarryFullHistoryAndOriginalConfiguration() async throws {
        let settings = await configuredSettings()
        let client = RecordingClient()
        let repository = MemoryConversationRepository()
        let store = ConversationStore(client: client, repository: repository, settings: settings)
        await store.translate("Hello", targetLanguage: "French")
        #expect(store.conversation?.configuration.targetLanguage == "French")
        #expect(store.conversation?.messages.map(\.role) == [.user, .assistant])
        settings.configuration.model = "new-model"
        settings.configuration.translationPrompt = "Different prompt"
        await settings.save()
        await store.ask("Explain the greeting")
        let requests = await client.requests
        #expect(requests.count == 2)
        #expect(requests[1].messages.map(\.content) == ["Hello", "Bonjour", "Explain the greeting"])
        #expect(requests[1].configuration.model == ProviderConfiguration.default.model)
        #expect(requests[1].configuration.translationPrompt == ProviderConfiguration.default.translationPrompt)
        #expect(store.conversation?.messages.count == 4)
        #expect(store.history.first?.messages.count == 4)
    }

    @Test func changedProviderRefusesHistoryFollowUpRatherThanUsingNewKey() async throws {
        let settings = await configuredSettings()
        let client = RecordingClient()
        let store = ConversationStore(client: client, repository: MemoryConversationRepository(), settings: settings)
        await store.translate("Hello")
        settings.configuration.baseURL = "https://new-provider.example/v1"
        settings.apiKey = "other-key"
        await settings.save()
        await store.ask("Why?")
        #expect(store.requestState == .failed)
        #expect(store.errorMessage == CopilotError.providerChanged.localizedDescription)
        #expect(await client.requests.count == 1)
        #expect(store.conversation?.messages.count == 2)
    }

    @Test func failedTranslationDoesNotPersistAnOrphanUserMessage() async throws {
        let settings = await configuredSettings()
        let client = RecordingClient(failure: .httpStatus(429))
        let repository = MemoryConversationRepository()
        let store = ConversationStore(client: client, repository: repository, settings: settings)
        await store.translate("Hello")
        #expect(store.requestState == .failed)
        #expect(!store.isWorking)
        #expect(store.pendingMessage == nil)
        #expect(store.conversation?.messages.isEmpty == true)
        #expect(await repository.history().isEmpty)
    }

    @Test func failedFollowUpCanRetryWithoutDuplicatingTheQuestion() async throws {
        let settings = await configuredSettings()
        let client = RecordingClient()
        let store = ConversationStore(client: client, repository: MemoryConversationRepository(), settings: settings)
        await store.translate("Hello")
        await client.setFailure(.httpStatus(500))
        await store.ask("Why?")
        #expect(store.conversation?.messages.count == 2)
        await client.setFailure(nil)
        await store.ask("Why?")
        #expect(store.conversation?.messages.count == 4)
        #expect(store.conversation?.messages.filter { $0.content == "Why?" }.count == 1)
    }

    @Test func cancellingIgnoresLateResponseAndPreservesNewSelection() async throws {
        let settings = await configuredSettings()
        let client = GateClient()
        let repository = MemoryConversationRepository()
        let store = ConversationStore(client: client, repository: repository, settings: settings)
        let pending = Task { await store.translate("Cancel me") }
        await client.waitUntilStarted()
        #expect(store.isWorking)
        store.cancel()
        #expect(store.requestState == .cancelled)
        #expect(store.pendingMessage == nil)
        store.select(CopilotPreviewFixtures.conversation)
        await client.release("late translation")
        await pending.value
        #expect(store.conversation?.id == CopilotPreviewFixtures.conversation.id)
        #expect(store.conversation?.messages.count == 2)
        #expect(await repository.history().isEmpty)
    }

    @Test func cancellingOwningTaskCancelsTheRequestAndLeavesNoHistory() async throws {
        let settings = await configuredSettings()
        let client = GateClient()
        let repository = MemoryConversationRepository()
        let store = ConversationStore(client: client, repository: repository, settings: settings)
        let pending = Task { await store.translate("Cancel me") }
        await client.waitUntilStarted()
        pending.cancel()
        await client.release("late translation")
        await pending.value
        #expect(store.requestState == .cancelled)
        #expect(!store.isWorking)
        #expect(store.conversation?.messages.isEmpty == true)
        #expect(await repository.history().isEmpty)
    }

    @Test func storageFailureDoesNotPublishASuccessfulUnstoredTurn() async throws {
        let settings = await configuredSettings()
        let store = ConversationStore(
            client: RecordingClient(), repository: FailingConversationRepository(), settings: settings)
        await store.translate("Hello")
        #expect(store.requestState == .failed)
        #expect(store.conversation?.messages.isEmpty == true)
        #expect(store.errorMessage == CopilotError.storageUnavailable.localizedDescription)
    }

    @Test func historyFailureIsDistinctFromTranslationFailure() async throws {
        let settings = await configuredSettings()
        let store = ConversationStore(
            client: RecordingClient(), repository: FailingConversationRepository(), settings: settings)
        await store.loadHistory()
        #expect(store.historyErrorMessage == CopilotError.storageUnavailable.localizedDescription)
        #expect(store.errorMessage == nil)
        #expect(!store.isLoadingHistory)
    }

    @Test func lockedKeychainIsReportedAndDoesNotPretendConfigurationLoaded() async throws {
        let settings = SettingsStore(repository: MemorySettingsRepository(), credentials: LockedCredentialStore())
        await settings.load()
        #expect(!settings.isLoaded)
        #expect(!settings.hasSavedAPIKey)
        #expect(settings.apiKey.isEmpty)
        #expect(settings.errorMessage == CopilotError.credentialUnavailable(-25308).localizedDescription)
    }

    @Test func refreshPicksUpExternallySavedSettingsAndCredentialReadiness() async throws {
        let repository = MemorySettingsRepository()
        let credentials = MemoryCredentialStore()
        let settings = SettingsStore(repository: repository, credentials: credentials)
        await settings.load()
        #expect(!settings.hasSavedAPIKey)
        var external = ProviderConfiguration.default
        external.baseURL = "https://external-provider.example/v1"
        external.model = "externally-selected-model"
        await repository.save(external)
        try await credentials.save("external-key", account: external.credentialAccount)
        await settings.refresh()
        #expect(settings.savedConfiguration == external)
        #expect(settings.configuration == external)
        #expect(settings.hasSavedAPIKey)
        #expect(settings.apiKey.isEmpty)
        #expect(try await settings.credential() == "external-key")
    }

    @Test func refreshUpdatesSavedSnapshotWithoutDiscardingDirtyDraftOrReplacementKey() async throws {
        let repository = MemorySettingsRepository()
        let settings = SettingsStore(repository: repository, credentials: MemoryCredentialStore())
        await settings.load()
        settings.configuration.model = "my-unsaved-model"
        settings.apiKey = "my-unsaved-key"
        let draft = settings.configuration
        var external = ProviderConfiguration.default
        external.model = "external-model"
        await repository.save(external)
        await settings.refresh()
        #expect(settings.savedConfiguration == external)
        #expect(settings.configuration == draft)
        #expect(settings.apiKey == "my-unsaved-key")
        #expect(settings.hasUnsavedChanges)
    }

    @Test func refreshFailurePreservesPreviouslyLoadedConfigurationAndCredentialReadiness() async throws {
        let repository = ToggleSettingsRepository()
        let credentials = MemoryCredentialStore()
        try await credentials.save("saved-key", account: ProviderConfiguration.default.credentialAccount)
        let settings = SettingsStore(repository: repository, credentials: credentials)
        await settings.load()
        await repository.setFailing(true)
        await settings.refresh()
        #expect(settings.savedConfiguration == .default)
        #expect(settings.configuration == .default)
        #expect(settings.hasSavedAPIKey)
        #expect(settings.isLoaded)
        #expect(!settings.isLoading)
        #expect(settings.errorMessage == CopilotError.storageUnavailable.localizedDescription)
    }
}

private struct RecordedRequest: Sendable {
    let configuration: ProviderConfiguration
    let messages: [ChatMessage]
}

private actor RecordingClient: LanguageModelClient {
    var requests: [RecordedRequest] = []
    private var failure: CopilotError?
    init(failure: CopilotError? = nil) { self.failure = failure }
    func setFailure(_ failure: CopilotError?) { self.failure = failure }
    func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String
    {
        requests.append(RecordedRequest(configuration: configuration, messages: messages))
        if let failure { throw failure }
        return "Bonjour"
    }
}

private actor GateClient: LanguageModelClient {
    private var started = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var response: CheckedContinuation<String, Never>?
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release(_ value: String) { response?.resume(returning: value); response = nil }
    func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String
    {
        return await withCheckedContinuation { continuation in
            response = continuation
            started = true
            waiting.forEach { $0.resume() }
            waiting = []
        }
    }
}

private struct FailingConversationRepository: ConversationRepository {
    func history(query: String) async throws -> [Conversation] { throw CopilotError.storageUnavailable }
    func load(id: UUID) async throws -> Conversation? { throw CopilotError.storageUnavailable }
    func upsert(_ conversation: Conversation) async throws -> Conversation { throw CopilotError.storageUnavailable }
    func delete(id: UUID) async throws { throw CopilotError.storageUnavailable }
}

private struct LockedCredentialStore: CredentialStore {
    func load(account: String) async throws -> String? { throw CopilotError.credentialUnavailable(-25308) }
    func save(_ key: String, account: String) async throws { throw CopilotError.credentialUnavailable(-25308) }
    func delete(account: String) async throws { throw CopilotError.credentialUnavailable(-25308) }
}

private actor ToggleSettingsRepository: SettingsRepository {
    private var failing = false
    func setFailing(_ failing: Bool) { self.failing = failing }
    func load() throws -> ProviderConfiguration {
        if failing { throw CopilotError.storageUnavailable }
        return .default
    }
    func save(_ configuration: ProviderConfiguration) {}
}
