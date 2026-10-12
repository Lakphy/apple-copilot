import SwiftUI
import CopilotCore

/// A square label keeps toolbar button geometry independent of SF Symbol proportions.
struct ToolbarActionIcon: View {
    let symbol: String

    private var size: CGFloat {
        #if os(macOS)
        16
        #else
        20
        #endif
    }

    var body: some View {
        Image(systemName: symbol)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

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
        .background(CopilotSurface.secondary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct GlassHistorySearch: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var text: String

    private var height: CGFloat {
        #if os(macOS)
        36
        #else
        44
        #endif
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索历史", text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel("搜索原文、译文或追问")
            if !text.isEmpty {
                Button("清除搜索", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: height - 8, height: height - 8)
                    .contentShape(.circle)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: height)
        .background(
            reduceTransparency ? AnyShapeStyle(CopilotSurface.secondary) : AnyShapeStyle(.clear),
            in: .capsule
        )
        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: .capsule)
    }
}

enum Clipboard {
    @MainActor static func copy(_ text: String) -> Bool {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        return true
        #endif
    }
}
