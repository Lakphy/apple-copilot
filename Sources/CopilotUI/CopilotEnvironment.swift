import CopilotCore
import Foundation
import Observation

public enum AppSection: String, CaseIterable, Identifiable {
    case translate, history, settings
    public var id: Self { self }
    public var title: String {
        switch self {
        case .translate: "翻译"
        case .history: "历史"
        case .settings: "设置"
        }
    }
    public var symbol: String {
        switch self {
        case .translate: "character.bubble.fill"
        case .history: "clock.fill"
        case .settings: "gearshape.fill"
        }
    }
}

@MainActor @Observable
public final class CopilotEnvironment {
    public let settings: SettingsStore
    public let session: ConversationStore
    public let startupMessage: String?
    public var section: AppSection = .translate
    public var sourceDraft = ""
    public var questionDraft = ""
    public private(set) var newTranslationID = UUID()
    private let client: any LanguageModelClient
    private let conversations: any ConversationRepository
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(settings: SettingsStore, client: any LanguageModelClient,
                conversations: any ConversationRepository, startupMessage: String? = nil) {
        self.settings = settings
        self.client = client
        self.conversations = conversations
        self.startupMessage = startupMessage
        self.session = ConversationStore(client: client, repository: conversations, settings: settings)
    }

    public func load() async {
        guard !hasLoaded else { return }
        let task: Task<Void, Never>
        if let loadTask {
            task = loadTask
        } else {
            task = Task { [settings, session] in
                await settings.load()
                await session.loadHistory()
            }
            loadTask = task
        }
        await task.value
        hasLoaded = true
        loadTask = nil
    }

    public func makeConversationStore() -> ConversationStore {
        ConversationStore(client: client, repository: conversations, settings: settings)
    }

    public func startNewTranslation() {
        session.newConversation()
        sourceDraft = ""
        questionDraft = ""
        section = .translate
        newTranslationID = UUID()
    }

    public static func live() -> CopilotEnvironment {
        let root: URL
        #if os(iOS)
        let group = Bundle.main.object(forInfoDictionaryKey: "CopilotAppGroup") as? String
        guard let group, let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group) else {
            return CopilotEnvironment(
                settings: SettingsStore(repository: MemorySettingsRepository(), credentials: MemoryCredentialStore()),
                client: URLSessionLanguageModelClient(), conversations: MemoryConversationRepository(),
                startupMessage: "共享配置不可用，请重新安装 Apple Copilot。开发构建请检查共享容器与签名配置。")
        }
        root = container.appendingPathComponent("AppleCopilot", isDirectory: true)
        let accessGroup = Bundle.main.object(forInfoDictionaryKey: "CopilotKeychainGroup") as? String
        #else
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleCopilot", isDirectory: true)
        let accessGroup: String? = nil
        #endif
        let settings = SettingsStore(
            repository: FileSettingsRepository(rootURL: root),
            credentials: KeychainCredentialStore(accessGroup: accessGroup))
        return CopilotEnvironment(settings: settings, client: URLSessionLanguageModelClient(),
                                  conversations: FileConversationRepository(rootURL: root))
    }

    public static func preview() -> CopilotEnvironment {
        let environment = CopilotEnvironment(
            settings: SettingsStore(repository: MemorySettingsRepository(), credentials: PreviewCredentials()),
            client: PreviewLanguageModelClient(),
            conversations: MemoryConversationRepository(conversations: [CopilotPreviewFixtures.conversation]))
        environment.session.select(CopilotPreviewFixtures.conversation)
        return environment
    }
}

private actor PreviewCredentials: CredentialStore {
    func load(account: String) -> String? { "preview-only" }
    func save(_ key: String, account: String) {}
    func delete(account: String) {}
}
