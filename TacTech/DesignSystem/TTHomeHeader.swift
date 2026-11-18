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
    /// 0 = expanded. 1 = compact (avatar + name + chevron).
    var collapseProgress: CGFloat = 0
    var onProfileTap: (() -> Void)? = nil
    var onNotificationTap: (() -> Void)? = nil

    @State private var showPerfTemp = false // PERF-TEMP
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
        // Soft lift into compact — reads as chrome morph, not a hard cut.
        .shadow(
            color: .black.opacity(PerfTemp.on(.homeShadow) ? 0.18 * Double(p) : 0), // PERF-TEMP
            radius: PerfTemp.on(.homeShadow) ? 10 * p : 0, // PERF-TEMP
            y: PerfTemp.on(.homeShadow) ? 4 * p : 0 // PERF-TEMP
        )
        #if DEBUG || PERF_TEMP
        .sheet(isPresented: $showPerfTemp) { PerfTempSheet() } // PERF-TEMP
        #endif
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
            #if DEBUG || PERF_TEMP
            .onLongPressGesture(minimumDuration: 0.8) { showPerfTemp = true } // PERF-TEMP: opens the debug sheet
            #endif

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
                            .ttHomeBadgePop(active: badgeCount > 0)
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

                TTIcon(icon: .chevronRight, size: 22 - 2 * p)
                    .foregroundStyle(.white)
                    .layoutPriority(2)
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

// MARK: - Scroll → header collapse (reliable on cold launch)

/// Shared collapse progress for home / list / detail chrome.
///
/// Collapsing a header **above** a ScrollView shortens the scroll view’s frame;
/// UIKit then compensates `contentOffset`, which without correction fights the
/// header. We undo that layout delta with a fixed-point solve.
///
/// While dragging, progress tracks scroll. When the gesture ends, progress
/// **settles to 0 or 1** (never rests half-shrunk). A scroll baseline keeps
/// that settled state stable until the user scrolls again.
///
/// Scroll metrics are **coalesced to the next main-queue turn** so
/// `onScrollGeometryChange` never mutates layout in the same frame (avoids
/// “tried to update multiple times per frame”).
///
/// Short pages get an invisible bottom fill so overflow always covers a full
/// header collapse — scroll + animated shrink/expand work the same as tall
/// pages, and bottom content stays reachable (scroll is never locked off).
@MainActor
final class TTHomeScrollCollapseModel: ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    /// Kept for ScrollView wiring; always `true` so short pages stay reachable.
    @Published private(set) var allowsScrolling = true
    /// Extra scrollable space under short content so collapse can complete without fighting.
    @Published private(set) var bottomFillHeight: CGFloat = 0

    /// How many points the header chrome shrinks from expanded → compact.
    /// Matches `TTDarkPageHeader` / `trainerListHeader` travel by default.
    var layoutTravel: CGFloat = TTDarkPageHeader.cardHeight - TTDarkPageHeader.compactHeight

    /// Extra room past `layoutTravel` so post-shrink overflow stays positive.
    private static let collapseAffordSlack: CGFloat = 18

    private var lastProgress: CGFloat = 0
    private var lastRawY: CGFloat = 0
    /// Subtracted from raw offset so a settled 0/1 state stays put with residual offset.
    private var offsetBaseline: CGFloat = 0
    private var isUserScrolling = false
    /// Cumulative offset delta for the active gesture — used to prefer expand on scroll-down.
    private var gestureDeltaY: CGFloat = 0
    private var pendingCanScroll: Bool?
    /// Last endpoint we haptic’d — avoids double buzz on layout echo.
    private var lastHapticEndpoint: CGFloat?

    private var pendingOffset: CGFloat?
    private var pendingOverflow: CGFloat?
    private var flushScheduled = false
    /// Drop geometry echoes caused by our own header-height publish (same frame / next layout).
    private var suppressGeometryIngest = false
    private var lastIngestedOffset: CGFloat?
    private var lastIngestedOverflow: CGFloat?
    private var settleUnlockTask: Task<Void, Never>?
    private var settleDebounceTask: Task<Void, Never>?

    func setUserScrolling(_ active: Bool) {
        let wasScrolling = isUserScrolling
        isUserScrolling = active
        if active, !wasScrolling {
            gestureDeltaY = 0
        }
        // Commit overflow gating only when idle — flipping `scrollDisabled`
        // mid-deceleration hard-stops the rubber band and looks like a vibrate.
        if wasScrolling, !active {
            commitPendingScrollGate()
            // Final settle pass with the latest metrics after the fling ends.
            flushPendingMetricsIfNeeded()
            settleToEndpointIfNeeded()
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
        updateBottomFill(measuredOverflow: overflow)
        // Never lock scroll off — short content uses bottom fill instead, so the
        // user can always reach bottom rows and complete animated shrink/expand.
        pendingCanScroll = true
        if !isUserScrolling {
            commitPendingScrollGate()
        }
    }

    /// Keep enough scroll range under short content for a full collapse travel.
    private func updateBottomFill(measuredOverflow: CGFloat) {
        guard measuredOverflow.isFinite else {
            // iOS 17 path has no overflow metric — use a fixed collapse affordance.
            let target = (max(layoutTravel, TTHomeHeaderCollapse.distance) + Self.collapseAffordSlack).rounded()
            if abs(target - bottomFillHeight) >= 1 { bottomFillHeight = target }
            return
        }
        // Measured overflow already includes the current fill (contentMargins).
        let natural = measuredOverflow - bottomFillHeight
        // Overlay headers use layoutTravel = 0 but still need ~`distance` of scroll
        // to reach full collapse; frame-shrinking headers need the travel delta.
        let needed = max(layoutTravel, TTHomeHeaderCollapse.distance) + Self.collapseAffordSlack
        let target = max(0, (needed - max(0, natural)).rounded())
        guard abs(target - bottomFillHeight) >= 1 else { return }
        bottomFillHeight = target
    }

    func setOffsetY(_ y: CGFloat) {
        guard allowsScrolling else {
            offsetBaseline = 0
            apply(0)
            return
        }

        let rawY = max(0, y)
        let deltaRaw = rawY - lastRawY
        lastRawY = rawY
        if isUserScrolling {
            gestureDeltaY += deltaRaw
        } else if abs(deltaRaw) >= 2.0 {
            // iOS 17 has no phase API — treat clear offset moves as gesture intent.
            gestureDeltaY += deltaRaw
        }

        // Back at (or very near) the top — always fully expand.
        // Short pages often never accumulate enough raw offset for the
        // distance-based baseline to unwind on its own.
        if rawY <= TTHomeHeaderCollapse.leadIn {
            offsetBaseline = 0
            if lastProgress > 0.001 {
                apply(0, animated: !isUserScrolling)
            }
            if !isUserScrolling {
                scheduleDebouncedSettle()
            }
            return
        }

        let effectiveRaw = max(0, rawY - offsetBaseline)
        // Fixed-point: p == f(y + travel * p). Exact solve keeps UIKit’s offset
        // compensation and our header height in agreement every frame.
        var solved = lastProgress
        for _ in 0..<5 {
            let compensated = max(0, effectiveRaw + layoutTravel * solved)
            solved = TTHomeHeaderCollapse.progress(for: compensated)
        }
        let target = min(1, max(0, solved))

        // Ignore idle layout echo that only nudges collapse upward.
        if !isUserScrolling, target > lastProgress, (target - lastProgress) < 0.04, abs(deltaRaw) < 1.5 {
            return
        }

        // While settled, ignore tiny geometry drift — but allow a real scroll
        // delta through so short-page expand (scroll down) is not swallowed.
        if !isUserScrolling {
            let settled: CGFloat = lastProgress >= 0.5 ? 1 : 0
            if abs(lastProgress - settled) < 0.001, abs(deltaRaw) < 2.0 {
                return
            }
        }

        apply(target)
        // iOS 17 has no scroll-phase API — debounce settle when metrics go quiet.
        if !isUserScrolling {
            scheduleDebouncedSettle()
        }
    }

    /// After the gesture ends, never rest half-shrunk — ease to expanded or compact.
    private func settleToEndpointIfNeeded() {
        settleDebounceTask?.cancel()
        settleDebounceTask = nil
        guard allowsScrolling else {
            offsetBaseline = 0
            apply(0, animated: true)
            gestureDeltaY = 0
            return
        }

        // Near the top always expands — short pages may still report mid progress
        // because collapse travel never fit in raw offset.
        // Scroll toward top (negative delta) also prefers expand so reverse
        // shrink returns to the full header instead of snapping back compact.
        // Strong downward flick past mid commits compact even under threshold.
        let snap: CGFloat
        if lastRawY <= TTHomeHeaderCollapse.leadIn {
            snap = 0
        } else if gestureDeltaY <= -6 {
            snap = lastProgress >= 0.90 ? 1 : 0
        } else if gestureDeltaY >= 14, lastProgress >= 0.28 {
            snap = 1
        } else {
            snap = lastProgress >= TTHomeHeaderCollapse.settleThreshold ? 1 : 0
        }
        gestureDeltaY = 0
        guard abs(lastProgress - snap) > 0.02 else {
            // Already near an endpoint — lock baseline so residual offset doesn’t creep.
            lockBaseline(for: snap)
            if abs(lastProgress - snap) > 0.0005 {
                apply(snap, animated: true)
            }
            return
        }

        lockBaseline(for: snap)
        apply(snap, animated: true)
    }

    private func scheduleDebouncedSettle() {
        settleDebounceTask?.cancel()
        settleDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self, !Task.isCancelled, !self.isUserScrolling else { return }
            self.settleToEndpointIfNeeded()
        }
    }

    private func lockBaseline(for snap: CGFloat) {
        if snap < 0.5 {
            // Treat current offset as “expanded zero”.
            offsetBaseline = lastRawY
        } else {
            // Keep progress reading as fully compact at the current offset.
            // Clamp to ≥ 0 — on short pages lastRawY << distance; a negative
            // baseline makes top-of-scroll still look collapsed and blocks expand.
            offsetBaseline = max(0, lastRawY - TTHomeHeaderCollapse.distance)
        }
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
        guard allowsScrolling != next else { return }
        allowsScrolling = next
        if !next {
            offsetBaseline = 0
            apply(0)
        }
    }

    private func apply(_ stepped: CGFloat, animated: Bool = false) {
        guard abs(stepped - lastProgress) > 0.0005 || abs(progress - stepped) > 0.0005 else { return }
        let previous = lastProgress
        lastProgress = stepped
        suppressGeometryIngest = true
        settleUnlockTask?.cancel()

        if animated {
            withAnimation(TTHomeHeaderCollapse.settleAnimation) {
                progress = stepped
            }
            playSettleHapticIfNeeded(from: previous, to: stepped)
            settleUnlockTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(480))
                guard let self, !Task.isCancelled else { return }
                self.suppressGeometryIngest = false
                self.pendingOffset = nil
                self.pendingOverflow = nil
            }
        } else {
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

    private func playSettleHapticIfNeeded(from previous: CGFloat, to next: CGFloat) {
        let endpoint: CGFloat? =
            next <= 0.02 ? 0 :
            next >= 0.98 ? 1 :
            nil
        guard let endpoint else { return }
        // Only when we actually crossed into an endpoint (not echo re-apply).
        let crossed =
            (endpoint == 0 && previous > 0.08) ||
            (endpoint == 1 && previous < 0.92)
        guard crossed, lastHapticEndpoint != endpoint else { return }
        lastHapticEndpoint = endpoint
        TTHomeHaptics.soft()
    }
}

extension View {
    /// Put on the **ScrollView**. Pairs with `TTHomeScrollCollapseProbe` inside the content (iOS 17).
    /// Short pages receive an invisible bottom fill so collapse can complete without locking scroll.
    func ttObserveHomeScrollCollapse(
        _ model: TTHomeScrollCollapseModel,
        space: String,
        perfFile: String = #fileID, // PERF-TEMP
        perfLine: Int = #line // PERF-TEMP
    ) -> some View {
        modifier(TTHomeScrollCollapseObserver(model: model, space: space, perfFile: perfFile, perfLine: perfLine))
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
    let perfFile: String // PERF-TEMP
    let perfLine: Int // PERF-TEMP
    @State private var perfPrinted = false // PERF-TEMP
    @State private var allowsScrolling = true
    @State private var bottomFillHeight: CGFloat = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        let gated = content
            // Always rubber-band so short home pages still feel like a real gesture.
            .scrollBounceBehavior(.always)
            .scrollDisabled(!allowsScrolling)
            // Invisible pad under short content — enough travel for full shrink/expand.
            // contentMargins accumulate with tab-bar clearance margins on root screens.
            .contentMargins(.bottom, bottomFillHeight, for: .scrollContent)

        if #available(iOS 18.0, *) {
            gated
                .onScrollGeometryChange(for: TTHomeScrollCollapseMetrics.self) { geometry in
                    TTHomeScrollCollapseMetrics.sampled(
                        offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                        overflow: geometry.contentSize.height - geometry.containerSize.height
                    )
                } action: { _, newValue in
                    if !perfPrinted { perfPrinted = true; PerfTemp.scrollReaderFired("old-model " + perfFile, perfLine) } // PERF-TEMP
                    // Never mutate header layout synchronously here — that re-enters
                    // OnScrollGeometryChange / NavigationRequestObserver in-frame.
                    model.ingestScrollMetrics(offset: newValue.offset, overflow: newValue.overflow)
                }
                .onScrollPhaseChange { _, phase in
                    model.setUserScrolling(phase != .idle)
                }
                .onAppear {
                    allowsScrolling = model.allowsScrolling
                    bottomFillHeight = model.bottomFillHeight
                }
                .onReceive(model.$allowsScrolling) { allowsScrolling = $0 }
                .onReceive(model.$bottomFillHeight) { bottomFillHeight = $0 }
        } else {
            gated
                .coordinateSpace(name: space)
                .onPreferenceChange(TTHomeScrollOffsetPreferenceKey.self) { value in
                    if !perfPrinted { perfPrinted = true; PerfTemp.scrollReaderFired("old-model(iOS17) " + perfFile, perfLine) } // PERF-TEMP
                    model.ingestScrollMetrics(offset: value, overflow: .infinity)
                }
                .onAppear {
                    allowsScrolling = model.allowsScrolling
                    bottomFillHeight = model.bottomFillHeight
                }
                .onReceive(model.$allowsScrolling) { allowsScrolling = $0 }
                .onReceive(model.$bottomFillHeight) { bottomFillHeight = $0 }
        }
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

    /// `offset` is 0 at rest. `maxOffset` is the furthest the content can scroll.
    /// Collapse is decided from `maxOffset` vs. the travel `d`; both are independent of the header's
    /// current height (the content inset is constant), so there is no feedback loop.
    func update(offset: CGFloat, maxOffset: CGFloat, travel: CGFloat, enabled: Bool) {
        let canCollapse = enabled && travel > 1 && maxOffset >= travel
        let next = canCollapse ? min(1, max(0, offset / travel)) : 0
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
    private let perfFile: String // PERF-TEMP
    private let perfLine: Int // PERF-TEMP

    init(
        sheetFill: Color = .white,
        headerBackground: Color = .black,
        topRadius: @escaping (CGFloat) -> CGFloat = { TTSheetChrome.homeTopRadius(collapseProgress: $0) },
        pinsBelowCollapsedHeader: Bool = false,
        topAnchorID: String? = nil,
        onRefresh: (() async -> Void)? = nil,
        perfFile: String = #fileID, // PERF-TEMP: names the screen in the scroll-reader log
        perfLine: Int = #line, // PERF-TEMP
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
        self.perfFile = perfFile
        self.perfLine = perfLine
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
            if PerfTemp.on(.homeCopies) { // PERF-TEMP (OFF keeps the last measured heights)
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
            } // PERF-TEMP
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
            legacyMaxOffset: legacyMaxOffset, perfFile: perfFile, perfLine: perfLine
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
        #if DEBUG || PERF_TEMP
        let _ = PerfTemp.trace("HomeHeaderHost") { Self._printChanges() } // PERF-TEMP
        #endif
        let radius = topRadius(model.progress)
        header(model.progress)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // Concave corners under the header keep the content sheet's rounded top, at every progress.
            .overlay(alignment: .bottom) {
                if PerfTemp.on(.homeEars) { // PERF-TEMP
                TTHeaderEars(radius: radius, color: background)
                    .offset(y: radius)
                    .allowsHitTesting(false)
                } // PERF-TEMP
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
    let perfFile: String // PERF-TEMP
    let perfLine: Int // PERF-TEMP
    @State private var perfPrinted = false // PERF-TEMP

    @ViewBuilder
    func body(content: Content) -> some View {
        if !PerfTemp.on(.homeScrollObserver) { // PERF-TEMP: pinpoints the "update multiple times per frame" warning
            content
        } else if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: TTCollapseSignal.self) { geo in
                    // Small Equatable value only: clamped progress (1% steps) + whether collapse is possible.
                    let offset = geo.contentOffset.y + geo.contentInsets.top
                    let maxOffset = geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom - geo.containerSize.height
                    let canCollapse = travel > 1 && maxOffset >= travel
                    let progress = canCollapse ? min(1, max(0, offset / travel)) : 0
                    return TTCollapseSignal(step: Int((progress * 100).rounded()), canCollapse: canCollapse)
                } action: { _, new in
                    if !perfPrinted { perfPrinted = true; PerfTemp.scrollReaderFired("new-container " + perfFile, perfLine) } // PERF-TEMP
                    model.apply(step: new.step, enabled: enabled)
                }
                .onChange(of: travel) { _, _ in
                    model.update(offset: 0, maxOffset: 0, travel: travel, enabled: enabled)
                }
        } else {
            content
                .onPreferenceChange(TTCollapseLegacyKey.self) { minY in
                    if !perfPrinted { perfPrinted = true; PerfTemp.scrollReaderFired("new-container(iOS17) " + perfFile, perfLine) } // PERF-TEMP
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
