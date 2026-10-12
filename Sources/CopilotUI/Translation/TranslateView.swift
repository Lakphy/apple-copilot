import SwiftUI
import CopilotCore

public struct TranslateView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var source: String { environment.sourceDraft }

    private var translationActionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    public init() {}

    public var body: some View {
        @Bindable var state = environment
        Group {
            if environment.session.conversation != nil {
                ConversationDetail(store: environment.session, draft: $state.questionDraft)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let message = environment.startupMessage {
                            InlineNotice(title: "需要配置共享权限", message: message)
                        }
                        SourceEditor(text: $state.sourceDraft)
                        translationActionsLayout {
                            Text("译为 \(environment.settings.savedConfiguration.targetLanguage)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
                            Button("翻译", systemImage: "character.bubble") {
                                Task { await environment.session.translate(source) }
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.regular)
                            .fixedSize(horizontal: true, vertical: false)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(
                                source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || environment.session.isWorking || environment.startupMessage != nil)
                        }
                        if environment.session.isWorking {
                            ProgressView("正在翻译…")
                            Button("停止生成") { environment.session.cancel() }.buttonStyle(.glass)
                        }
                        if let error = environment.session.errorMessage {
                            InlineNotice(title: "未能完成翻译", message: error)
                        }
                        if !environment.settings.hasSavedAPIKey {
                            Button("配置模型与密钥", systemImage: "key") {
                                environment.section = .settings
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .focusedSceneValue(
                    \.copilotActions,
                    CopilotActions(
                        send: { Task { await environment.session.translate(source) } },
                        cancel: environment.session.cancel,
                        canSend: !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        isWorking: environment.session.isWorking))
                #endif
            }
        }
        .copilotPageBackground()
        .navigationTitle("翻译")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    environment.startNewTranslation()
                } label: {
                    ToolbarActionIcon(symbol: "square.and.pencil")
                }
                .buttonBorderShape(.circle)
                .help("开始新的翻译（⌘N）")
                .accessibilityLabel("新翻译")
            }
        }
    }
}

private struct SourceEditor: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("原文").font(.headline)
            NativeSourceTextEditor(text: $text)
                .id(environment.newTranslationID)
                .frame(height: 160)
                .padding(12)
                .background(CopilotSurface.secondary, in: .rect(cornerRadius: 12))
                .accessibilityLabel("要翻译的原文")
        }
    }
}
