#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import CopilotUI

@Suite @MainActor
struct SourceTextEditorTests {
    @Test func composingTextHidesPlaceholderWithoutPublishingUncommittedInput() {
        var draft = ""
        let parent = NativeSourceTextEditor(text: Binding(get: { draft }, set: { draft = $0 }))
        let coordinator = parent.makeCoordinator()
        let editor = SourceTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        editor.delegate = coordinator
        editor.onCompositionCommitted = { [weak editor] in
            if let editor { coordinator.publish(editor) }
        }
        #expect(editor.showsPlaceholder)

        editor.setMarkedText(
            "ni", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        #expect(editor.string == "ni")
        #expect(!editor.showsPlaceholder)
        #expect(draft.isEmpty)

        editor.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!editor.hasMarkedText())
        #expect(editor.string == "你")
        #expect(draft == "你")

        editor.setSelectedRange(NSRange(location: 1, length: 0))
        editor.insertNewline(nil)
        editor.insertText("好", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "你\n好")
        #expect(draft == "你\n好")

        editor.setSelectedRange(NSRange(location: 0, length: (editor.string as NSString).length))
        editor.deleteBackward(nil)
        #expect(editor.showsPlaceholder)
        #expect(draft.isEmpty)
    }

    @Test func cancelledCompositionRestoresPlaceholder() {
        let editor = SourceTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        editor.setMarkedText(
            "ni", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.setMarkedText(
            "", selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.unmarkText()
        #expect(editor.string.isEmpty)
        #expect(editor.showsPlaceholder)
    }
}
#endif
