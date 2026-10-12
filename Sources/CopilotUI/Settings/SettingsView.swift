import SwiftUI
import CopilotCore

public struct SettingsView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @ScaledMetric(relativeTo: .body) private var toolbarButtonHeight = 44

    public init() {}

    private var settings: SettingsStore { environment.settings }

    private var canSave: Bool {
        environment.startupMessage == nil && settings.canSave
    }

    public var body: some View {
        Form {
            statusSection
                .listRowBackground(CopilotSurface.secondary)
            ModelServiceSection(
                settings: settings, canRetainAPIKey: settings.canRetainAPIKey,
                validationMessage: settings.validationMessage
            )
            .listRowBackground(CopilotSurface.secondary)
            TranslationPreferencesSection(settings: settings)
                .listRowBackground(CopilotSurface.secondary)
            SystemTranslationSection()
                .listRowBackground(CopilotSurface.secondary)
            PrivacySettingsSection()
                .listRowBackground(CopilotSurface.secondary)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        #if os(macOS)
        // macOS grouped forms need an explicit reading width. On iPadOS the
        // native form owns its margins; constraining the scroll view also
        // constrains its background and separates it from the navigation bar.
        .frame(maxWidth: 720)
        #endif
        .frame(maxWidth: .infinity)
        .copilotPageBackground()
        .navigationTitle("设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: reset) {
                    ToolbarActionIcon(symbol: "arrow.counterclockwise")
                        #if os(iOS)
                    .frame(width: toolbarButtonHeight, height: toolbarButtonHeight)
                    .glassEffect(.regular.interactive(), in: .circle)
                        #endif
                }
                .buttonBorderShape(.circle)
                #if os(iOS)
                .buttonStyle(.plain)
                #endif
                .disabled(settings.isLoading || settings.isSaving || !settings.isLoaded)
                .accessibilityLabel("重置设置")
                .help("恢复默认配置，保存后生效")
            }
            #if os(iOS)
            .sharedBackgroundVisibility(.hidden)
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button(role: .confirm, action: save) {
                    Group {
                        if settings.isSaving {
                            ProgressView().accessibilityLabel("正在保存设置")
                        } else {
                            Text("保存")
                        }
                    }
                    #if os(iOS)
                    .padding(.horizontal, 16)
                    .frame(minHeight: toolbarButtonHeight)
                    .foregroundStyle(.white)
                    .glassEffect(
                        .regular.tint(canSave ? Color.accentColor : Color.gray.opacity(0.35))
                            .interactive(canSave), in: .capsule)
                    #endif
                }
                #if os(macOS)
                .buttonStyle(.glassProminent)
                #endif
                #if os(iOS)
                .buttonStyle(.plain)
                #endif
                .disabled(!canSave)
                .accessibilityLabel(settings.isSaving ? "正在保存设置" : "保存设置")
                .help("保存设置")
                #if os(iOS)
                .keyboardShortcut("s", modifiers: .command)
                #endif
            }
            #if os(iOS)
            .sharedBackgroundVisibility(.hidden)
            #endif
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
        }
    }

    private func draftChanged() {
        settings.clearError()
    }

    private func save() {
        guard canSave else { return }
        Task {
            await settings.save()
            if settings.errorMessage == nil && !settings.hasUnsavedChanges {
                AccessibilityNotification.Announcement("设置已保存").post()
            }
        }
    }

    private func reset() {
        guard settings.isLoaded, !settings.isLoading, !settings.isSaving else { return }
        settings.configuration = .default
        settings.apiKey = ""
        draftChanged()
    }
}
