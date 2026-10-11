import SwiftUI
import CopilotCore

public struct SettingsView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @State private var saved = false

    public init() {}

    private var settings: SettingsStore { environment.settings }

    private var validationMessage: String? {
        do {
            try settings.configuration.validate()
            if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: { $0.isNewline }) {
                return "API key 不能包含换行。"
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canRetainAPIKey: Bool {
        guard settings.hasSavedAPIKey,
              let account = try? settings.configuration.credentialAccount,
              let savedAccount = try? settings.savedConfiguration.credentialAccount else { return false }
        return account == savedAccount
    }

    private var canSave: Bool {
        validationMessage == nil
            && environment.startupMessage == nil
            && !settings.isLoading
            && !settings.isSaving
            && settings.hasUnsavedChanges
            && (canRetainAPIKey || !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public var body: some View {
        Form {
            statusSection
            ModelServiceSection(settings: settings, canRetainAPIKey: canRetainAPIKey,
                                validationMessage: validationMessage)
            TranslationPreferencesSection(settings: settings)
            SystemTranslationSection()
            PrivacySettingsSection()
        }
        .formStyle(.grouped)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .navigationTitle("设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: save) {
                    if settings.isSaving {
                        ProgressView().accessibilityLabel("正在保存设置")
                    } else {
                        Text("保存")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSave)
                .accessibilityLabel(settings.isSaving ? "正在保存设置" : "保存设置")
                .help("保存设置")
                #if os(iOS)
                .keyboardShortcut("s", modifiers: .command)
                #endif
            }
        }
        .focusedSceneValue(\.copilotSettingsActions, CopilotSettingsActions(save: save, canSave: canSave))
        .task { await environment.load() }
        .onChange(of: settings.configuration) { _, _ in draftChanged() }
        .onChange(of: settings.apiKey) { _, _ in draftChanged() }
    }

    @ViewBuilder private var statusSection: some View {
        if let message = environment.startupMessage {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
            }
        } else if let error = settings.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                if !settings.isLoaded {
                    Button("重新载入设置") { Task { await settings.load() } }
                        .disabled(settings.isLoading || settings.isSaving)
                }
            }
        } else if saved {
            Section {
                Label("设置已保存", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func draftChanged() {
        saved = false
        settings.clearError()
    }

    private func save() {
        guard canSave else { return }
        saved = false
        Task {
            await settings.save()
            saved = settings.errorMessage == nil && !settings.hasUnsavedChanges
        }
    }
}

private struct ModelServiceSection: View {
    @Bindable var settings: SettingsStore
    let canRetainAPIKey: Bool
    let validationMessage: String?

    var body: some View {
        Section {
            Picker("API 协议", selection: $settings.configuration.apiProtocol) {
                ForEach(APIProtocol.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            TextField("Base URL", text: $settings.configuration.baseURL,
                      prompt: Text("https://api.example.com/v1"))
                .apiTextInput(isURL: true)
                .settingsFieldLabel("Base URL")
            TextField("模型", text: $settings.configuration.model,
                      prompt: Text("服务提供商的模型 ID"))
                .apiTextInput()
                .settingsFieldLabel("模型")
            SecureField(canRetainAPIKey ? "API key（留空保留）" : "API key", text: $settings.apiKey)
                .apiTextInput()
                .privacySensitive()
                .writingToolsBehavior(.disabled)
                .settingsFieldLabel("API key")
            if canRetainAPIKey {
                Label("已保存密钥", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("允许本机 HTTP 服务", isOn: $settings.configuration.allowLocalHTTP)
        } header: {
            Text("模型服务")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.primary)
                }
                if !canRetainAPIKey && settings.apiKey.isEmpty {
                    Text("输入此服务的 API key 后保存。更换协议或服务器需要重新输入密钥。")
                }
                Text("Base URL 支持根地址、版本路径或完整端点。远程服务使用 HTTPS；HTTP 仅适用于本机和回环地址。")
            }
        }
    }
}

private struct TranslationPreferencesSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Section {
            TextField("目标语言", text: $settings.configuration.targetLanguage)
                .settingsFieldLabel("目标语言")
            VStack(alignment: .leading, spacing: 8) {
                Text("翻译提示词").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $settings.configuration.translationPrompt)
                    .font(.body)
                    .frame(minHeight: 160)
                    .accessibilityLabel("翻译系统提示词")
            }
        } header: {
            Text("翻译偏好")
        } footer: {
            Text("提示词可使用 {targetLanguage}。历史会话保留创建时的模型、语言和提示词，追问使用该会话的上下文。")
        }
    }
}

private struct SystemTranslationSection: View {
    var body: some View {
        Section {
            #if os(iOS)
            Text("在系统“设置 → App → 默认 App → 翻译”中选择 Apple Copilot。随后在支持的 App 中选中文字并点“翻译”。")
            #else
            Text("在其他 App 中选中文字，打开“服务 → 使用 Apple Copilot 翻译”。如果服务未出现，在系统设置“键盘 → 键盘快捷键 → 服务”启用它。")
            #endif
        } header: {
            Text("系统划词")
        }
    }
}

private struct PrivacySettingsSection: View {
    var body: some View {
        Section {
            Text("翻译时，原文及本次对话会发送给你配置的服务。历史记录仅保存在本地，API key 安全存储在此设备的 Keychain 中，不会进入历史记录。")
                .foregroundStyle(.secondary)
        } header: {
            Text("数据与隐私")
        }
    }
}

struct SettingsEditor: View {
    @Environment(CopilotEnvironment.self) private var environment
    @State private var confirmDiscard = false
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) { self.onClose = onClose }

    private var canClose: Bool {
        !environment.settings.isSaving && !environment.settings.isLoading
    }

    var body: some View {
        NavigationStack {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("返回翻译", systemImage: "chevron.backward", action: requestClose)
                            .disabled(!canClose)
                            .keyboardShortcut(.cancelAction)
                    }
                }
        }
        .confirmationDialog("保存修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("保存并返回") {
                Task {
                    await environment.settings.save()
                    if environment.settings.errorMessage == nil && !environment.settings.hasUnsavedChanges {
                        onClose()
                    }
                }
            }
            Button("放弃修改", role: .destructive) {
                environment.settings.discardDraft()
                onClose()
            }
            Button("继续编辑", role: .cancel) {}
        }
    }

    private func requestClose() {
        if environment.settings.hasUnsavedChanges {
            confirmDiscard = true
        } else {
            onClose()
        }
    }
}

private extension View {
    @ViewBuilder func settingsFieldLabel(_ title: String) -> some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder func apiTextInput(isURL: Bool = false) -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(isURL ? .URL : .asciiCapable)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
