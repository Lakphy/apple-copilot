import SwiftUI
import WebKit
import CopilotCore

extension EnvironmentValues {
    @Entry var scrollMarkdownAnchor = MarkdownAnchorAction { _ in }
}

struct MarkdownAnchorAction {
    let perform: (CGFloat) -> Void
    func callAsFunction(_ offset: CGFloat) { perform(offset) }
}

/// A local, persistent document per message. Streaming changes the DOM instead
/// of reloading WebKit, preserving selection and horizontal code scrolling.
struct RichMarkdownView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scrollMarkdownAnchor) private var scrollAnchor
    @ScaledMetric(relativeTo: .body) private var fontSize = RichMarkdownView.defaultFontSize
    @ScaledMetric(relativeTo: .title) private var titleSize = RichMarkdownView.defaultTitleSize
    @ScaledMetric(relativeTo: .title2) private var title2Size = RichMarkdownView.defaultTitle2Size
    @ScaledMetric(relativeTo: .title3) private var title3Size = RichMarkdownView.defaultTitle3Size
    let markdown: String
    var isStreaming = false
    @State private var height: CGFloat = 1
    @State private var position = MarkdownContentPosition()
    @State private var failed = false

    private static var defaultFontSize: CGFloat {
        #if os(macOS)
        13
        #else
        17
        #endif
    }

    private static var defaultTitleSize: CGFloat {
        #if os(macOS)
        22
        #else
        28
        #endif
    }
    private static var defaultTitle2Size: CGFloat {
        #if os(macOS)
        17
        #else
        22
        #endif
    }
    private static var defaultTitle3Size: CGFloat {
        #if os(macOS)
        15
        #else
        20
        #endif
    }

    var body: some View {
        Group {
            if failed {
                Text(markdown).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownWebView(
                    markdown: markdown, isStreaming: isStreaming,
                    dark: colorScheme == .dark, fontSize: fontSize, height: $height,
                    onLink: { openURL($0) }, onAnchor: { scrollAnchor(position.top + $0) },
                    onFailure: { failed = true },
                    increasedContrast: contrast == .increased,
                    boldText: legibilityWeight == .bold, reduceMotion: reduceMotion,
                    headingSizes: [titleSize, title2Size, title3Size]
                )
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: height)
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .named("transcript")).minY
        } action: {
            position.top = $0
        }
    }
}

/// The latest anchor origin is only read when a link is activated. Geometry
/// updates don't need to invalidate the Markdown body or its representable.
@MainActor private final class MarkdownContentPosition { var top: CGFloat = 0 }
