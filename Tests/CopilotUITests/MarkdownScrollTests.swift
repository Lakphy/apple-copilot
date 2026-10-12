#if os(macOS)
import AppKit
import CoreGraphics
import Testing
import WebKit
@testable import CopilotUI

@Suite @MainActor
struct MarkdownScrollTests {
    @Test func verticalWheelReachesTheEnclosingConversationInBothDirections() throws {
        let fixture = ScrollFixture()
        let down = try wheel(y: -100)
        fixture.webView.scrollWheel(with: down)
        #expect(fixture.scrollView.events.count == 1)
        #expect(fixture.scrollView.events.first === down)
        let up = try wheel(y: 50)
        fixture.webView.scrollWheel(with: up)
        #expect(fixture.scrollView.events.count == 2)
        #expect(fixture.scrollView.events.last === up)
        #expect(fixture.scrollView.events[0].scrollingDeltaY < 0)
        #expect(fixture.scrollView.events[1].scrollingDeltaY > 0)
    }

    @Test func horizontalAndShiftWheelStayInWebKit() throws {
        let fixture = ScrollFixture()
        fixture.webView.scrollWheel(with: try wheel(x: -100, y: -2))
        fixture.webView.scrollWheel(with: try wheel(y: -100, shifted: true))
        #expect(fixture.scrollView.events.isEmpty)
        // The next ordinary wheel must not inherit the previous horizontal route.
        fixture.webView.scrollWheel(with: try wheel(y: -100))
        #expect(fixture.scrollView.events.count == 1)
    }

    @Test func trackpadKeepsItsVerticalDestinationThroughDriftEndAndMomentum() throws {
        let fixture = ScrollFixture()
        let events = try [
            wheel(y: -30, phase: .began),
            wheel(x: -20, y: -2, phase: .changed),
            wheel(phase: .ended),
            wheel(y: -10, momentum: .begin),
            wheel(y: -3, momentum: .continuous),
            wheel(momentum: .end),
        ]
        for event in events { fixture.webView.scrollWheel(with: event) }
        #expect(fixture.scrollView.events.count == events.count)
        #expect(fixture.scrollView.events[2].phase.contains(.ended))
        #expect(fixture.scrollView.events.last?.momentumPhase.contains(.ended) == true)

        fixture.webView.scrollWheel(with: try wheel(x: -30, phase: .began))
        fixture.webView.scrollWheel(with: try wheel(y: -20, phase: .changed))
        fixture.webView.scrollWheel(with: try wheel(phase: .ended))
        #expect(fixture.scrollView.events.count == events.count)
    }

    @Test func cancelledGestureDoesNotCaptureTheNextGesture() throws {
        let fixture = ScrollFixture()
        fixture.webView.scrollWheel(with: try wheel(y: -20, phase: .began))
        fixture.webView.scrollWheel(with: try wheel(phase: .cancelled))
        fixture.webView.scrollWheel(with: try wheel(x: -20, phase: .began))
        #expect(fixture.scrollView.events.count == 2)
    }

    private func wheel(
        x: Int32 = 0, y: Int32 = 0, phase: CGScrollPhase? = nil,
        momentum: CGMomentumScrollPhase = .none, shifted: Bool = false
    ) throws -> NSEvent {
        let cgEvent = try #require(
            CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
        cgEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
        cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        if shifted { cgEvent.flags.insert(.maskShift) }
        return try #require(NSEvent(cgEvent: cgEvent))
    }
}

@MainActor
private final class ScrollFixture {
    let scrollView = RecordingScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    let webView = MacMarkdownWebView(
        frame: NSRect(x: 0, y: 0, width: 320, height: 1600),
        configuration: WKWebViewConfiguration())
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.borderless], backing: .buffered, defer: false)

    init() {
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 320, height: 2400))
        document.addSubview(webView)
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        window.contentView = scrollView
    }
}

private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class RecordingScrollView: NSScrollView {
    var events: [NSEvent] = []
    override func scrollWheel(with event: NSEvent) {
        events.append(event)
        super.scrollWheel(with: event)
    }
}
#endif
