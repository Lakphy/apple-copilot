#if os(macOS)
import AppKit
import WebKit

/// Markdown expands to its full height; the surrounding SwiftUI ScrollView owns
/// vertical scrolling. WebKit still owns horizontal scrolling inside HTML blocks.
@MainActor
final class MacMarkdownWebView: WKWebView {
    private var verticalGesture: Bool?

    override func scrollWheel(with event: NSEvent) {
        guard let scrollView = conversationScrollView else {
            super.scrollWheel(with: event)
            return
        }

        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if !phased || event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            verticalGesture = nil
        }
        // Keep one destination through the gesture and its momentum, including
        // zero-delta end events. Shift-wheel remains WebKit's horizontal gesture.
        if verticalGesture == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            verticalGesture =
                !event.modifierFlags.contains(.shift)
                && abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        }

        if verticalGesture == true {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }

        if !phased || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) {
            verticalGesture = nil
        }
    }

    private var conversationScrollView: NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }
}
#endif
