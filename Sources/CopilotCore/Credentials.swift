import Foundation
import Security

/// Stores credentials separately from Codable settings and conversation history.
public protocol CredentialStore: Sendable {
    /// Returns the credential for an endpoint identity, or nil when it is absent.
    func load(account: String) async throws -> String?
    /// Adds or replaces the credential for an endpoint identity.
    func save(_ key: String, account: String) async throws
    /// Removes a credential, succeeding when the identity is already absent.
    func delete(account: String) async throws
}

/// Shared by settings validation and request construction so header rules cannot drift.
func validatedAPIKey(_ value: String) throws -> String {
    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.contains(where: { $0.isNewline }) else {
        throw CopilotError.invalidConfiguration("API Key 不能包含换行。")
    }
    return key
}

/// No secrets are logged, Codable, or stored in preferences. SecItem calls run on this actor.
public actor KeychainCredentialStore: CredentialStore {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.applecopilot.credentials", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func identity(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    public func load(account: String) throws -> String? {
        var query = identity(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw CopilotError.credentialUnavailable(errSecDecode)
            }
            return key
        case errSecItemNotFound: return nil
        default: throw CopilotError.credentialUnavailable(status)
        }
    }

    public func save(_ key: String, account: String) throws {
        let identity = identity(account: account)
        var add = identity
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(add as CFDictionary, nil) {
        case errSecSuccess: return
        case errSecDuplicateItem:
            let status = SecItemUpdate(
                identity as CFDictionary,
                [
                    kSecValueData as String: Data(key.utf8),
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                ] as CFDictionary)
            guard status == errSecSuccess else { throw CopilotError.credentialUnavailable(status) }
        case let status: throw CopilotError.credentialUnavailable(status)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(identity(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CopilotError.credentialUnavailable(status)
        }
    }
}

/// Deterministic previews and tests only. Production uses KeychainCredentialStore.
public actor MemoryCredentialStore: CredentialStore {
    private var keys: [String: String] = [:]
    public init() {}
    public func load(account: String) -> String? { keys[account] }
    public func save(_ key: String, account: String) { keys[account] = key }
    public func delete(account: String) { keys.removeValue(forKey: account) }
}
