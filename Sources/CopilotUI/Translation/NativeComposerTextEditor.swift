#if os(iOS)
import SwiftUI
import UIKit

/// A vertical SwiftUI TextField inserts a newline from the software Send key.
/// Handle that edit before it changes the draft, without inspecting pasted text.
struct NativeComposerTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ComposerTextView {
        let editor = ComposerTextView()
        editor.backgroundColor = .clear
        editor.font = .preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.textColor = .label
        editor.textContainerInset = .zero
        editor.textContainer.lineFragmentPadding = 0
        editor.returnKeyType = .send
        editor.writingToolsBehavior = .complete
        editor.accessibilityLabel = "追问内容"
        editor.text = text
        editor.delegate = context.coordinator
        return editor
    }

    func updateUIView(_ editor: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        if editor.markedTextRange == nil, editor.text != text {
            editor.text = text
            editor.invalidateIntrinsicContentSize()
        }
        editor.refreshPlaceholder()
        if isFocused, !editor.isFirstResponder {
            editor.becomeFirstResponder()
        } else if !isFocused, editor.isFirstResponder {
            editor.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let lineHeight = uiView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(max(lineHeight, measured.height), lineHeight * 4))
    }

    static func dismantleUIView(_ editor: ComposerTextView, coordinator: Coordinator) {
        editor.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeComposerTextEditor
        init(_ parent: NativeComposerTextEditor) { self.parent = parent }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard let editor = textView as? ComposerTextView,
                text == "\n", editor.markedTextRange == nil,
                !editor.isInsertingLineBreak, !editor.isPasting
            else { return true }
            // Publish the current native value before the synchronous send action.
            parent.text = editor.text
            parent.submit()
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let editor = textView as? ComposerTextView else { return }
            editor.refreshPlaceholder()
            editor.invalidateIntrinsicContentSize()
            if editor.markedTextRange == nil { parent.text = editor.text }
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isFocused = false }
    }
}

final class ComposerTextView: UITextView {
    private let placeholderLabel = UILabel()
    private(set) var isInsertingLineBreak = false
    private(set) var isPasting = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.text = "继续追问…"
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var keyCommands: [UIKeyCommand]? {
        let lineBreaks = ["\r", "\n"].flatMap { input in
            [UIKeyModifierFlags.shift, .alternate].map { modifiers in
                let command = UIKeyCommand(
                    input: input, modifierFlags: modifiers,
                    action: #selector(insertLineBreak))
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }
        return (super.keyCommands ?? []) + lineBreaks
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let lineBreaks = presses.filter { press in
            guard let key = press.key else { return false }
            return key.keyCode == .keyboardReturnOrEnter
                && !key.modifierFlags.intersection([.shift, .alternate]).isEmpty
                && !key.modifierFlags.contains(.command)
        }
        guard !lineBreaks.isEmpty, markedTextRange == nil else {
            super.pressesBegan(presses, with: event)
            return
        }
        insertLineBreak()
        let remaining = presses.subtracting(lineBreaks)
        if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
    }

    @objc private func insertLineBreak() {
        guard markedTextRange == nil else { return }
        isInsertingLineBreak = true
        defer { isInsertingLineBreak = false }
        insertText("\n")
    }

    override func paste(_ sender: Any?) {
        isPasting = true
        defer { isPasting = false }
        super.paste(sender)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.font = font
        placeholderLabel.frame = CGRect(
            origin: .zero,
            size: placeholderLabel.sizeThatFits(
                CGSize(
                    width: bounds.width,
                    height: .greatestFiniteMagnitude)))
        refreshPlaceholder()
    }

    func refreshPlaceholder() { placeholderLabel.isHidden = !text.isEmpty || markedTextRange != nil }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        super.setMarkedText(markedText, selectedRange: selectedRange)
        refreshPlaceholder()
    }

    override func unmarkText() {
        super.unmarkText()
        refreshPlaceholder()
        if let delegate { delegate.textViewDidChange?(self) }
    }
}
#endif
