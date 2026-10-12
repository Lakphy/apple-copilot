import Foundation
import Observation

/// Editable settings and a saved snapshot, with endpoint-scoped credentials.
@MainActor
@Observable
public final class SettingsStore {
    public var configuration: ProviderConfiguration
    /// Replacement credential draft; loading never places a saved secret in a text field.
    public var apiKey = ""
    public private(set) var savedConfiguration: ProviderConfiguration
    public private(set) var hasSavedAPIKey = false
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var isLoaded = false

    @ObservationIgnored private let repository: any SettingsRepository
    @ObservationIgnored private let credentials: any CredentialStore

    public var hasUnsavedChanges: Bool { configuration != savedConfiguration || !apiKey.isEmpty }

    /// A safe explanation of invalid draft values, independent of UI presentation.
    public var validationMessage: String? {
        do {
            try configuration.validate()
            _ = try validatedAPIKey(apiKey)
            return nil
        } catch {
            return safeMessage(for: error)
        }
    }

    /// Whether leaving the credential draft empty retains this endpoint's saved key.
    public var canRetainAPIKey: Bool {
        guard hasSavedAPIKey,
            let account = try? configuration.credentialAccount,
            let savedAccount = try? savedConfiguration.credentialAccount
        else { return false }
        return account == savedAccount
    }

    /// Whether the draft is valid, changed, and has a usable credential.
    ///
    /// Startup capability failures are handled separately by the app environment.
    public var canSave: Bool {
        validationMessage == nil && !isLoading && !isSaving && hasUnsavedChanges
            && (canRetainAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public init(repository: any SettingsRepository, credentials: any CredentialStore) {
        self.repository = repository
        self.credentials = credentials
        self.configuration = .default
        self.savedConfiguration = .default
    }

    public func load() async {
        guard !isLoading, !isLoaded else { return }
        await refresh()
    }

    /// Reload settings shared with an extension, preserving any local edits in progress.
    public func refresh() async {
        guard !isLoading, !isSaving else { return }
        let previousSaved = savedConfiguration
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let saved = try await repository.load()
            try saved.validate()
            let key = try await credentials.load(account: saved.credentialAccount)
            if configuration == previousSaved && apiKey.isEmpty {
                configuration = saved
            }
            savedConfiguration = saved
            hasSavedAPIKey = !(key ?? "").isEmpty
            isLoaded = true
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    public func save() async {
        guard !isSaving, !isLoading else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let draft = configuration
        do {
            try draft.validate()
            let replacement = try validatedAPIKey(apiKey)
            let account = try draft.credentialAccount
            let oldAccount = try savedConfiguration.credentialAccount
            if !replacement.isEmpty {
                try await credentials.save(replacement, account: account)
            } else {
                guard account == oldAccount,
                    let existing = try await credentials.load(account: account), !existing.isEmpty
                else {
                    throw CopilotError.missingAPIKey
                }
            }
            try await repository.save(draft)
            savedConfiguration = draft
            hasSavedAPIKey = true
            isLoaded = true
            // Don't discard edits made while awaiting Keychain/file I/O.
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == replacement { apiKey = "" }
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    public func credential(for configuration: ProviderConfiguration? = nil) async throws -> String {
        guard isLoaded else { throw CopilotError.missingAPIKey }
        let effective = configuration ?? savedConfiguration
        let account = try effective.credentialAccount
        guard account == (try savedConfiguration.credentialAccount) else { throw CopilotError.providerChanged }
        guard let key = try await credentials.load(account: account), !key.isEmpty else {
            throw CopilotError.missingAPIKey
        }
        return key
    }

    public func discardDraft() {
        configuration = savedConfiguration
        apiKey = ""
        errorMessage = nil
    }

    public func clearError() { errorMessage = nil }
}
