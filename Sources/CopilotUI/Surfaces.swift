import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shared semantic surfaces keep navigation between pages visually stable,
/// while preserving the system's appearance and contrast adaptations.
enum CopilotSurface {
    static var page: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var secondary: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }
}

extension View {
    func copilotPageBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CopilotSurface.page, ignoresSafeAreaEdges: .all)
    }
}
