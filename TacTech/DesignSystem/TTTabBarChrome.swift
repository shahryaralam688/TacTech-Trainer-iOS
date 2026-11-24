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

// MARK: - Tab screen transition

extension View {
    /// Root-tab screen transition — a quick cross-fade (0.2 s ease-out). Which tab is visible is a pure function of
    /// `selection`: the selected tab is at opacity 1 and every other tab at 0, whatever animation or timer is running.
    /// Nothing depends on an animation finishing, so quick taps, swipes or a retarget in the middle of a fade can never
    /// leave every tab hidden. SwiftUI retargets the running fade from its current value, so it is interruptible.
    /// Tabs stay mounted: state, scroll position and navigation stacks are untouched.
    /// (`order` is kept for the call sites; the fade needs no direction.)
    func ttTabFade<Tab: Hashable>(tab: Tab, selection: Tab, order: [Tab]) -> some View {
        modifier(TTTabFade(tab: tab, selection: selection))
    }
}

private struct TTTabFade<Tab: Hashable>: ViewModifier {
    let tab: Tab
    let selection: Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var duration: TimeInterval { 0.2 }

    func body(content: Content) -> some View {
        let selected = selection == tab
        content
            .opacity(selected ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: Self.duration), value: selected)
            // The incoming page renders above the outgoing one.
            .zIndex(selected ? 1 : 0)
            // A hidden tab is not read by VoiceOver.
            .accessibilityHidden(!selected)
    }
}

// MARK: - Swipe navigation
//
// Platform conventions (Apple HIG "Navigation"):
//  • Swiping from the leading screen edge goes back one level (never a different gesture).
//  • Horizontal swipes elsewhere on a root screen may move between sibling tabs.
// Both honour right-to-left layouts, so Arabic users swipe the mirrored way.

// MARK: Interactive pop with the app's custom (hidden) navigation bars

/// `navigationBarBackButtonHidden(true)` + a hidden bar silently disables UIKit's edge-swipe back.
/// Re-enable it for every `NavigationStack` once, here, instead of per screen.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Never start on the root screen — it would freeze the UI.
        viewControllers.count > 1
    }
}

// MARK: Full-screen covers / custom containers

private let ttEdgeWidth: CGFloat = 28
private let ttSwipeDistance: CGFloat = 70

extension View {
    /// Edge-swipe back for screens presented without a navigation controller
    /// (full-screen covers, in-view drill-downs like a chat thread).
    func ttEdgeSwipeBack(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(TTEdgeSwipeBack(enabled: enabled, action: action))
    }

    /// Swipe left/right on a root screen to move to the neighbouring tab.
    func ttSwipeBetweenTabs<Tab: Hashable>(
        order: [Tab],
        selection: Binding<Tab>,
        enabled: Bool = true
    ) -> some View {
        modifier(TTSwipeBetweenTabs(order: order, selection: selection, enabled: enabled))
    }
}

private struct TTEdgeSwipeBack: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onEnded { value in
                    guard enabled else { return }
                    let isLTR = layoutDirection == .leftToRight
                    let width = UIScreen.main.bounds.width
                    let startsAtLeadingEdge = isLTR
                        ? value.startLocation.x < ttEdgeWidth
                        : value.startLocation.x > width - ttEdgeWidth
                    let travel = isLTR ? value.translation.width : -value.translation.width
                    guard startsAtLeadingEdge,
                          travel > ttSwipeDistance,
                          abs(value.translation.height) < travel * 0.6 else { return }
                    TTKeyboard.dismiss()
                    action()
                }
        )
    }
}

private struct TTSwipeBetweenTabs<Tab: Hashable>: ViewModifier {
    let order: [Tab]
    @Binding var selection: Tab
    let enabled: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .global)
                .onEnded { value in
                    guard enabled, let index = order.firstIndex(of: selection) else { return }
                    let isLTR = layoutDirection == .leftToRight
                    let width = UIScreen.main.bounds.width
                    // The leading edge belongs to "back"; don't steal it.
                    let startsAtLeadingEdge = isLTR
                        ? value.startLocation.x < ttEdgeWidth
                        : value.startLocation.x > width - ttEdgeWidth
                    guard !startsAtLeadingEdge else { return }
                    let travel = isLTR ? value.translation.width : -value.translation.width
                    guard abs(travel) > ttSwipeDistance,
                          abs(value.translation.height) < abs(travel) * 0.5 else { return }
                    // Finger moving toward the leading side → next tab (like turning a page).
                    let next = travel < 0 ? index + 1 : index - 1
                    guard order.indices.contains(next) else { return }
                    TTKeyboard.dismiss()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = order[next]
                    }
                }
        )
    }
}
