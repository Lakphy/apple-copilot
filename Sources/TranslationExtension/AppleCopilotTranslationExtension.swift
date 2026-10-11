import CopilotCore
import CopilotUI
import ExtensionKit
import SwiftUI
import TranslationUIProvider

/// The system presents this extension after the person chooses Apple Copilot
/// as their default translation app in Settings.
@main
@MainActor
final class AppleCopilotTranslationExtension: @MainActor TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            SelectedTextTranslationView(context: context)
        }
    }
}

@MainActor
private struct SelectedTextTranslationView: View {
    let context: any TranslationUIProviderContext

    @State private var environment = CopilotEnvironment.live()

    var body: some View {
        TranslationOverlayView(
            selectedText: context.inputText.map { String($0.characters) } ?? "",
            allowsReplacement: context.allowsReplacement,
            // The system host owns the title bar and close control.
            finish: finish,
            expand: context.expandSheet
        )
        .environment(environment)
    }

    private func finish(_ translation: String?) {
        context.finish(translation: translation.map { AttributedString($0) })
    }
}
