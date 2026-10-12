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

    public init(
        settings: SettingsStore, client: any LanguageModelClient,
        conversations: any ConversationRepository, startupMessage: String? = nil
    ) {
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
        guard let group,
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group)
        else {
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
        return CopilotEnvironment(
            settings: settings, client: URLSessionLanguageModelClient(),
            conversations: FileConversationRepository(rootURL: root))
    }

    public static func preview(markdown: Bool = false) -> CopilotEnvironment {
        let text =
            (try? Bundle.module.url(forResource: "fixture", withExtension: "md", subdirectory: "Markdown")
                .map { try String(contentsOf: $0, encoding: .utf8) }) ?? "# Markdown\n\n**示例回复**"
        let conversation =
            markdown
            ? Conversation(
                sourceText: "请展示 Markdown、代码和流程图。", configuration: .default,
                messages: [
                    ChatMessage(role: .user, content: "请展示 Markdown、代码和流程图。"),
                    ChatMessage(role: .assistant, content: text),
                ]) : CopilotPreviewFixtures.conversation
        let client: any LanguageModelClient =
            markdown ? MarkdownPreviewClient(text: text) : PreviewLanguageModelClient()
        let environment = CopilotEnvironment(
            settings: SettingsStore(repository: MemorySettingsRepository(), credentials: PreviewCredentials()),
            client: client,
            conversations: MemoryConversationRepository(conversations: [conversation]))
        environment.session.select(conversation)
        return environment
    }
}

private struct MarkdownPreviewClient: LanguageModelClient {
    let text: String
    func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String
    { text }
    func stream(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage],
        onDelta: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        var cursor = text.startIndex
        while cursor < text.endIndex {
            try Task.checkCancellation()
            let end = text.index(cursor, offsetBy: 16, limitedBy: text.endIndex) ?? text.endIndex
            try await onDelta(String(text[cursor..<end]))
            cursor = end
            try await Task.sleep(for: .milliseconds(150))
        }
    }
}

private actor PreviewCredentials: CredentialStore {
    func load(account: String) -> String? { "preview-only" }
    func save(_ key: String, account: String) {}
    func delete(account: String) {}
}
