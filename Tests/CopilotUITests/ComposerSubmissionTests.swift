#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import CopilotUI

@Suite(.serialized) @MainActor
struct ComposerSubmissionTests {
    @Test func returnSubmitsTheQuestion() throws {
        let fixture = ComposerFixture(text: "解释一下这句话")
        try fixture.pressReturn()
        #expect(fixture.sent == ["解释一下这句话"])
        #expect(fixture.text == "解释一下这句话")
        #expect(fixture.cancelCount == 0)
    }

    @Test func optionReturnInsertsANewline() throws {
        let fixture = ComposerFixture(text: "第一行")
        try fixture.pressReturn(modifiers: .option)
        #expect(fixture.sent.isEmpty)
        #expect(fixture.text == "第一行\n")
    }

    @Test func blankQuestionDoesNotSubmit() throws {
        let fixture = ComposerFixture(text: " \n ")
        try fixture.pressReturn()
        #expect(fixture.sent.isEmpty)
        #expect(fixture.cancelCount == 0)
    }

    @Test func returnWhileGeneratingPreservesTheNextDraft() throws {
        let fixture = ComposerFixture(text: "下一条追问", isWorking: true)
        try fixture.pressReturn()
        #expect(fixture.sent.isEmpty)
        #expect(fixture.text == "下一条追问")
        #expect(fixture.cancelCount == 0)
    }

    @Test func commandReturnSubmitsOnce() throws {
        let fixture = ComposerFixture(text: "第一行\n第二行")
        try fixture.pressReturn(modifiers: .command)
        #expect(fixture.sent == ["第一行\n第二行"])
        #expect(fixture.cancelCount == 0)
    }

    @Test func commandReturnWhileGeneratingDoesNotStopTheReply() throws {
        let fixture = ComposerFixture(text: "下一条追问", isWorking: true)
        try fixture.pressReturn(modifiers: .command)
        #expect(fixture.sent.isEmpty)
        #expect(fixture.cancelCount == 0)
        #expect(fixture.text == "下一条追问")
    }

    @Test func committedCompositionIsSentAsText() throws {
        let fixture = ComposerFixture(text: "")
        let editor = try fixture.focusEditor()
        editor.setMarkedText(
            "ni", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        editor.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.sent.isEmpty)
        #expect(fixture.text == "你")
        #expect(fixture.cancelCount == 0)
        try fixture.pressReturn()
        #expect(fixture.sent == ["你"])
    }
}

@MainActor
private final class ComposerFixture {
    var text: String
    var sent: [String] = []
    var cancelCount = 0
    private let window: NSWindow
    private let host: NSHostingView<GlassComposer>

    init(text: String, isWorking: Bool = false) {
        _ = NSApplication.shared
        self.text = text
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host = NSHostingView(
            rootView: GlassComposer(
                text: .constant(""), isWorking: false,
                send: {}, cancel: {}))
        host.rootView = GlassComposer(
            text: Binding(get: { [unowned self] in self.text }, set: { [unowned self] in self.text = $0 }),
            isWorking: isWorking,
            send: { [unowned self] in self.sent.append(self.text) },
            cancel: { [unowned self] in self.cancelCount += 1 })
        window.contentView = host
        host.layoutSubtreeIfNeeded()
    }

    func pressReturn(modifiers: NSEvent.ModifierFlags = []) throws {
        let editor = try focusEditor()
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36))
        if !modifiers.contains(.command) || !window.performKeyEquivalent(with: event) {
            editor.keyDown(with: event)
        }
    }

    func focusEditor() throws -> NSTextView {
        let field = try #require(findTextField(in: host))
        if let editor = field.currentEditor() as? NSTextView, window.firstResponder === editor { return editor }
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        return editor
    }

    private func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { self.findTextField(in: $0) }.first
    }
}
#endif
