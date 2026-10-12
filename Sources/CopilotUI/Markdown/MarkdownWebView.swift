import CopilotCore
import SwiftUI
import WebKit

@MainActor
struct MarkdownWebView {
    let markdown: String
    let isStreaming: Bool
    let dark: Bool
    let fontSize: CGFloat
    @Binding var height: CGFloat
    var onLink: (URL) -> Void
    var onAnchor: (CGFloat) -> Void
    var onFailure: () -> Void
    var increasedContrast = false
    var boldText = false
    var reduceMotion = false
    var headingSizes: [CGFloat] = []

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "markdown")
        #if os(macOS)
        let webView = MacMarkdownWebView(frame: .zero, configuration: configuration)
        #else
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #endif
        webView.navigationDelegate = coordinator
        #if os(macOS)
        webView.underPageBackgroundColor = .windowBackgroundColor
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        #endif
        coordinator.webView = webView
        if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Markdown") {
            coordinator.documentURL = url
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            Task { @MainActor in coordinator.parent.onFailure() }
        }
        return webView
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownWebView
        weak var webView: WKWebView?
        var documentURL: URL?
        private(set) var ready = false
        private var lastUpdate: Payload?
        private var palette: [String: String]?
        #if os(macOS)
        private var colorObserver: NSObjectProtocol?
        #endif
        private var imageTasks: [Int: Task<Void, Never>] = [:]

        struct Payload: Equatable {
            let markdown: String
            let streaming: Bool
            let dark: Bool
            let fontSize: CGFloat
            let increasedContrast: Bool
            let boldText: Bool
            let reduceMotion: Bool
            let headingSizes: [CGFloat]
        }

        init(parent: MarkdownWebView) {
            self.parent = parent
            super.init()
            #if os(macOS)
            colorObserver = NotificationCenter.default.addObserver(
                forName: NSColor.systemColorsDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.palette = nil
                    self.update(self.parent)
                }
            }
            #endif
        }

        func update(_ parent: MarkdownWebView) {
            self.parent = parent
            guard ready, let webView else { return }
            let payload = Payload(
                markdown: parent.markdown, streaming: parent.isStreaming,
                dark: parent.dark, fontSize: parent.fontSize,
                increasedContrast: parent.increasedContrast, boldText: parent.boldText,
                reduceMotion: parent.reduceMotion, headingSizes: parent.headingSizes)
            guard payload != lastUpdate || palette == nil else { return }
            if palette == nil || payload.dark != lastUpdate?.dark
                || payload.increasedContrast != lastUpdate?.increasedContrast
            {
                #if os(macOS)
                if payload.dark != lastUpdate?.dark || payload.increasedContrast != lastUpdate?.increasedContrast {
                    webView.appearance = MarkdownAppearance.appearance(
                        dark: parent.dark, increasedContrast: parent.increasedContrast)
                }
                #endif
                palette = MarkdownAppearance.palette(dark: parent.dark, increasedContrast: parent.increasedContrast)
                #if os(macOS)
                // This view is an opaque document (WKWebView.isOpaque is true).
                // Match that contract in Core Animation so parent scrolling
                // doesn't blend a tall, transparent backing layer each frame.
                webView.appearance?.performAsCurrentDrawingAppearance {
                    webView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                    webView.layer?.isOpaque = true
                }
                #endif
            }
            lastUpdate = payload
            var arguments: [String: Any] = [
                "markdown": payload.markdown, "streaming": payload.streaming,
                "dark": payload.dark, "fontSize": Double(payload.fontSize),
                "increasedContrast": payload.increasedContrast, "boldText": payload.boldText,
                "reduceMotion": payload.reduceMotion, "headingSizes": payload.headingSizes.map(Double.init),
                "palette": palette ?? [:],
            ]
            #if os(macOS)
            arguments["platform"] = "macOS"
            #else
            arguments["platform"] = "iOS"
            #endif
            webView.callAsyncJavaScript(
                "window.copilotUpdate(payload)", arguments: ["payload": arguments], in: nil, in: .page,
                completionHandler: { [weak self] result in
                    if case .failure = result { self?.parent.onFailure() }
                })
        }

        func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            guard message.frameInfo.isMainFrame,
                let payload = message.body as? [String: Any], let type = payload["type"] as? String
            else { return }
            switch type {
            case "ready":
                ready = true
                update(parent)
            case "height":
                guard let value = payload["height"] as? Double, value.isFinite, value > 0 else { return }
                let height = CGFloat(value)
                if abs(parent.height - height) >= 0.5 { parent.height = height }
            case "copy":
                guard let text = payload["text"] as? String, let id = payload["id"] as? Int else { return }
                let succeeded = Clipboard.copy(text)
                webView?.callAsyncJavaScript(
                    "window.copilotCopyResult(id, succeeded)",
                    arguments: [
                        "id": id, "succeeded": succeeded,
                    ], in: nil, in: .page, completionHandler: nil)
            case "link":
                guard let text = payload["url"] as? String, let url = URL(string: text),
                    ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
                else { return }
                parent.onLink(url)
            case "image":
                guard let text = payload["url"] as? String, let url = URL(string: text),
                    let id = payload["id"] as? Int,
                    ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                    url.user == nil, url.password == nil
                else { return }
                imageTasks[id] = Task { [weak self] in
                    let dataURL = try? await MarkdownImageLoader.load(url)
                    guard !Task.isCancelled, let self else { return }
                    self.webView?.callAsyncJavaScript(
                        "window.copilotImageResult(id, dataURL)",
                        arguments: [
                            "id": id, "dataURL": dataURL.map { $0 as Any } ?? NSNull(),
                        ], in: nil, in: .page, completionHandler: nil)
                    self.imageTasks[id] = nil
                }
            case "anchor":
                guard let offset = payload["offset"] as? Double, offset.isFinite else { return }
                parent.onAnchor(CGFloat(offset))
            default: break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
            -> WKNavigationActionPolicy
        {
            // Only the bundled document can navigate inside this view. Links use SwiftUI openURL.
            if navigationAction.navigationType == .other, navigationAction.request.url == documentURL {
                return .allow
            } else {
                return .cancel
            }
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
        ) {
            parent.onFailure()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            parent.onFailure()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("typeof window.copilotUpdate === 'function'") { [weak self] result, _ in
                guard let self else { return }
                guard result as? Bool == true else { self.parent.onFailure(); return }
                if !self.ready { self.ready = true; self.update(self.parent) }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            lastUpdate = nil
            // A terminated process has no DOM state to preserve; recover the current message.
            if let documentURL {
                webView.loadFileURL(documentURL, allowingReadAccessTo: documentURL.deletingLastPathComponent())
            }
        }

        func dismantle(_ webView: WKWebView) {
            ready = false
            #if os(macOS)
            if let colorObserver { NotificationCenter.default.removeObserver(colorObserver) }
            colorObserver = nil
            #endif
            imageTasks.values.forEach { $0.cancel() }
            imageTasks.removeAll()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "markdown")
        }
    }
}

#if os(macOS)
extension MarkdownWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) { coordinator.dismantle(nsView) }
}
#else
extension MarkdownWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { coordinator.dismantle(uiView) }
}
#endif
