import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// Only installed in the wide iPad workspace; compact navigation keeps its
/// normal gestures. Use the native split controller's public configuration.
struct FixedSidebarPolicy: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PolicyController { PolicyController() }

    func updateUIViewController(_ controller: PolicyController, context: Context) {
        controller.applyPolicy()
    }

    final class PolicyController: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyPolicy()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyPolicy()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyPolicy()
        }

        func applyPolicy() {
            guard let split = splitViewController else { return }
            split.presentsWithGesture = false
            split.showsSecondaryOnlyButton = false
            if split.preferredSplitBehavior != .tile { split.preferredSplitBehavior = .tile }
            if split.preferredDisplayMode != .oneBesideSecondary {
                split.preferredDisplayMode = .oneBesideSecondary
            }
        }
    }
}
#endif
