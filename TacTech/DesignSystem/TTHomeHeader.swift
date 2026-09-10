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
    static let distance: CGFloat = 168

    /// Approximate height delta of `TTHomeProfileHeader` expanded → compact.
    /// Must match real layout travel or ScrollView offset compensation fights and vibrates.
    static let homeLayoutTravel: CGFloat = 102

    /// Linear map — smootherstep lagged the finger and fought layout compensation on flings.
    static func progress(for offset: CGFloat) -> CGFloat {
        min(1, max(0, offset / distance))
    }
}

/// Home top bar — scroll-synced collapse to avatar + name + forward.
struct TTHomeProfileHeader: View {
    let name: String
    var avatarSymbol: String? = nil
    var avatarUserId: String? = nil
    var avatarInitial: String? = nil
    var badgeCount: Int = 0
    var metrics: [TTHomeProfileMetric] = []
    var date: Date = .now
    /// 0 = expanded. 1 = compact (avatar + name + chevron).
    var collapseProgress: CGFloat = 0
    var onProfileTap: (() -> Void)? = nil
    var onNotificationTap: (() -> Void)? = nil

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let dateGrey = Color.white.opacity(0.55)
    private let bellBG = Color(white: 0.22)

    private var p: CGFloat { min(1, max(0, collapseProgress)) }
    private var expand: CGFloat { 1 - p }

    private var avatarSide: CGFloat { 58 - 18 * p } // 58 → 40
    private var avatarRadius: CGFloat { 16 - 4 * p } // 16 → 12
    private var titleSize: CGFloat { 28 - 8 * p } // 28 → 20
    private var rowSpacing: CGFloat { 14 - 2 * p }

    var body: some View {
        VStack(alignment: .leading, spacing: 22 * expand) {
            topRow
                .opacity(Double(expand))
                // Extra height so the notification badge isn’t clipped at rest.
                .frame(height: 54 * expand, alignment: .top)
                .clipped()
                .allowsHitTesting(p < 0.35)

            profileRow
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
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        // No spring on `p` — collapse must track scroll 1:1 (esp. expand on scroll-down).
    }

    // MARK: - Rows

    private var topRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                TTIcon(icon: .calendar1, size: 14)
                Text(formattedDate)
                    .font(TTFont.textSM(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(dateGrey)

            Spacer()

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
                    }
                }
                // Keep badge inside the hit target so parent `.clipped()` can’t crop it.
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
            .buttonStyle(TTHomeHeaderPressStyle())
        }
    }

    private var profileRow: some View {
        Button {
            onProfileTap?()
        } label: {
            HStack(spacing: rowSpacing) {
                avatarView(side: avatarSide, corner: avatarRadius)

                VStack(alignment: .leading, spacing: 7 * expand) {
                    Text(p < 0.55 ? "Hello, \(name)!" : name)
                        .font(TTFont.workSans(titleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

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
                                        .font(TTFont.textMD(.medium))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .opacity(Double(expand))
                        .frame(height: 22 * expand, alignment: .top)
                        .clipped()
                    }
                }

                Spacer(minLength: 0)

                TTIcon(icon: .chevronRight, size: 22 - 2 * p)
                    .foregroundStyle(.white)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TTHomeHeaderPressStyle())
        .accessibilityLabel("Open profile, \(name)")
        .accessibilityHint("Opens your profile")
    }

    private func avatarView(side: CGFloat, corner: CGFloat) -> some View {
        Group {
            if TTAvatarCatalog.isCustom(avatarSymbol),
               let custom = TTAvatarCatalog.loadCustomImage(for: avatarUserId) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if let avatarSymbol, TTAvatarCatalog.isAssetName(avatarSymbol) {
                Image(avatarSymbol)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    if let avatarSymbol, !TTAvatarCatalog.hasRenderableAvatar(avatarSymbol) {
                        Image(systemName: avatarSymbol)
                            .font(TTFont.workSans(side * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text((avatarInitial ?? String(name.prefix(1))).uppercased())
                            .font(TTFont.workSans(side * 0.36, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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

// MARK: - Scroll → header collapse (reliable on cold launch)

/// Shared collapse progress for home / list / detail chrome.
///
/// Collapsing a header **above** a ScrollView shortens the scroll view’s frame;
/// UIKit then compensates `contentOffset`, which without correction fights the
/// header. We undo that layout delta with a fixed-point solve.
///
/// Progress is applied **1:1 with no animation**. Spring/blend lag leaves the
/// header still resizing after a fling settles — that feedback loop is the
/// end-of-scroll “vibrate”.
///
/// Scroll metrics are **coalesced to the next main-queue turn** so
/// `onScrollGeometryChange` never mutates layout in the same frame (avoids
/// “tried to update multiple times per frame”).
///
/// Short content: scrolling / bounce is disabled (so the header never fights
/// rubber-band). Tall content: scrolling stays on and collapse stays interactive.
@MainActor
final class TTHomeScrollCollapseModel: ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    /// `false` when content fits the viewport — ScrollView should not move.
    @Published private(set) var allowsScrolling = true

    /// How many points the header chrome shrinks from expanded → compact.
    /// Matches `TTDarkPageHeader` / `trainerListHeader` travel by default.
    var layoutTravel: CGFloat = TTDarkPageHeader.cardHeight - TTDarkPageHeader.compactHeight

    private var lastProgress: CGFloat = 0
    private var lastRawY: CGFloat = 0
    private var isUserScrolling = false
    private var pendingCanScroll: Bool?

    private var pendingOffset: CGFloat?
    private var pendingOverflow: CGFloat?
    private var flushScheduled = false
    /// Drop geometry echoes caused by our own header-height publish (same frame / next layout).
    private var suppressGeometryIngest = false
    private var lastIngestedOffset: CGFloat?
    private var lastIngestedOverflow: CGFloat?

    func setUserScrolling(_ active: Bool) {
        let wasScrolling = isUserScrolling
        isUserScrolling = active
        // Commit overflow gating only when idle — flipping `scrollDisabled`
        // mid-deceleration hard-stops the rubber band and looks like a vibrate.
        if wasScrolling, !active {
            commitPendingScrollGate()
            // Final settle pass with the latest metrics after the fling ends.
            flushPendingMetricsIfNeeded()
        }
    }

    /// Safe entry from `onScrollGeometryChange` / preference probes.
    /// Stores the latest sample and applies it once outside the geometry pass.
    func ingestScrollMetrics(offset: CGFloat, overflow: CGFloat) {
        if suppressGeometryIngest {
            // Keep latest sample but do not schedule — avoids same-frame re-entry warning.
            pendingOffset = offset
            pendingOverflow = overflow
            return
        }
        if lastIngestedOffset == offset, lastIngestedOverflow == overflow {
            return
        }
        lastIngestedOffset = offset
        lastIngestedOverflow = overflow
        pendingOffset = offset
        pendingOverflow = overflow
        scheduleFlush()
    }

    func setScrollableOverflow(_ overflow: CGFloat) {
        // Hysteresis: avoid toggling when contentSize ≈ container during bounce.
        let next: Bool
        if allowsScrolling {
            next = overflow > 0.5
        } else {
            next = overflow > 8
        }
        pendingCanScroll = next
        if !isUserScrolling {
            commitPendingScrollGate()
        }
    }

    func setOffsetY(_ y: CGFloat) {
        guard allowsScrolling else {
            apply(0)
            return
        }

        let rawY = max(0, y)
        // Fixed-point: p == f(y + travel * p). Exact solve keeps UIKit’s offset
        // compensation and our header height in agreement every frame.
        var solved = lastProgress
        for _ in 0..<5 {
            let compensated = max(0, rawY + layoutTravel * solved)
            solved = TTHomeHeaderCollapse.progress(for: compensated)
        }
        let target = min(1, max(0, solved))
        let deltaRaw = rawY - lastRawY
        lastRawY = rawY

        // Ignore idle layout echo that only nudges collapse upward.
        if !isUserScrolling, target > lastProgress, (target - lastProgress) < 0.04, abs(deltaRaw) < 1.5 {
            return
        }

        apply(target)
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.flushPendingMetricsIfNeeded()
        }
    }

    private func flushPendingMetricsIfNeeded() {
        let overflow = pendingOverflow
        let offset = pendingOffset
        pendingOverflow = nil
        pendingOffset = nil
        if let overflow {
            setScrollableOverflow(overflow)
        }
        if let offset {
            setOffsetY(offset)
        }
    }

    private func commitPendingScrollGate() {
        guard let next = pendingCanScroll else { return }
        pendingCanScroll = nil
        guard allowsScrolling != next else {
            if !next { apply(0) }
            return
        }
        allowsScrolling = next
        if !next { apply(0) }
    }

    private func apply(_ stepped: CGFloat) {
        guard abs(stepped - lastProgress) > 0.0005 || abs(progress - stepped) > 0.0005 else { return }
        lastProgress = stepped
        suppressGeometryIngest = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            progress = stepped
        }
        // Clear suppress after layout; discard echo samples from our own height change.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.suppressGeometryIngest = false
            self.pendingOffset = nil
            self.pendingOverflow = nil
        }
    }
}

extension View {
    /// Put on the **ScrollView**. Pairs with `TTHomeScrollCollapseProbe` inside the content (iOS 17).
    /// Also gates bounce/scroll when content fits the screen.
    func ttObserveHomeScrollCollapse(
        _ model: TTHomeScrollCollapseModel,
        space: String
    ) -> some View {
        modifier(TTHomeScrollCollapseObserver(model: model, space: space))
    }
}

/// **Must** be the first child inside the ScrollView content (fallback / cold launch on iOS 17).
struct TTHomeScrollCollapseProbe: View {
    let model: TTHomeScrollCollapseModel
    let space: String

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TTHomeScrollOffsetPreferenceKey.self,
                value: max(0, -geo.frame(in: .named(space)).minY)
            )
        }
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
    }
}

private struct TTHomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TTHomeScrollCollapseMetrics: Equatable {
    var offset: CGFloat
    var overflow: CGFloat

    /// Snap to 1pt so float / layout echo doesn’t re-enter geometry observation.
    static func sampled(offset: CGFloat, overflow: CGFloat) -> Self {
        Self(
            offset: offset.rounded(),
            overflow: overflow.rounded()
        )
    }
}

/// One measurement path only — dual PreferenceKey + geometry observers fought and jittered.
///
/// Intentionally **not** `@ObservedObject`: progress publishes every scroll tick;
/// observing here would rebuild the ScrollView and re-enter geometry / navigation
/// observers in the same frame.
private struct TTHomeScrollCollapseObserver: ViewModifier {
    let model: TTHomeScrollCollapseModel
    let space: String
    @State private var allowsScrolling = true

    @ViewBuilder
    func body(content: Content) -> some View {
        let gated = content
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(!allowsScrolling)

        if #available(iOS 18.0, *) {
            gated
                .onScrollGeometryChange(for: TTHomeScrollCollapseMetrics.self) { geometry in
                    TTHomeScrollCollapseMetrics.sampled(
                        offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                        overflow: geometry.contentSize.height - geometry.containerSize.height
                    )
                } action: { _, newValue in
                    // Never mutate header layout synchronously here — that re-enters
                    // OnScrollGeometryChange / NavigationRequestObserver in-frame.
                    model.ingestScrollMetrics(offset: newValue.offset, overflow: newValue.overflow)
                }
                .onScrollPhaseChange { _, phase in
                    model.setUserScrolling(phase != .idle)
                }
                .onAppear { allowsScrolling = model.allowsScrolling }
                .onReceive(model.$allowsScrolling) { allowsScrolling = $0 }
        } else {
            gated
                .coordinateSpace(name: space)
                .onPreferenceChange(TTHomeScrollOffsetPreferenceKey.self) { value in
                    model.ingestScrollMetrics(offset: value, overflow: .infinity)
                }
                .onAppear { allowsScrolling = model.allowsScrolling }
                .onReceive(model.$allowsScrolling) { allowsScrolling = $0 }
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
