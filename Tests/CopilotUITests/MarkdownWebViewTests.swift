#if os(macOS)
import AppKit
import SwiftUI
import Testing
import WebKit
@testable import CopilotUI

@Suite @MainActor
struct MarkdownWebViewTests {
    @Test func bundledFileRendersAndReportsHeightThroughNativeBridge() async throws {
        var height: CGFloat = 1
        var failed = false
        let markdown =
            "# Native WebKit\n\n| A | B |\n| - | - |\n| 1 | 2 |\n\n```swift\nlet x = 1\n```\n\n```mermaid\nflowchart LR\nA --> B\n```"
        let parent = MarkdownWebView(
            markdown: markdown, isStreaming: false, dark: false, fontSize: 17,
            height: Binding(get: { height }, set: { height = $0 }),
            onLink: { _ in }, onAnchor: { _ in }, onFailure: { failed = true })
        let coordinator = parent.makeCoordinator()
        let webView = parent.makeWebView(coordinator: coordinator)
        webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source:
                    "window.copilotErrors=[]; window.addEventListener('error', e=>window.copilotErrors.push(e.message)); window.addEventListener('securitypolicyviolation',e=>window.copilotErrors.push(e.violatedDirective+':'+e.blockedURI));",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let url = coordinator.documentURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 900),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        defer { coordinator.dismantle(webView); window.contentView = nil }
        coordinator.update(parent)
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        var result = ""
        while ContinuousClock.now < deadline && !failed {
            result =
                (try? await script(
                    "JSON.stringify({engine:typeof window.copilotUpdate, errors:window.copilotErrors, body:document.body?.innerHTML.slice(0,300), heading:document.querySelector('h1')?.textContent, table:!!document.querySelector('table'), highlight:!!document.querySelector('.hljs-keyword'), diagram:!!document.querySelector('.mermaid-diagram svg')})",
                    webView: webView)) ?? ""
            if result.contains("\"diagram\":true") { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!failed)
        #expect(coordinator.ready)
        #expect(result.contains("\"heading\":\"Native WebKit\""))
        #expect(result.contains("\"table\":true"))
        #expect(result.contains("\"highlight\":true"))
        #expect(result.contains("\"diagram\":true"))
        #expect(height > 200)
        print("MARKDOWN_NATIVE_OPACITY view=\(webView.isOpaque) layer=\(String(describing: webView.layer?.isOpaque))")
        #expect(webView.layer?.isOpaque == true)

        // Repeated representable updates must leave a finished document alone.
        // Record work as well as elapsed time; timing is diagnostic, not a CI gate.
        let start = ContinuousClock.now
        for _ in 0..<2_000 { coordinator.update(parent) }
        let elapsed = start.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        print("MARKDOWN_NO_CHANGE_UPDATES 2000 \(milliseconds) ms")
        let appearanceWrites = AppearanceWriteCounter()
        let observation = webView.observe(\.appearance, options: [.new]) { _, _ in
            MainActor.assumeIsolated { appearanceWrites.value += 1 }
        }
        for _ in 0..<100 { coordinator.update(parent) }
        observation.invalidate()
        print("MARKDOWN_NO_CHANGE_APPEARANCE_WRITES 100 \(appearanceWrites.value)")
        #expect(appearanceWrites.value == 0)

        // Caching must still respond to the system's accent/semantic-color
        // notification without forcing an unchanged NSAppearance assignment.
        let previousRevision = try await script(
            "String(document.getElementById('content').dataset.renderRevision)", webView: webView)
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        var refreshedRevision = previousRevision
        let refreshDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while refreshedRevision == previousRevision && ContinuousClock.now < refreshDeadline {
            try await Task.sleep(for: .milliseconds(20))
            refreshedRevision = try await script(
                "String(document.getElementById('content').dataset.renderRevision)", webView: webView)
        }
        #expect(refreshedRevision != previousRevision)

        let dark = MarkdownWebView(
            markdown: markdown, isStreaming: false, dark: true, fontSize: 17,
            height: Binding(get: { height }, set: { height = $0 }),
            onLink: { _ in }, onAnchor: { _ in }, onFailure: { failed = true })
        coordinator.update(dark)
        let darkDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        var darkReady = false
        while ContinuousClock.now < darkDeadline {
            darkReady =
                (try? await script(
                    "String(document.documentElement.dataset.theme === 'dark' && !!document.querySelector('.mermaid-diagram svg'))",
                    webView: webView)) == "true"
            if darkReady { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(darkReady)
        #expect(webView.appearance?.name == .darkAqua)
        let png: Data = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let tiff = image?.tiffRepresentation,
                    let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                {
                    continuation.resume(returning: png)
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("build/MarkdownValidation")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("mac-native-dark.png"))

        let accessible = MarkdownWebView(
            markdown: markdown, isStreaming: false, dark: true, fontSize: 53,
            height: Binding(get: { height }, set: { height = $0 }),
            onLink: { _ in }, onAnchor: { _ in }, onFailure: { failed = true },
            increasedContrast: true, boldText: true, reduceMotion: true,
            headingSizes: [58, 56, 55])
        coordinator.update(accessible)
        let accessibleDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        var appearance = ""
        while ContinuousClock.now < accessibleDeadline {
            appearance =
                (try? await script(
                    "JSON.stringify({contrast:document.documentElement.dataset.contrast, bold:getComputedStyle(document.body).fontWeight, font:getComputedStyle(document.body).fontSize, heading:getComputedStyle(document.querySelector('h1')).fontSize, motion:document.documentElement.dataset.reduceMotion})",
                    webView: webView)) ?? ""
            if appearance.contains("\"font\":\"53px\"") { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!failed)
        #expect(appearance.contains("\"contrast\":\"more\""))
        #expect(appearance.contains("\"bold\":\"600\""))
        #expect(appearance.contains("\"heading\":\"58px\""))
        #expect(appearance.contains("\"motion\":\"true\""))
        #expect(webView.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        let palettes = [false, true].flatMap { dark in
            [false, true].map { contrast in
                [
                    "dark": dark, "increasedContrast": contrast,
                    "palette": MarkdownAppearance.palette(dark: dark, increasedContrast: contrast),
                ] as [String: Any]
            }
        }
        try JSONSerialization.data(withJSONObject: palettes, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("mac-native-palettes.json"))
    }

    private func script(_ source: String, webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(source) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as? String ?? "")
                }
            }
        }
    }
}

@MainActor private final class AppearanceWriteCounter { var value = 0 }
#endif
