#if os(macOS)
import AppKit
import CopilotCore
import CopilotUI
import SwiftUI

/// A macOS Services entry point. macOS does not expose the iOS default
/// translation-provider sheet to third-party apps; this uses a native panel.
@MainActor
public final class AppleCopilotApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public var environment = CopilotEnvironment.live()

    private var translationPanel: NSPanel?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Advertised as NSMessage=translateSelection in the macOS app Info.plist.
    /// Read the selected text synchronously, then let the panel own async work.
    @objc(translateSelection:userData:error:)
    public func translateSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "请选择要翻译的文本。"
            return
        }

        showTranslation(for: text)
    }

    public func showTranslation(for selectedText: String) {
        translationPanel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Apple Copilot · 划词翻译"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 360, height: 360)
        panel.delegate = self

        let overlay = TranslationOverlayView(
            selectedText: selectedText,
            allowsReplacement: false,
            finish: { [weak panel] _ in panel?.close() },
            expand: { [weak panel] in
                guard let panel else { return }
                var frame = panel.frame
                let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
                let height = min(max(frame.height, 560), visible.height)
                frame.origin.y = min(max(frame.maxY - height, visible.minY), visible.maxY - height)
                frame.size.height = height
                frame.size.width = min(frame.width, visible.width)
                frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                panel.setFrame(frame, display: true)
            },
            settingsPresentationChanged: { [weak panel] isPresented in
                panel?.title = isPresented ? "设置" : "Apple Copilot · 划词翻译"
                // NavigationStack installs its toolbar while switching screens.
                // Keep the same Services panel in front after that update.
                Task { @MainActor [weak panel] in
                    await Task.yield()
                    panel?.makeKeyAndOrderFront(nil)
                }
            }
        )
        .environment(environment)

        panel.contentView = NSHostingView(rootView: overlay)
        translationPanel = panel
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === translationPanel {
            translationPanel = nil
        }
    }
}
#endif
