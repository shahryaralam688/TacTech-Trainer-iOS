import SwiftUI

/// Status chip under the home greeting (e.g. "88% Healthy", "Pro").
struct TTHomeProfileMetric: Identifiable, Hashable {
    let id: String
    let icon: SandowIcon
    let iconColor: Color
    let text: String

    init(id: String = UUID().uuidString, icon: SandowIcon, iconColor: Color, text: String) {
        self.id = id
        self.icon = icon
        self.iconColor = iconColor
        self.text = text
    }
}

/// How far home must scroll before the header is fully compact.
enum TTHomeHeaderCollapse {
    /// Longer travel = shrink/expand feels paced, not sudden.
    static let distance: CGFloat = 188

    /// Ignore tiny flicks so light scrolls don’t enter a half-shrunk look.
    static let leadIn: CGFloat = 36

    /// On finger-up, snap fully expanded below this; fully compact at/above.
    static let settleThreshold: CGFloat = 0.38

    /// Approximate height delta of `TTHomeProfileHeader` expanded → compact.
    /// Must match real layout travel or ScrollView offset compensation fights and vibrates.
    static let homeLayoutTravel: CGFloat = 102

    /// Finger-up settle — soft spring (Apple Music / Photos style), not a hard ease.
    static let settleAnimation: Animation = .spring(response: 0.44, dampingFraction: 0.86)

    /// Linear map after lead-in — mid values are temporary while dragging only.
    static func progress(for offset: CGFloat) -> CGFloat {
        let adjusted = max(0, offset - leadIn)
        let span = max(1, distance - leadIn)
        return min(1, max(0, adjusted / span))
    }

    /// Visual easing so mid-drag doesn’t look half-broken (smoothstep).
    static func displayProgress(from linear: CGFloat) -> CGFloat {
        let t = min(1, max(0, linear))
        return t * t * (3 - 2 * t)
    }
}

/// Home top bar — scroll-synced collapse to avatar + name + forward.
struct TTHomeProfileHeader: View {
    let name: String
    var avatarSymbol: String? = nil
    var avatarUrl: String? = nil
    var avatarUserId: String? = nil
    var avatarInitial: String? = nil
    var badgeCount: Int = 0
    /// Shows AI Coach Pro chip next to name when true (server-confirmed).
    var showsAIPro: Bool = false
    var metrics: [TTHomeProfileMetric] = []
    var date: Date = .now
    /// 0 = expanded. 1 = compact (avatar + name; bell stays visible).
    var collapseProgress: CGFloat = 0
    var onProfileTap: (() -> Void)? = nil
    var onNotificationTap: (() -> Void)? = nil

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let dateGrey = Color.white.opacity(0.55)
    private let bellBG = Color(white: 0.22)

    private var p: CGFloat {
        TTHomeHeaderCollapse.displayProgress(from: collapseProgress)
    }
    private var expand: CGFloat { 1 - p }

    private var avatarSide: CGFloat { 58 - 18 * p } // 58 → 40
    private var avatarRadius: CGFloat { 16 - 4 * p } // 16 → 12
    /// Name size tracks avatar height (~38% of avatar) so type stays proportional.
    private var titleSize: CGFloat { max(16, avatarSide * 0.38) } // ~22 → ~15
    private var greetingSize: CGFloat { max(12, avatarSide * 0.24) } // ~14 → ~10
    private var rowSpacing: CGFloat { 14 - 2 * p }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 22 * expand) {
                topRow
                    .opacity(Double(expand))
                    .frame(height: 54 * expand, alignment: .top)
                    .clipped()
                    .allowsHitTesting(p < 0.35)

                profileRow
            }

            // Notifications bell stays visible and tappable in both expanded (p = 0) and collapsed (p = 1) states.
            notificationBellButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 12 - 2 * p)
        .padding(.bottom, 22 - 10 * p)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.black
                TTHomeHeaderBands()
                    .fill(Color.white.opacity(0.07 * Double(expand)))
            }
            .ignoresSafeArea(edges: .top)
        }
        // Soft lift into compact — reads as chrome morph, not a hard cut.
        .shadow(
            color: .black.opacity(0.18 * Double(p)),
            radius: 10 * p,
            y: 4 * p
        )
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        // No spring on scroll-driven `p` — collapse tracks finger 1:1; settle spring is in the model.
    }

    // MARK: - Rows

    private var topRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                TTIcon(icon: .calendar1, size: 14)
                Text(formattedDate)
                    .font(TTFont.textSM(.regular))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(dateGrey)

            Spacer()

            // Reserve trailing space for the persistent `notificationBellButton` overlay.
            Color.clear.frame(width: 48, height: 48)
        }
    }

    private var notificationBellButton: some View {
        Button {
            if let onNotificationTap {
                onNotificationTap()
            } else {
                onProfileTap?()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                TTIcon(icon: .bell1, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(bellBG)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if badgeCount > 0 {
                    Text("\(min(badgeCount, 9))")
                        .font(TTFont.text2XS(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(orange)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black, lineWidth: 1.5)
                        )
                        .offset(x: 4, y: -4)
                        .ttHomeBadgePop(active: badgeCount > 0)
                }
            }
            // Keep badge inside the hit target.
            .padding(.top, 4)
            .padding(.trailing, 4)
        }
        .buttonStyle(TTHomeHeaderPressStyle())
        .accessibilityLabel(
            badgeCount > 0
                ? String(localized: "Notifications, \(badgeCount) unread", locale: LocalizationController.shared.locale)
                : String(localized: "Notifications", locale: LocalizationController.shared.locale)
        )
    }

    private var profileRow: some View {
        Button {
            onProfileTap?()
        } label: {
            HStack(spacing: rowSpacing) {
                avatarView(side: avatarSide, corner: avatarRadius)

                VStack(alignment: .leading, spacing: 7 * expand) {
                    profileNameLabel

                    if !metrics.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                                if index > 0 {
                                    Circle()
                                        .fill(Color.white.opacity(0.45))
                                        .frame(width: 3, height: 3)
                                        .padding(.horizontal, 2)
                                }
                                HStack(spacing: 5) {
                                    TTIcon(icon: metric.icon, size: 12)
                                        .foregroundStyle(metric.iconColor)
                                    Text(metric.text)
                                        .font(TTFont.textMD(.regular))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .opacity(Double(expand))
                        .frame(height: 22 * expand, alignment: .top)
                        .clipped()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                // Keep text clear of the persistent trailing bell when collapsed.
                .padding(.trailing, 54 * p)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TTHomeHeaderPressStyle())
        .accessibilityLabel("Open profile, \(name)")
        .accessibilityHint("Opens your profile")
    }

    /// Long names scale / wrap instead of hard “…” truncation.
    @ViewBuilder
    private var profileNameLabel: some View {
        let expanded = p < 0.55
        let display = TTHomeDelight.homeDisplayName(name)

        if expanded {
            VStack(alignment: .leading, spacing: 2) {
                Text(TTHomeDelight.greetingPrefix(date: date))
                    .font(TTFont.workSans(greetingSize, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 8) {
                    Text(display)
                        .font(TTFont.workSans(titleSize, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsAIPro {
                        AIProBadge(style: .compact)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                showsAIPro
                    ? "\(TTHomeDelight.greeting(for: display, date: date)), AI Coach Pro subscriber"
                    : TTHomeDelight.greeting(for: display, date: date)
            )
        } else {
            HStack(spacing: 6) {
                Text(display)
                    .font(TTFont.workSans(titleSize, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if showsAIPro {
                    AIProBadge(style: .compact)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func avatarView(side: CGFloat, corner: CGFloat) -> some View {
        TTUserAvatarView(
            avatarUrl: avatarUrl,
            avatarAsset: avatarSymbol,
            userId: avatarUserId,
            name: avatarInitial.map { String($0) } ?? name,
            size: side,
            shape: .roundedRect,
            cornerRadius: corner,
            strokeColor: Color.white.opacity(0.22),
            strokeWidth: 1.5,
            initialsForeground: .white,
            initialsBackground: Color.white.opacity(0.14)
        )
    }

    private var formattedDate: String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(LocalizationController.shared.locale)
        )
    }
}

/// Subtle diagonal ribbon texture for the home header card.
struct TTHomeHeaderBands: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -40, y: 20))
        path.addQuadCurve(to: CGPoint(x: 120, y: -10), control: CGPoint(x: 40, y: -30))
        path.addQuadCurve(to: CGPoint(x: -20, y: 90), control: CGPoint(x: 70, y: 40))
        path.closeSubpath()

        path.move(to: CGPoint(x: -30, y: 50))
        path.addQuadCurve(to: CGPoint(x: 90, y: 10), control: CGPoint(x: 30, y: 0))
        path.addQuadCurve(to: CGPoint(x: -10, y: 110), control: CGPoint(x: 50, y: 55))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.maxX + 30, y: rect.maxY - 10))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 130, y: rect.maxY + 20),
            control: CGPoint(x: rect.maxX - 40, y: rect.maxY + 40)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + 10, y: rect.maxY - 80),
            control: CGPoint(x: rect.maxX - 60, y: rect.maxY - 30)
        )
        path.closeSubpath()
        return path
    }
}

/// Press feedback without the default disabled/dull fade.
private struct TTHomeHeaderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Collapsing header screen (content never depends on header progress)

/// Scroll progress for `TTCollapsingHeaderScreen`. Only the header, its corner "ears" and the sheet
/// background observe this object, so a scroll tick never rebuilds the screen's content.
@MainActor
final class TTHeaderCollapseState: ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    /// iOS 17 path: first sample is taken as "at rest".
    private var restMinY: CGFloat?

    /// Content must scroll at least this far before the header collapses at all (below it: stays expanded, no jitter).
    static let minScrollable: CGFloat = 24

    /// Scroll distance over which progress runs 0 → 1. Full travel when the content scrolls that far; a short but
    /// scrollable page collapses over its whole (shorter) range, so the header is fully compact exactly at the
    /// bottom — never stuck half-way and no blank tail is needed. `nil` = nothing to collapse.
    static func collapseSpan(maxOffset: CGFloat, travel: CGFloat) -> CGFloat? {
        guard travel > 1, maxOffset >= minScrollable else { return nil }
        return min(travel, maxOffset)
    }

    /// `offset` is 0 at rest. `maxOffset` is the furthest the content can scroll.
    /// Collapse is decided from `maxOffset` vs. the travel `d`; both are independent of the header's
    /// current height (the content inset is constant), so there is no feedback loop.
    func update(offset: CGFloat, maxOffset: CGFloat, travel: CGFloat, enabled: Bool) {
        let span = enabled ? Self.collapseSpan(maxOffset: maxOffset, travel: travel) : nil
        let next = span.map { min(1, max(0, offset / $0)) } ?? 0
        if abs(next - progress) > 0.001 { progress = next }
    }

    /// iOS 18 path: the scroll callback delivers an already clamped 1%-step progress. Writes only on change.
    func apply(step: Int, enabled: Bool) {
        let next = enabled ? CGFloat(min(100, max(0, step))) / 100 : 0
        if abs(next - progress) > 0.004 { progress = next }
    }

    private var lastLegacyMinY: CGFloat?

    /// iOS 17: position of the content's top edge in the scroll view's space. `maxOffset` is an estimate from the
    /// content and viewport heights (measured on size changes only), since iOS 17 can't report the scroll range.
    func updateLegacy(minY: CGFloat, maxOffset: CGFloat, travel: CGFloat, enabled: Bool) {
        if restMinY == nil { restMinY = minY }
        lastLegacyMinY = minY
        update(offset: (restMinY ?? minY) - minY, maxOffset: maxOffset, travel: travel, enabled: enabled)
    }

    /// iOS 17: the content or viewport size changed — re-apply the short-content rule with the last known offset.
    func refreshLegacy(maxOffset: CGFloat, travel: CGFloat, enabled: Bool) {
        guard let minY = lastLegacyMinY else { return }
        update(offset: (restMinY ?? minY) - minY, maxOffset: maxOffset, travel: travel, enabled: enabled)
    }

    func resetBaseline() { restMinY = nil }
}

/// What the iOS 18 scroll callback reports: a clamped progress in 1% steps plus "can collapse".
/// Layout thrash that doesn't move these two values (insets, margins, bounce) produces no callback at all.
private struct TTCollapseSignal: Equatable {
    var step: Int
    var canCollapse: Bool
}

/// iOS 17 only: the scrolled content's height and the scroll view's height, each reported only when it changes.
private struct TTLegacyContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TTLegacyViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TTCollapseLegacyKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TTHeaderExpandedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TTHeaderCollapsedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Dark header over a white, top-rounded content sheet that collapses with the scroll.
///
/// - The header is drawn **over** the scroll view; the scroll view reserves a constant top inset equal
///   to the *expanded* header height. The content area therefore never changes size with progress.
/// - Expanded and collapsed heights are **measured** from two hidden copies of the header
///   (`header(0)`, `header(1)`), so Dynamic Type is handled. `d = expanded - collapsed`.
/// - `progress = clamp(offset / d)`, driven continuously by the scroll offset. If the content can't
///   scroll at least `d`, the header stays expanded. Overscroll (negative offset) gives 0.
/// - Reduce Motion: the header stays expanded.
/// - No snapping to the nearest end: that needs programmatic scrolling, which isn't reliable on iOS 17.
struct TTCollapsingHeaderScreen<Header: View, Content: View>: View {
    var sheetFill: Color = .white
    var headerBackground: Color = .black
    /// Sheet corner radius for a given progress. Default is the Home lip (44 → 28).
    var topRadius: (CGFloat) -> CGFloat = { TTSheetChrome.homeTopRadius(collapseProgress: $0) }
    /// `true`: the scroll view's top inset is the *collapsed* header height and the content starts with a
    /// spacer of `d`. Pinned section headers then stick directly under the collapsed header (no gap).
    /// Both the inset and the spacer are constant, so content size still never depends on progress.
    var pinsBelowCollapsedHeader: Bool = false
    /// With `pinsBelowCollapsedHeader`: id of the top spacer, so `ScrollViewProxy.scrollTo(id)` returns to rest.
    var topAnchorID: String? = nil
    var onRefresh: (() async -> Void)? = nil
    @ViewBuilder var header: (_ progress: CGFloat) -> Header
    @ViewBuilder var content: () -> Content

    init(
        sheetFill: Color = .white,
        headerBackground: Color = .black,
        topRadius: @escaping (CGFloat) -> CGFloat = { TTSheetChrome.homeTopRadius(collapseProgress: $0) },
        pinsBelowCollapsedHeader: Bool = false,
        topAnchorID: String? = nil,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder header: @escaping (_ progress: CGFloat) -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.sheetFill = sheetFill
        self.headerBackground = headerBackground
        self.topRadius = topRadius
        self.pinsBelowCollapsedHeader = pinsBelowCollapsedHeader
        self.topAnchorID = topAnchorID
        self.onRefresh = onRefresh
        self.header = header
        self.content = content
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = TTHeaderCollapseState()
    @State private var expandedHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0
    @State private var legacyContentHeight: CGFloat = 0
    @State private var legacyViewportHeight: CGFloat = 0

    private var travel: CGFloat { max(0, expandedHeight - collapsedHeight) }

    /// iOS 17 estimate of how far the content can scroll: content + top inset − viewport. (Safe areas cancel out;
    /// bottom margins are already part of the content's own bottom padding.) 0 until both sizes are known, so the
    /// header stays expanded until then.
    private var legacyMaxOffset: CGFloat {
        guard legacyContentHeight > 0, legacyViewportHeight > 0 else { return 0 }
        let topInset = pinsBelowCollapsedHeader ? collapsedHeight : expandedHeight
        return legacyContentHeight + topInset - legacyViewportHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            scroll

            TTCollapsingHeaderHost(
                model: model,
                background: headerBackground,
                topRadius: topRadius,
                header: header
            )

            // Hidden copies measure the two end states once per layout change (not per scroll frame).
            ZStack(alignment: .top) {
                header(0)
                    .background(GeometryReader { Color.clear.preference(key: TTHeaderExpandedHeightKey.self, value: $0.size.height) })
                header(1)
                    .background(GeometryReader { Color.clear.preference(key: TTHeaderCollapsedHeightKey.self, value: $0.size.height) })
            }
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onPreferenceChange(TTHeaderExpandedHeightKey.self) { value in
            if abs(value - expandedHeight) > 0.5 {
                expandedHeight = value
                model.resetBaseline()
            }
        }
        .onPreferenceChange(TTHeaderCollapsedHeightKey.self) { value in
            if abs(value - collapsedHeight) > 0.5 { collapsedHeight = value }
        }
    }

    @ViewBuilder
    private var scroll: some View {
        let base = ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                legacyProbe
                if pinsBelowCollapsedHeader {
                    topSpacer
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) {
                TTCollapsingSheetBackground(model: model, fill: sheetFill, topRadius: topRadius)
            }
            .background { legacyContentMeasure }
        }
        .background { legacyViewportMeasure }
        .onPreferenceChange(TTLegacyContentHeightKey.self) { value in
            if abs(value - legacyContentHeight) > 0.5 { legacyContentHeight = value }
        }
        .onPreferenceChange(TTLegacyViewportHeightKey.self) { value in
            if abs(value - legacyViewportHeight) > 0.5 { legacyViewportHeight = value }
        }
        // Rubber-band always, so pull-to-refresh also works with short content.
        .scrollBounceBehavior(.always)
        // Constant reserve for the expanded header: content never moves because the header shrinks.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: pinsBelowCollapsedHeader ? collapsedHeight : expandedHeight)
        }
        .modifier(TTCollapseObserver(
            model: model, travel: travel, enabled: !reduceMotion,
            legacyMaxOffset: legacyMaxOffset
        ))

        if let onRefresh {
            base.refreshable { await onRefresh() }
        } else {
            base
        }
    }

    @ViewBuilder
    private var topSpacer: some View {
        if let topAnchorID {
            Color.clear.frame(height: travel).id(topAnchorID)
        } else {
            Color.clear.frame(height: travel)
        }
    }

    @ViewBuilder
    private var legacyContentMeasure: some View {
        if #unavailable(iOS 18.0) {
            GeometryReader { geo in
                Color.clear.preference(key: TTLegacyContentHeightKey.self, value: geo.size.height)
            }
        }
    }

    @ViewBuilder
    private var legacyViewportMeasure: some View {
        if #unavailable(iOS 18.0) {
            GeometryReader { geo in
                Color.clear.preference(key: TTLegacyViewportHeightKey.self, value: geo.size.height)
            }
        }
    }

    /// iOS 17 only: reports the content's top edge. Zero height, so it never affects layout.
    @ViewBuilder
    private var legacyProbe: some View {
        if #available(iOS 18.0, *) {
            EmptyView()
        } else {
            GeometryReader { geo in
                Color.clear.preference(key: TTCollapseLegacyKey.self, value: geo.frame(in: .scrollView).minY)
            }
            .frame(height: 0)
            .accessibilityHidden(true)
        }
    }
}

/// Header host: the only view (with the ears) that re-renders on each progress change.
private struct TTCollapsingHeaderHost<Header: View>: View {
    @ObservedObject var model: TTHeaderCollapseState
    let background: Color
    let topRadius: (CGFloat) -> CGFloat
    let header: (CGFloat) -> Header

    var body: some View {
        let radius = topRadius(model.progress)
        header(model.progress)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Concave corners under the header keep the content sheet's rounded top, at every progress.
            .overlay(alignment: .bottom) {
                TTHeaderEars(radius: radius, color: background)
                    .offset(y: radius)
                    .allowsHitTesting(false)
            }
    }
}

private struct TTHeaderEars: View {
    let radius: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            ear
            Spacer(minLength: 0)
            ear.scaleEffect(x: -1, y: 1)
        }
        .frame(height: radius)
        .accessibilityHidden(true)
    }

    private var ear: some View {
        color
            .frame(width: radius, height: radius)
            .mask {
                Rectangle()
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .frame(width: radius * 2, height: radius * 2)
                            .offset(x: radius, y: radius)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
    }
}

private struct TTCollapsingSheetBackground: View {
    @ObservedObject var model: TTHeaderCollapseState
    let fill: Color
    let topRadius: (CGFloat) -> CGFloat

    var body: some View {
        let r = topRadius(model.progress)
        UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: r, style: .continuous)
            .fill(fill)
            // Extends below the content so a short page (or a bounce) still shows a full sheet.
            .padding(.bottom, -3000)
    }
}

private struct TTCollapseObserver: ViewModifier {
    let model: TTHeaderCollapseState
    let travel: CGFloat
    let enabled: Bool
    let legacyMaxOffset: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: TTCollapseSignal.self) { geo in
                    // Small Equatable value only: clamped progress (1% steps) + whether collapse is possible.
                    let offset = geo.contentOffset.y + geo.contentInsets.top
                    let maxOffset = geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom - geo.containerSize.height
                    let span = TTHeaderCollapseState.collapseSpan(maxOffset: maxOffset, travel: travel)
                    let progress = span.map { min(1, max(0, offset / $0)) } ?? 0
                    return TTCollapseSignal(step: Int((progress * 100).rounded()), canCollapse: span != nil)
                } action: { _, new in
                    model.apply(step: new.step, enabled: enabled)
                }
                .onChange(of: travel) { _, _ in
                    model.update(offset: 0, maxOffset: 0, travel: travel, enabled: enabled)
                }
        } else {
            content
                .onPreferenceChange(TTCollapseLegacyKey.self) { minY in
                    model.updateLegacy(minY: minY, maxOffset: legacyMaxOffset, travel: travel, enabled: enabled)
                }
                .onChange(of: legacyMaxOffset) { _, newValue in
                    model.refreshLegacy(maxOffset: newValue, travel: travel, enabled: enabled)
                }
        }
    }
}

#Preview("Home Header") {
    VStack(spacing: 24) {
        TTHomeProfileHeader(
            name: "Maya",
            badgeCount: 2,
            metrics: [
                TTHomeProfileMetric(id: "h", icon: .plus, iconColor: TTColor.actionOrange, text: "86% Healthy"),
                TTHomeProfileMetric(id: "p", icon: .starFull, iconColor: .blue, text: "Pro")
            ],
            onProfileTap: {}
        )
        TTHomeProfileHeader(
            name: "Maya",
            avatarSymbol: nil,
            collapseProgress: 1,
            onProfileTap: {}
        )
    }
    .background(Color.black)
}
