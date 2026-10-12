import SwiftUI

private let sourcePlaceholder = "输入或粘贴要翻译的文本"

#if os(macOS)
import AppKit

/// Keep composition and placeholder rendering in the native text system.
struct NativeSourceTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let editor = SourceTextView(frame: NSRect(x: 0, y: 0, width: 0, height: 160))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .preferredFont(forTextStyle: .body)
        editor.textColor = .textColor
        editor.textContainerInset = .zero
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 160)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.writingToolsBehavior = .complete
        editor.setAccessibilityLabel("要翻译的原文")
        editor.string = text
        editor.delegate = context.coordinator
        editor.onCompositionCommitted = { [weak coordinator = context.coordinator, weak editor] in
            if let editor { coordinator?.publish(editor) }
        }
        scrollView.documentView = editor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scrollView.documentView as? SourceTextView else { return }
        // Never overwrite the input method's in-progress marked text.
        if !editor.hasMarkedText(), editor.string != text {
            editor.string = text
            editor.needsDisplay = true
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        let editor = scrollView.documentView as? SourceTextView
        editor?.delegate = nil
        editor?.onCompositionCommitted = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeSourceTextEditor
        init(_ parent: NativeSourceTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? SourceTextView else { return }
            publish(editor)
        }

        func publish(_ editor: SourceTextView) {
            guard !editor.hasMarkedText(), parent.text != editor.string else { return }
            parent.text = editor.string
        }
    }
}

final class SourceTextView: NSTextView {
    var onCompositionCommitted: (() -> Void)?
    var showsPlaceholder: Bool { string.isEmpty && !hasMarkedText() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder else { return }
        let origin = NSPoint(
            x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerOrigin.y)
        (sourcePlaceholder as NSString).draw(
            at: origin,
            withAttributes: [
                .font: font ?? NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.placeholderTextColor,
            ])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
        onCompositionCommitted?()
    }
}

#else
import UIKit

struct NativeSourceTextEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SourceTextView {
        let editor = SourceTextView()
        editor.backgroundColor = .clear
        editor.font = .preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.textColor = .label
        editor.writingToolsBehavior = .complete
        editor.accessibilityLabel = "要翻译的原文"
        editor.text = text
        editor.delegate = context.coordinator
        editor.onCompositionCommitted = { [weak coordinator = context.coordinator, weak editor] in
            if let editor { coordinator?.publish(editor) }
        }
        return editor
    }

    func updateUIView(_ editor: SourceTextView, context: Context) {
        context.coordinator.parent = self
        if editor.markedTextRange == nil, editor.text != text { editor.text = text }
        editor.refreshPlaceholder()
    }

    static func dismantleUIView(_ editor: SourceTextView, coordinator: Coordinator) {
        editor.delegate = nil
        editor.onCompositionCommitted = nil
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeSourceTextEditor
        init(_ parent: NativeSourceTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard let editor = textView as? SourceTextView else { return }
            editor.refreshPlaceholder()
            publish(editor)
        }

        func publish(_ editor: SourceTextView) {
            guard editor.markedTextRange == nil, parent.text != editor.text else { return }
            parent.text = editor.text
        }
    }
}

final class SourceTextView: UITextView {
    var onCompositionCommitted: (() -> Void)?
    private let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.text = sourcePlaceholder
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.font = font
        let x = textContainerInset.left + textContainer.lineFragmentPadding
        let width = max(0, bounds.width - x - textContainerInset.right - textContainer.lineFragmentPadding)
        let size = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = CGRect(x: x, y: textContainerInset.top, width: width, height: size.height)
        refreshPlaceholder()
    }

    func refreshPlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty || markedTextRange != nil
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        super.setMarkedText(markedText, selectedRange: selectedRange)
        refreshPlaceholder()
    }

    override func unmarkText() {
        super.unmarkText()
        refreshPlaceholder()
        onCompositionCommitted?()
    }
}
#endif
