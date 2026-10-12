import CopilotCore
import SwiftUI

/// The system sheet and the Mac Services panel already own their title and
/// close controls. The extension supplies only the translation and its actions.
public struct TranslationOverlayView: View {
    @Environment(CopilotEnvironment.self) private var environment
    private let selectedText: String
    private let targetLanguage: String?
    private let allowsReplacement: Bool
    private let finish: (String?) -> Void
    private let expand: () -> Void
    private let settingsPresentationChanged: (Bool) -> Void
    @State private var store: ConversationStore?
    @State private var isEditingSettings = false
    @State private var question = ""

    public init(
        selectedText: String, targetLanguage: String? = nil,
        allowsReplacement: Bool = false,
        finish: @escaping (String?) -> Void,
        expand: @escaping () -> Void,
        settingsPresentationChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.selectedText = selectedText
        self.targetLanguage = targetLanguage
        self.allowsReplacement = allowsReplacement
        self.finish = finish
        self.expand = expand
        self.settingsPresentationChanged = settingsPresentationChanged
    }

    public var body: some View {
        Group {
            if isEditingSettings {
                SettingsEditor(onClose: { isEditingSettings = false })
            } else if let store, store.conversation != nil {
                ConversationDetail(
                    store: store, onFocus: expand,
                    onSettings: {
                        isEditingSettings = true; expand()
                    },
                    replaceTranslation: replacementAction,
                    contentPadding: 16, draft: $question)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        SourceText(text: selectedText)
                        if let message = environment.startupMessage {
                            InlineNotice(title: "需要配置共享权限", message: message)
                        }
                        if let store, let error = store.errorMessage {
                            InlineNotice(title: "未能完成翻译", message: error)
                            Button("重试翻译", systemImage: "arrow.clockwise") {
                                Task { await store.translate(selectedText, targetLanguage: targetLanguage) }
                            }
                            .buttonStyle(.glassProminent)
                        }
                        if store?.isWorking == true { ProgressView("正在翻译…") }
                        if !environment.settings.hasSavedAPIKey {
                            Button("配置模型与密钥", systemImage: "key") {
                                isEditingSettings = true; expand()
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .copilotPageBackground()
        .task(id: selectedText) {
            store?.cancel()
            guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await environment.load()
            // Extension scenes can outlive a sheet. Re-read settings saved by
            // the main app before taking the next conversation's snapshot.
            await environment.settings.refresh()
            guard !Task.isCancelled else { return }
            let session = environment.makeConversationStore()
            store = session
            if environment.startupMessage == nil && environment.settings.hasSavedAPIKey {
                await session.translate(selectedText, targetLanguage: targetLanguage)
            }
        }
        .onChange(of: isEditingSettings) { oldValue, value in
            settingsPresentationChanged(value)
            if oldValue, !value, environment.settings.hasSavedAPIKey,
                store?.conversation == nil, let store
            {
                Task { await store.translate(selectedText, targetLanguage: targetLanguage) }
            }
        }
        .onDisappear { store?.cancel() }
    }

    private func replace(_ translation: String) {
        store?.cancel()
        finish(translation)
    }

    private var replacementAction: ((String) -> Void)? {
        guard allowsReplacement else { return nil }
        return { translation in replace(translation) }
    }
}
