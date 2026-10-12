import CopilotCore
import SwiftUI

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
