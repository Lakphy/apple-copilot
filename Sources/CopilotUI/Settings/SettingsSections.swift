import CopilotCore
import SwiftUI

struct ModelServiceSection: View {
    @Bindable var settings: SettingsStore
    let canRetainAPIKey: Bool
    let validationMessage: String?

    private var endpoint: String? {
        try? settings.configuration.resolvedEndpoint().absoluteString
    }

    var body: some View {
        Section {
            Picker("API 协议", selection: $settings.configuration.apiProtocol) {
                ForEach(APIProtocol.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            TextField(
                "Base URL", text: $settings.configuration.baseURL,
                prompt: Text("https://api.example.com/v1")
            )
            .apiTextInput(isURL: true)
            .settingsFieldLabel("Base URL")
            TextField(
                "模型", text: $settings.configuration.model,
                prompt: Text("服务提供商的模型 ID")
            )
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
                if let endpoint {
                    Text("完整请求地址")
                        .font(.caption)
                    Text(endpoint)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if endpoint != settings.configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Button("补全路径") {
                            settings.configuration.baseURL = endpoint
                        }
                        .disabled(settings.isLoading || settings.isSaving)
                    }
                }
                if settings.hasUnsavedChanges {
                    Text("修改尚未保存。翻译使用已保存的配置，请点右上角“保存”使修改生效。")
                }
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.primary)
                }
                if !canRetainAPIKey && settings.apiKey.isEmpty {
                    Text("输入此服务的 API key 后保存。更换协议或服务器需要重新输入密钥。")
                }
                Text("Base URL 支持根地址、版本路径或完整端点，发送时自动补全路径。远程服务使用 HTTPS；HTTP 仅适用于本机和回环地址。")
            }
        }
    }
}

struct TranslationPreferencesSection: View {
    @Bindable var settings: SettingsStore

    private static let commonLanguages = [
        "简体中文", "繁體中文", "英语", "日语", "韩语", "法语", "德语", "西班牙语",
        "葡萄牙语", "意大利语", "俄语", "阿拉伯语", "印地语", "泰语", "越南语", "印度尼西亚语",
    ]

    var body: some View {
        Section {
            #if os(macOS)
            HStack(alignment: .center, spacing: 12) {
                Text("目标语言")
                Spacer(minLength: 12)
                targetLanguageField
                    .frame(maxWidth: 260)
            }
            #else
            targetLanguageField.settingsFieldLabel("目标语言")
            #endif
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("翻译提示词").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Menu("添加变量", systemImage: "curlybraces") {
                        ForEach(PromptVariable.allCases) { variable in
                            Button("\(variable.placeholder) · \(variable.title)") {
                                settings.configuration.translationPrompt += variable.placeholder
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("将变量追加到提示词末尾")
                }
                TextEditor(text: $settings.configuration.translationPrompt)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .frame(minHeight: 160)
                    .accessibilityLabel("翻译系统提示词")
            }
            DisclosureGroup("变量说明与提示词预览") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(PromptVariable.allCases) { variable in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variable.placeholder).font(.caption.monospaced())
                            Text(variable.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("使用 {{targetLanguage}} 可保留字面量 {targetLanguage}；未知变量保持原样。")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("展开预览").font(.subheadline.weight(.medium))
                    Text(
                        settings.configuration.resolvedPrompt(
                            context: PromptContext(messages: [
                                ChatMessage(role: .user, content: "Good design makes complex things simple.")
                            ]))
                    )
                    .font(.callout)
                    .textSelection(.enabled)
                    Text("预览使用示例原文和当前设备时间；发送时使用实际会话。原文语言自动识别不代表确定结果。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text("翻译偏好")
        } footer: {
            Text("可添加目标语言、模型、日期时间和会话变量。历史会话保留创建时的模型、语言和提示词，动态变量在每次请求时展开。")
        }
    }

    private var targetLanguageField: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("可手动输入语言", text: $settings.configuration.targetLanguage)
                .labelsHidden()
                .accessibilityLabel("目标语言")
                #if os(macOS)
            .multilineTextAlignment(.trailing)
                #endif
            Menu {
                Picker("常用语言", selection: $settings.configuration.targetLanguage) {
                    // A custom value stays a valid selection while being edited.
                    if !Self.commonLanguages.contains(settings.configuration.targetLanguage) {
                        Text("自定义语言").tag(settings.configuration.targetLanguage)
                    }
                    ForEach(Self.commonLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "chevron.up.chevron.down")
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .accessibilityLabel("选择常用目标语言")
            .help("从常用语言列表中选择，也可手动输入")
        }
    }
}

struct SystemTranslationSection: View {
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

struct PrivacySettingsSection: View {
    var body: some View {
        Section {
            Text("翻译时，原文及本次对话会发送给你配置的服务。历史记录仅保存在本地，API key 安全存储在此设备的 Keychain 中，不会进入历史记录。")
                .foregroundStyle(.secondary)
        } header: {
            Text("数据与隐私")
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
