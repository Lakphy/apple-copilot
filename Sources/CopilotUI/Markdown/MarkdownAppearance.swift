import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Resolve semantic colors at the native boundary so the local document uses
/// the same surfaces and accessibility appearance as the surrounding SwiftUI.
@MainActor
enum MarkdownAppearance {
    #if os(macOS)
    static func appearance(dark: Bool, increasedContrast: Bool) -> NSAppearance? {
        let name: NSAppearance.Name =
            increasedContrast
            ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (dark ? .darkAqua : .aqua)
        return NSAppearance(named: name)
    }
    #endif

    static func palette(dark: Bool, increasedContrast: Bool) -> [String: String] {
        var colors: [String: String] = [:]
        #if os(macOS)
        appearance(dark: dark, increasedContrast: increasedContrast)?.performAsCurrentDrawingAppearance {
            let surface = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
            func hex(_ color: NSColor) -> String {
                let rgb = color.usingColorSpace(.sRGB)!
                return composite(
                    red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent,
                    alpha: rgb.alphaComponent,
                    background: (surface.redComponent, surface.greenComponent, surface.blueComponent))
            }
            colors = [
                "surface": hex(surface), "fg": hex(.textColor), "muted": hex(.secondaryLabelColor),
                "panel": hex(.underPageBackgroundColor), "line": hex(.separatorColor),
                "accent": hex(.linkColor), "focus": hex(.keyboardFocusIndicatorColor),
            ]
        }
        #else
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = dark ? .dark : .light
            traits.accessibilityContrast = increasedContrast ? .high : .normal
        }
        func components(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (r, g, b, a)
        }
        let surface = components(.systemBackground)
        func hex(_ color: UIColor) -> String {
            let c = components(color)
            return composite(red: c.0, green: c.1, blue: c.2, alpha: c.3, background: (surface.0, surface.1, surface.2))
        }
        colors = [
            "surface": hex(.systemBackground), "fg": hex(.label), "muted": hex(.secondaryLabel),
            "panel": hex(.secondarySystemBackground), "line": hex(.separator),
            "accent": hex(.link), "focus": hex(.systemBlue),
        ]
        #endif
        return colors
    }

    nonisolated private static func composite(
        red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat,
        background: (CGFloat, CGFloat, CGFloat)
    ) -> String {
        let channels = [
            red * alpha + background.0 * (1 - alpha),
            green * alpha + background.1 * (1 - alpha),
            blue * alpha + background.2 * (1 - alpha),
        ]
        return "#" + channels.map { String(format: "%02x", Int((min(1, max(0, $0)) * 255).rounded())) }.joined()
    }
}
