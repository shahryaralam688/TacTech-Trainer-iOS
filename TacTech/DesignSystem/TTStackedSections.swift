import SwiftUI

// MARK: - Stacked Sections (Cards & Lists)

/// Sticky chapter-style deck — Animata `StackedSections` pattern, TacTech tokens.
///
/// Cards keep normal list spacing until they hit the pin line; then each sticks with a
/// `stackOffset` peek of the card underneath while the next one covers it.
struct TTStackedSections<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Identifiable {
    let data: Data
    var stackOffset: CGFloat = TTStackedTokens.stackOffset
    var withDramaEffect: Bool = true
    var paneGap: CGFloat = TTStackedTokens.paneGap
    /// Extra in-flow space after the last pane so it can stay pinned through the outro.
    var scrollRunway: CGFloat = TTStackedTokens.defaultRunway
    /// Caps how deep the sticky ladder climbs (keeps long lists usable).
    var maxPinnedDepth: Int = TTStackedTokens.maxPinnedDepth
    /// Prefer the named space already on your ScrollView (e.g. home-collapse space).
    var coordinateSpaceName: String? = nil
    @ViewBuilder var content: (Data.Element) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let items = Array(data)
        let total = items.count

        VStack(spacing: paneGap) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                TTStackedPane(
                    index: index,
                    total: total,
                    stackOffset: stackOffset,
                    maxPinnedDepth: maxPinnedDepth,
                    withDramaEffect: withDramaEffect && !reduceMotion,
                    coordinateSpaceName: coordinateSpaceName
                ) {
                    content(item)
                }
            }

            if scrollRunway > 0, total > 1 {
                Color.clear
                    .frame(height: scrollRunway)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Binding variant for editable stacks (e.g. plan exercise drafts).
struct TTStackedForEach<Element: Identifiable, Content: View>: View {
    @Binding var data: [Element]
    var stackOffset: CGFloat = TTStackedTokens.stackOffset
    var withDramaEffect: Bool = true
    var paneGap: CGFloat = TTStackedTokens.paneGap
    var scrollRunway: CGFloat = TTStackedTokens.defaultRunway
    var maxPinnedDepth: Int = TTStackedTokens.maxPinnedDepth
    var coordinateSpaceName: String? = nil
    @ViewBuilder var content: (Binding<Element>) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = data.count

        VStack(spacing: paneGap) {
            ForEach($data) { $item in
                let index = data.firstIndex(where: { $0.id == item.id }) ?? 0
                TTStackedPane(
                    index: index,
                    total: total,
                    stackOffset: stackOffset,
                    maxPinnedDepth: maxPinnedDepth,
                    withDramaEffect: withDramaEffect && !reduceMotion,
                    coordinateSpaceName: coordinateSpaceName
                ) {
                    content($item)
                }
            }

            if scrollRunway > 0, total > 1 {
                Color.clear
                    .frame(height: scrollRunway)
                    .accessibilityHidden(true)
            }
        }
    }
}

enum TTStackedTokens {
    /// Peek band when the next pane covers this one.
    static let stackOffset: CGFloat = 40
    static let paneGap: CGFloat = TTSpace.md
    /// Default runway so the last card can finish its pin.
    static let defaultRunway: CGFloat = 160
    /// How many peeks can stack before later cards share the same pin line.
    static let maxPinnedDepth: Int = 6
    static let corner: CGFloat = TTCardTokens.listCorner
}

// MARK: - Pane

private struct TTStackedPane<Content: View>: View {
    let index: Int
    let total: Int
    let stackOffset: CGFloat
    let maxPinnedDepth: Int
    let withDramaEffect: Bool
    let coordinateSpaceName: String?
    @ViewBuilder var content: () -> Content

    private var pinnedTop: CGFloat {
        CGFloat(min(index, max(0, maxPinnedDepth - 1))) * stackOffset
    }

    private var endScale: CGFloat {
        let depthFromFront = CGFloat(min(index, maxPinnedDepth - 1))
        return max(0.92, 1.0 - 0.025 * depthFromFront)
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(Double(index + 1))
            .visualEffect { view, proxy in
                let minY = scrollMinY(proxy)
                let pin = pinnedTop
                let stickY = max(0, pin - minY)

                let rowH = max(proxy.size.height, 1)
                let coverProgress = min(1, max(0, stickY / rowH))
                let scale = withDramaEffect
                    ? 1 + (endScale - 1) * coverProgress
                    : 1

                return view
                    .scaleEffect(scale, anchor: .top)
                    .offset(y: stickY)
            }
    }

    private func scrollMinY(_ proxy: GeometryProxy) -> CGFloat {
        if let coordinateSpaceName {
            return proxy.frame(in: .named(coordinateSpaceName)).minY
        }
        return proxy.frame(in: .scrollView(axis: .vertical)).minY
    }
}
