import SwiftUI
import CopilotCore

struct InlineNotice: View {
    let title: String
    let message: String
    var symbol = "exclamationmark.triangle"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            Text(message).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct GlassComposer: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var text: String
    let isWorking: Bool
    var onFocus: () -> Void = {}
    let send: () -> Void
    let cancel: () -> Void
    @FocusState private var isFocused: Bool

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
        .background(reduceTransparency ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.clear), in: shape)
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
        TextField("追问内容", text: $text,
                  prompt: Text("继续追问…").foregroundStyle(Color.secondary), axis: .vertical)
            .font(.body)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: .infinity)
            .focused($isFocused)
            .accessibilityLabel("追问内容")
    }

    private var action: some View {
        Button(action: isWorking ? cancel : send) {
            Image(systemName: isWorking ? "stop.fill" : "arrow.up")
                .font(.system(size: actionSymbolSize, weight: .semibold))
                .foregroundStyle(canSend ? AnyShapeStyle(colorScheme == .dark ? Color.black : Color.white) : AnyShapeStyle(Color.secondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.circle)
                .background(canSend ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: .circle)
        }
        // Only the outer composer uses glass; the inset action has a solid tint.
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help(isWorking ? "停止生成" : "发送追问")
        .accessibilityLabel(isWorking ? "停止生成" : "发送追问")
        .keyboardShortcut(.return, modifiers: [.command])
    }
}

/// Keep one stable TextField while moving the inset action between a compact
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
        subviews[0].place(at: CGPoint(x: bounds.minX + 14, y: inputY), anchor: .topLeading,
                          proposal: .init(width: inputWidth(for: bounds.width), height: height))
        let inset: CGFloat = isExpanded ? 8 : 6
        subviews[1].place(at: CGPoint(x: bounds.maxX - actionSize - inset, y: bounds.maxY - actionSize - inset), anchor: .topLeading,
                          proposal: .init(width: actionSize, height: actionSize))
    }
}

enum Clipboard {
    @MainActor static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

struct SourceText: View {
    let text: String
    @State private var isExpanded = false

    private var needsExpansion: Bool { text.count > 180 || text.filter { $0 == "\n" }.count > 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原文").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(needsExpansion && !isExpanded ? 4 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            if needsExpansion {
                Button(isExpanded ? "收起原文" : "展开原文", systemImage: isExpanded ? "chevron.up" : "chevron.down") {
                    isExpanded.toggle()
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .padding(.vertical, 6)
            }
        }
        .onChange(of: text) { _, _ in isExpanded = false }
    }
}

struct ConversationTranscript: View {
    let conversation: Conversation
    var onSettings: (() -> Void)?
    var replaceTranslation: ((String) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            SourceText(text: conversation.sourceText)
            Divider()
            ForEach(Array(conversation.messages.dropFirst().enumerated()), id: \.element.id) { index, message in
                if message.role == .user {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("追问").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text(message.content).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.background.secondary, in: .rect(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if index == 0 {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("译文").font(.headline)
                                    Text(conversation.configuration.targetLanguage)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                translationActions(message.content)
                            }
                        } else {
                            Text("回复").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                        Text(message.content)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contextMenu { Button("复制", systemImage: "doc.on.doc") { Clipboard.copy(message.content) } }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func translationActions(_ translation: String) -> some View {
        if onSettings != nil || replaceTranslation != nil {
            Menu {
                Button("复制译文", systemImage: "doc.on.doc") { Clipboard.copy(translation) }
                if let replaceTranslation {
                    Button("替换原文", systemImage: "arrow.triangle.2.circlepath") { replaceTranslation(translation) }
                }
                if let onSettings { Button("设置", systemImage: "gearshape", action: onSettings) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: actionSize, height: actionSize)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("译文操作")
        } else {
            Button("复制译文", systemImage: "doc.on.doc") { Clipboard.copy(translation) }
                .labelStyle(.iconOnly)
                .font(.system(size: 17))
                .frame(width: actionSize, height: actionSize)
                .buttonStyle(.borderless)
                .help("复制译文")
        }
    }

    private var actionSize: CGFloat {
        #if os(macOS)
        28
        #else
        44
        #endif
    }
}
