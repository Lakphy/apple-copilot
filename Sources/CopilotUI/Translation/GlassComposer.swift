import CopilotCore
import SwiftUI

struct GlassComposer: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var text: String
    let isWorking: Bool
    var onFocus: () -> Void = {}
    let send: () -> Void
    let cancel: () -> Void
    #if os(macOS)
    @FocusState private var isFocused: Bool
    #else
    @State private var isFocused = false
    #endif

    private var controlHeight: CGFloat {
        #if os(macOS)
        36
        #else
        44
        #endif
    }

    private var canSend: Bool {
        isWorking || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isExpanded: Bool { isFocused || !text.isEmpty || isWorking }

    private var shape: AnyShape {
        isExpanded ? AnyShape(RoundedRectangle(cornerRadius: 24)) : AnyShape(Capsule())
    }

    private var actionSymbolSize: CGFloat {
        #if os(macOS)
        15
        #else
        17
        #endif
    }

    var body: some View {
        ComposerLayout(actionSize: controlHeight, isExpanded: isExpanded) {
            input
            action
        }
        .background(reduceTransparency ? AnyShapeStyle(CopilotSurface.secondary) : AnyShapeStyle(.clear), in: shape)
        .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
        #if os(macOS)
        .overlay {
            shape.stroke(isFocused ? Color.accentColor : .clear, lineWidth: 1.5)
            .allowsHitTesting(false)
        }
        #endif
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: isFocused) { _, focused in if focused { onFocus() } }
        #if os(macOS)
        .onExitCommand { isFocused = false }
        #endif
    }

    private var input: some View {
        #if os(macOS)
        TextField(
            "追问内容", text: $text,
            prompt: Text("继续追问…").foregroundStyle(Color.secondary), axis: .vertical
        )
        .font(.body)
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .submitLabel(.send)
        .onSubmit(submit)
        .focused($isFocused)
        .composerInputFrame(height: controlHeight)
        #else
        NativeComposerTextEditor(
            text: $text,
            isFocused: Binding(get: { isFocused }, set: { isFocused = $0 }),
            submit: submit
        )
        .composerInputFrame(height: controlHeight)
        #endif
    }

    private var action: some View {
        Button(action: isWorking ? cancel : submit) {
            Image(systemName: isWorking ? "stop.fill" : "arrow.up")
                .font(.system(size: actionSymbolSize, weight: .semibold))
                .foregroundStyle(
                    canSend
                        ? AnyShapeStyle(colorScheme == .dark ? Color.black : Color.white)
                        : AnyShapeStyle(Color.secondary)
                )
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(.circle)
                .background(canSend ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: .circle)
        }
        // Only the outer composer uses glass; the inset action has a solid tint.
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(isWorking ? "停止生成" : "发送追问")
        .accessibilityLabel(isWorking ? "停止生成" : "发送追问")
        .keyboardShortcut(isWorking ? nil : KeyboardShortcut(.return, modifiers: .command))
    }

    private func submit() {
        #if os(macOS)
        guard NSTextInputContext.current?.client.hasMarkedText() != true else { return }
        #endif
        guard !isWorking, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        send()
    }
}

private extension View {
    func composerInputFrame(height: CGFloat) -> some View {
        padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: .infinity)
            .accessibilityLabel("追问内容")
    }
}

/// Keep one stable input while moving the inset action between a compact
/// single row and the expanded bottom row. Changing focus never recreates it.
private struct ComposerLayout: Layout {
    let actionSize: CGFloat
    let isExpanded: Bool

    private func inputWidth(for width: CGFloat) -> CGFloat {
        max(1, isExpanded ? width - 28 : width - 14 - 8 - actionSize - 6)
    }

    private func inputHeight(for width: CGFloat, subviews: Subviews) -> CGFloat {
        subviews[0].sizeThatFits(.init(width: inputWidth(for: width), height: nil)).height
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let height = inputHeight(for: width, subviews: subviews)
        return CGSize(width: width, height: isExpanded ? height + 8 + actionSize + 16 : max(actionSize, height) + 12)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let height = inputHeight(for: bounds.width, subviews: subviews)
        // SwiftUI mirrors custom-layout positions for right-to-left languages.
        let inputY = isExpanded ? bounds.minY + 8 : bounds.midY - height / 2
        subviews[0].place(
            at: CGPoint(x: bounds.minX + 14, y: inputY), anchor: .topLeading,
            proposal: .init(width: inputWidth(for: bounds.width), height: height))
        let inset: CGFloat = isExpanded ? 8 : 6
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - actionSize - inset, y: bounds.maxY - actionSize - inset), anchor: .topLeading,
            proposal: .init(width: actionSize, height: actionSize))
    }
}
