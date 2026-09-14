import SwiftUI
import UIKit

// MARK: - Root tab bar chrome (custom floating bar)

/// `true` = floating tab bar may show. Reduced with AND across the tree.
enum TTRootTabBarVisibleKey: PreferenceKey {
    static var defaultValue: Bool = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}

private struct TTRootTabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Bottom clearance reserved for the floating tab bar (0 when chrome is hidden).
    var ttRootTabBarClearance: CGFloat {
        get { self[TTRootTabBarClearanceKey.self] }
        set { self[TTRootTabBarClearanceKey.self] = newValue }
    }
}

extension View {
    /// Publish whether the root floating tab bar should stay visible for this subtree.
    func ttRootTabBarVisible(_ visible: Bool) -> some View {
        preference(key: TTRootTabBarVisibleKey.self, value: visible)
    }

    /// Sync floating tab bar visibility with UINavigationController depth (root only).
    /// Place inside a `NavigationStack` so pushes outside the tab layer hide the bar.
    func ttSyncRootTabBarWithNavigationDepth() -> some View {
        background(alignment: .center) {
            TTNavigationDepthBridge()
        }
    }
}

/// Bridges UIKit nav-stack depth → SwiftUI preference (no duplicated nav state).
private struct TTNavigationDepthBridge: View {
    @State private var atRoot = true

    var body: some View {
        TTNavigationDepthReader(atRoot: $atRoot)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ttRootTabBarVisible(atRoot)
    }
}

private struct TTNavigationDepthReader: UIViewControllerRepresentable {
    @Binding var atRoot: Bool

    func makeUIViewController(context: Context) -> ProbeController {
        let probe = ProbeController()
        probe.onDepthChange = { depth in
            let root = depth <= 1
            if atRoot != root {
                atRoot = root
            }
        }
        return probe
    }

    func updateUIViewController(_ uiViewController: ProbeController, context: Context) {}

    final class ProbeController: UIViewController {
        var onDepthChange: ((Int) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            report()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            report()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            report()
        }

        private func report() {
            let depth = navigationController?.viewControllers.count ?? 1
            onDepthChange?(depth)
        }
    }
}
