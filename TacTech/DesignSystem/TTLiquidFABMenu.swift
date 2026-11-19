import SwiftUI
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Model

struct TTLiquidFABAction: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: SandowIcon
    /// Orange icon plate (AI / primary).
    var highlighted: Bool = false
    /// Starts a new visual group (adds extra space above this row). Layout only.
    var startsGroup: Bool = false
}

extension Notification.Name {
    /// Opens the trainer/trainee AI coach overlay from anywhere in the tab root.
    static let ttOpenAICoachChat = Notification.Name("ttOpenAICoachChat")
}

enum TTLiquidFABPortal {
    static let matchedID = "tactech.liquid.centerFAB"
}

extension TTLiquidFABAction {
    /// Trainer center-tab quick actions.
    static let trainerCenterMenu: [TTLiquidFABAction] = [
        TTLiquidFABAction(
            id: "ai",
            title: "AI Assistant",
            subtitle: "Draft plans, get ideas",
            icon: .sparkle2,
            highlighted: true
        ),
        TTLiquidFABAction(
            id: "traineeChat",
            title: "Trainee chat",
            subtitle: "Message or call a trainee",
            icon: .chat
        ),
        TTLiquidFABAction(
            id: "create",
            title: "Create workout plan",
            subtitle: "Build one from scratch",
            icon: .filePlus,
            startsGroup: true
        ),
        TTLiquidFABAction(
            id: "assign",
            title: "Assign to trainee",
            subtitle: "Give a trainee a plan",
            icon: .userCheck
        ),
        TTLiquidFABAction(
            id: "assignments",
            title: "Plan assignments",
            subtitle: "See who has which plan",
            icon: .listThreeCheck
        )
    ]

    /// Trainee center-tab quick actions — limited to things the tabs don't already cover.
    static let traineeCenterMenu: [TTLiquidFABAction] = [
        TTLiquidFABAction(
            id: "ai",
            title: "Ask AI coach",
            subtitle: "Form · nutrition · cues",
            icon: .sparkle2,
            highlighted: true
        ),
        TTLiquidFABAction(
            id: "logMeal",
            title: "Log a meal",
            subtitle: "Scan or add food",
            icon: .forkKnife
        ),
        TTLiquidFABAction(
            id: "quickWorkout",
            title: "Quick workout",
            subtitle: "Start training now",
            icon: .barbellDiagonal
        )
    ]
}

// MARK: - Overlay (liquid rise from center tab +)

/// Full-screen liquid action menu — gooey backbone, staggered pill pour, morphing FAB.
struct TTLiquidFABOverlay: View {
    @Binding var isPresented: Bool
    let actions: [TTLiquidFABAction]
    var onSelect: (TTLiquidFABAction) -> Void
    var bottomReserve: CGFloat = TTFloatingTabBar<Int>.liquidMenuFABBottomReserve
    var namespace: Namespace.ID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    /// False once the menu starts closing (or the app leaves the foreground): the breathing loops stop at once,
    /// not only when the overlay is finally removed.
    @State private var loopsActive = true
    @State private var dismissing = false
    @State private var expanded = false
    @State private var scrimVisible = false
    @State private var fabBoost = false
    @State private var liquidWave = false
    @State private var highlightedId: String?
    /// When opening started (system uptime). Taps on the scrim / close button before `earlyTapGrace` has passed are ignored.
    @State private var openStartedAt = ProcessInfo.processInfo.systemUptime

    /// Why: the close button sits exactly where the "+" was. A quick second tap on "+" lands on it (or on the scrim)
    /// and would close the menu that is just opening. Ignoring taps this long after opening starts prevents that.
    private static let earlyTapGrace: TimeInterval = 0.35

    /// Scrim / close-button taps count only after the grace period and while no close is running.
    private func dismissFromTap() {
        guard !dismissing,
              ProcessInfo.processInfo.systemUptime - openStartedAt >= Self.earlyTapGrace else { return }
        dismiss()
    }

    private let orange = TTColor.actionOrange
    private let fabSize: CGFloat = TTFloatingTabBar<Int>.centerFABSize

    /// Open — soft overshoot so pills “pop” out of the liquid.
    private var openSpring: Animation {
        .spring(response: 0.55, dampingFraction: 0.72, blendDuration: 0.15)
    }
    /// Close — tighter so handoff to cradle + stays clean.
    private var closeSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.92)
    }
    private var pillSpring: Animation {
        .spring(response: 0.5, dampingFraction: 0.68, blendDuration: 0.12)
    }

    var body: some View {
        #if DEBUG || PERF_TEMP
        let _ = PerfTemp.trace("LiquidFABOverlay") { Self._printChanges() } // PERF-TEMP
        #endif
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                scrim

                ZStack(alignment: .bottom) {
                    liquidColumn
                        .allowsHitTesting(false)

                    VStack(spacing: 10) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            actionPill(action, index: index)
                                // 10pt inside a group, 22pt between groups (10 + 12).
                                .padding(.top, action.startsGroup && index > 0 ? 12 : 0)
                        }

                        fabButton
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, geo.safeAreaInsets.bottom + bottomReserve)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: highlightedId)
        // Nothing keeps animating while the app is in the background.
        .onChange(of: scenePhase) { _, phase in
            guard !dismissing else { return }
            if phase == .active {
                loopsActive = true
                if expanded { withAnimation(.easeOut(duration: 0.2)) { liquidWave = true } }
            } else {
                loopsActive = false
                withAnimation(.easeOut(duration: 0.2)) { liquidWave = false }
            }
        }
        .onAppear { present() }
    }

    // MARK: - Present / dismiss

    private func present() {
        #if DEBUG || PERF_TEMP
        PlusTapProbe.shared.opened() // PERF-TEMP
        #endif
        openStartedAt = ProcessInfo.processInfo.systemUptime
        if reduceMotion {
            expanded = true
            scrimVisible = true
            return
        }
        // Tiny kick so the FAB feels alive before pills pour out.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            fabBoost = true
        }
        PerfTemp.interval("fab.open", seconds: 0.7) // PERF-TEMP
        withAnimation(openSpring.delay(0.04)) {
            expanded = true
            scrimVisible = true
            liquidWave = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard loopsActive, PerfTemp.on(.fabLoops) else { return } // PERF-TEMP
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                // Keep a gentle liquid breathe while open.
                liquidWave = true
            }
        }
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        guard !dismissing else { return } // a close is already running: no second haptic or animation
        dismissing = true
        loopsActive = false
        PerfTemp.interval("fab.close", seconds: 0.45) // PERF-TEMP
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        let collapse = reduceMotion ? Animation.easeOut(duration: 0.14) : closeSpring
        withAnimation(collapse) {
            expanded = false
            scrimVisible = false
            fabBoost = false
            liquidWave = false
            highlightedId = nil
        }
        let handoff: TimeInterval = reduceMotion ? 0.1 : 0.26
        DispatchQueue.main.asyncAfter(deadline: .now() + handoff) {
            withAnimation(collapse) {
                isPresented = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                completion?()
            }
        }
    }

    private func select(_ action: TTLiquidFABAction) {
        guard !dismissing else { return }
        highlightedId = action.id
        dismiss {
            onSelect(action)
        }
    }

    // MARK: - Scrim

    private var scrim: some View {
        Rectangle()
            .fill(reduceTransparency ? AnyShapeStyle(Color.black) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(
                // Dark scrim; solid-ish when Reduce Transparency is on (no blur then).
                Color.black.opacity(scrimVisible ? (reduceTransparency ? 0.92 : 0.58) : 0)
            )
            .ignoresSafeArea()
            .opacity(scrimVisible ? 1 : 0)
            .animation(closeSpring, value: scrimVisible)
            .onTapGesture { dismissFromTap() }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            dismissFromTap()
        } label: {
            ZStack {
                // Breathing orange bloom (only while open).
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [orange.opacity(0.55), orange.opacity(0)],
                            center: .center,
                            startRadius: 8,
                            endRadius: 42
                        )
                    )
                    .frame(width: 88, height: 88)
                    .scaleEffect(expanded ? (liquidWave ? 1.18 : 1.05) : 0.7)
                    .opacity(expanded ? 1 : 0)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(expanded ? Color.black : orange)
                    .frame(width: fabSize, height: fabSize)
                    .shadow(color: Color.black.opacity(expanded ? 0.4 : 0.28), radius: expanded ? 11 : 6, y: 8)
                    .scaleEffect(fabBoost && expanded ? 1.06 : 1)

                TTIcon(icon: .plus, filled: true, size: 20)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(expanded ? 45 : 0))
                    .scaleEffect(expanded ? 1.05 : 1)
            }
            .frame(width: fabSize, height: fabSize)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : openSpring, value: expanded)
            .animation(reduceMotion || !PerfTemp.on(.fabLoops) ? nil : (loopsActive ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .easeOut(duration: 0.2)), value: liquidWave) // PERF-TEMP
        }
        .buttonStyle(.plain)
        .modifier(TTLiquidFABMatched(
            id: TTLiquidFABPortal.matchedID,
            namespace: namespace,
            isSource: true
        ))
        .accessibilityLabel("Close menu")
    }

    // MARK: - Liquid column (gooey)

    private var liquidColumn: some View {
        let count = max(actions.count, 1)
        let openHeight: CGFloat = fabSize + 20 + CGFloat(count) * 76
        let breathe: CGFloat = liquidWave && expanded ? 1.06 : 1

        return ZStack(alignment: .bottom) {
            // Soft outer glow
            Capsule(style: .continuous)
                .fill(orange.opacity(0.35))
                .frame(width: 64 * breathe, height: expanded ? openHeight + 24 : fabSize)
                .blur(radius: PerfTemp.on(.fabBlur) ? 28 : 0) // PERF-TEMP
                .opacity(expanded ? 1 : 0)

            // Gooey stack — blur + contrast merges blobs into liquid.
            ZStack(alignment: .bottom) {
                Capsule(style: .continuous)
                    .fill(orange)
                    .frame(width: 36, height: expanded ? openHeight : fabSize * 0.6)

                ForEach(0..<count, id: \.self) { i in
                    let fromBottom = count - 1 - i
                    Circle()
                        .fill(orange)
                        .frame(width: expanded ? 44 : 10, height: expanded ? 44 : 10)
                        .offset(y: expanded ? -CGFloat(fromBottom + 1) * 72 : 0)
                        .scaleEffect(expanded ? (liquidWave && i % 2 == 0 ? 1.08 : 1) : 0.2)
                }

                // FAB node
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(orange)
                    .frame(width: fabSize * 0.85, height: fabSize * 0.85)
            }
            .frame(width: 90, height: expanded ? openHeight + 40 : fabSize)
            .blur(radius: PerfTemp.on(.fabBlur) ? (expanded ? 16 : 4) : 0) // PERF-TEMP
            .opacity(expanded ? 1 : 0)
            // High contrast after blur ≈ metaball / liquid merge.
            .contrast(PerfTemp.on(.fabBlur) && expanded ? 1.35 : 1) // PERF-TEMP
            .brightness(PerfTemp.on(.fabBlur) && expanded ? 0.02 : 0) // PERF-TEMP

            // Sharp highlight rim so liquid reads premium, not muddy.
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .frame(width: 22, height: expanded ? openHeight * 0.72 : 12)
                .blur(radius: PerfTemp.on(.fabBlur) ? 1 : 0) // PERF-TEMP
                .opacity(expanded ? 0.7 : 0)
                .offset(y: -fabSize * 0.15)
        }
        .scaleEffect(x: breathe, y: 1, anchor: .bottom)
        .animation(reduceMotion ? .easeOut(duration: 0.14) : openSpring, value: expanded)
        .animation(reduceMotion || !PerfTemp.on(.fabLoops) ? nil : (loopsActive ? .easeInOut(duration: 1.55).repeatForever(autoreverses: true) : .easeOut(duration: 0.2)), value: liquidWave) // PERF-TEMP
    }

    // MARK: - Pills

    private func actionPill(_ action: TTLiquidFABAction, index: Int) -> some View {
        let fromBottom = actions.count - 1 - index
        let delay = Double(fromBottom) * 0.055
        let isHot = highlightedId == action.id

        return Button {
            select(action)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(action.highlighted ? orange : Color.black)
                    TTIcon(icon: action.icon, filled: false, size: 24)
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: expanded && action.highlighted)
                }
                .frame(width: 52, height: 52)
                .scaleEffect(expanded ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(action.title))
                        .font(TTFont.workSans(17, weight: .medium))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Text(LocalizedStringKey(action.subtitle))
                        .font(TTFont.workSans(14, weight: .regular))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .frame(width: 308, height: 76, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(TTColor.surface)
                    .shadow(color: Color.black.opacity(0.18), radius: 13, y: 10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(TTColor.ink.opacity(0.06), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .scaleEffect(isHot ? 0.96 : 1)
        }
        .buttonStyle(TTLiquidFABPillPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(String(localized: String.LocalizationValue(action.title))), \(String(localized: String.LocalizationValue(action.subtitle)))"
        )
        .accessibilityAddTraits(.isButton)
        .opacity(expanded ? 1 : 0)
        .offset(y: expanded ? 0 : CGFloat(fromBottom + 1) * 28 + 48)
        .scaleEffect(expanded ? 1 : 0.42, anchor: .bottom)
        .rotation3DEffect(
            .degrees(expanded ? 0 : 18),
            axis: (x: 1, y: 0, z: 0),
            anchor: .bottom,
            perspective: 0.7
        )
        .blur(radius: PerfTemp.on(.fabBlur) ? (expanded ? 0 : 6) : 0) // PERF-TEMP
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : pillSpring.delay(delay),
            value: expanded
        )
        .animation(.easeOut(duration: 0.12), value: isHot)
    }
}

// MARK: - Helpers

private struct TTLiquidFABMatched: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    var isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}

private struct TTLiquidFABPillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview("Liquid FAB · Center") {
    ZStack {
        Color(white: 0.92).ignoresSafeArea()
        TTLiquidFABOverlay(
            isPresented: .constant(true),
            actions: TTLiquidFABAction.trainerCenterMenu,
            onSelect: { _ in }
        )
    }
}


// MARK: - Bubble menu (new presentation: liquid bubbles in an arc above the original rounded-square button)
//
// Drawing layer: ONE Canvas (`TTBubbleCanvas`) draws the scrim, glow, necks, bubbles, icons and labels. The button
// itself is the ORIGINAL rounded square (`TTCenterSquareFace`, the same view the tab bar uses), drawn above the Canvas
// at exactly the bar button's frame. No blur, no material, no contrast filter, no repeating animation.
//
// Isolation: ALL menu state (open / closed, per-frame values) lives in `TTBubbleEngine`, a small @Observable object.
// The root screen only holds it (never reads it in a body), so opening or closing the menu re-runs no root, Home or
// tab-bar body. Who observes it (and what):
//   - TTBubbleCanvas renderer ........ `frame`, `presented`   (redraw per animation frame)
//   - TTBubbleBaseView body .......... `frame`, `presented`   (the "+" -> "x" turn, press scale, show / hide)
//   - TTBubbleVisibility modifier .... `presented`            (hit testing, accessibility)
//   - TTBubbleCenterButton (tab bar) . `presented`            (hides the bar's button while the menu is open)

/// Shared numbers and drawing helpers.
enum TTBubbleArt {
    static let buttonRadius: CGFloat = 28 // inscribed circle of the 56pt square: the necks' anchor
    static let bubbleRadius: CGFloat = 27
    static let arcRadius: CGFloat = 104
    static let glowRadius: CGFloat = 86
    /// "+" grows by this much (14%) when the menu is fully open; position never changes.
    static func openGrow(_ master: Double) -> CGFloat {
        1 + 0.14 * CGFloat(min(max(master, 0), 1))
    }
    /// Counter-clockwise from +x, screen y up: AI upper left, Chat straight up, Workout Plan upper right.
    static let anglesDegrees: [Double] = [155, 90, 25]

    /// Same orange as the button fill, so the necks and bubbles are one colour with it.
    static let brand: Color = TTColor.actionOrange
    /// Built once (not per frame).
    static let glowGradient = Gradient(colors: [TTColor.actionOrange.opacity(0.55), TTColor.actionOrange.opacity(0)])
    static let fill = GraphicsContext.Shading.color(TTColor.actionOrange)
    /// Cos / sin of the bubble angles, computed once.
    static let directions: [(cos: CGFloat, sin: CGFloat)] = anglesDegrees.map {
        (CGFloat(cos($0 * .pi / 180)), CGFloat(sin($0 * .pi / 180)))
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// Bubble radius while moving: starts small (inside the button) and grows to 27.
    static func bubbleRadius(progress p: Double) -> CGFloat {
        bubbleRadius * CGFloat(0.3 + 0.7 * clamp(p, 0, 1.15))
    }

    static func bubbleCenter(c: CGPoint, index: Int, p: Double) -> CGPoint {
        let d = directions[min(max(index, 0), directions.count - 1)]
        return CGPoint(x: c.x + d.cos * arcRadius * CGFloat(p), y: c.y - d.sin * arcRadius * CGFloat(p))
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// Pre-made radial glow (a gradient, not a blur).
    static func drawGlow(_ ctx: GraphicsContext, c: CGPoint, opacity: Double) {
        var g = ctx
        g.opacity = opacity
        g.fill(circle(c, glowRadius),
               with: .radialGradient(glowGradient, center: c, startRadius: 0, endRadius: glowRadius))
    }

    /// Analytic metaball bridge between two circles. `v` is the pinch factor (0 = no neck).
    static func neckPath(c1: CGPoint, r1: CGFloat, c2: CGPoint, r2: CGFloat, v: Double) -> Path? {
        let r1 = Double(r1), r2 = Double(r2)
        let dx = Double(c2.x - c1.x), dy = Double(c2.y - c1.y)
        let d = hypot(dx, dy)
        guard r1 > 0, r2 > 0, v > 0.001, d > abs(r1 - r2) + 0.5 else { return nil }

        var u1 = 0.0, u2 = 0.0
        if d < r1 + r2 {
            u1 = acos(clamp((r1 * r1 + d * d - r2 * r2) / (2 * r1 * d), -1, 1))
            u2 = acos(clamp((r2 * r2 + d * d - r1 * r1) / (2 * r2 * d), -1, 1))
        }
        let a1 = atan2(dy, dx)
        let a2 = acos(clamp((r1 - r2) / d, -1, 1))
        let a1a = a1 + u1 + (a2 - u1) * v
        let a1b = a1 - u1 - (a2 - u1) * v
        let a2a = a1 + .pi - u2 - (.pi - u2 - a2) * v
        let a2b = a1 - .pi + u2 + (.pi - u2 - a2) * v

        func pt(_ c: CGPoint, _ r: Double, _ a: Double) -> CGPoint {
            CGPoint(x: Double(c.x) + r * cos(a), y: Double(c.y) + r * sin(a))
        }
        let p1a = pt(c1, r1, a1a), p1b = pt(c1, r1, a1b)
        let p2a = pt(c2, r2, a2a), p2b = pt(c2, r2, a2b)

        let total = r1 + r2
        var d2 = min(v * 2.4, hypot(Double(p1a.x - p2a.x), Double(p1a.y - p2a.y)) / total)
        d2 *= min(1, 2 * d / total)
        let h1 = r1 * d2, h2 = r2 * d2

        func off(_ p: CGPoint, _ h: Double, _ a: Double) -> CGPoint {
            CGPoint(x: Double(p.x) + h * cos(a), y: Double(p.y) + h * sin(a))
        }
        var path = Path()
        path.move(to: p1a)
        path.addCurve(to: p2a, control1: off(p1a, h1, a1a - .pi / 2), control2: off(p2a, h2, a2a + .pi / 2))
        path.addLine(to: p2b)
        path.addCurve(to: p1b, control1: off(p2b, h2, a2b - .pi / 2), control2: off(p1b, h1, a1b + .pi / 2))
        path.closeSubpath()
        return path
    }
}

/// All state of the bubble menu. Values are evaluated in CLOSED FORM from the time elapsed since each motion's own
/// start (damped spring, mass 1), using one clock (the display link's frame time), so a late frame lands on the
/// right point of the curve instead of changing the velocity. The display link exists only while something moves.
@MainActor @Observable
final class TTBubbleEngine {
    enum Phase { case closed, opening, open, closing }

    /// Speed of the open / close motion. 1.0 = prototype speed; 2.0 = twice as slow.
    /// Spring time = elapsed / scale; every stagger delay and the scrim fade are multiplied by it.
    /// Reduce Motion is not affected.
    static let openMotionScale = 2.0
    static let closeMotionScale = 2.0

    /// One damped-spring motion towards `target`, started at `start` (wall-clock) from `x0` with velocity `v0`
    /// (per wall-clock second). `scale` stretches time.
    struct Segment {
        var start: CFTimeInterval = 0
        var x0 = 0.0, v0 = 0.0, target = 0.0
        var k = 220.0, c = 17.0, scale = 1.0

        func eval(at now: CFTimeInterval) -> (x: Double, v: Double) {
            let t = max(0, now - start) / scale
            let y0 = x0 - target
            let vt0 = v0 * scale // velocity in spring time
            let w0 = k.squareRoot()
            let z = c / (2 * w0)
            let a = z * w0
            var y: Double, vy: Double
            if z < 1 - 1e-6 {
                let wd = w0 * (1 - z * z).squareRoot()
                let e = exp(-a * t), cs = cos(wd * t), sn = sin(wd * t)
                let b = (vt0 + a * y0) / wd
                y = e * (y0 * cs + b * sn)
                vy = e * ((b * wd - a * y0) * cs - (a * b + y0 * wd) * sn)
            } else if z < 1 + 1e-6 {
                let d = vt0 + w0 * y0
                let e = exp(-w0 * t)
                y = (y0 + d * t) * e
                vy = e * (vt0 - w0 * d * t)
            } else {
                let s = w0 * (z * z - 1).squareRoot()
                let r1 = -a + s, r2 = -a - s
                let ca = (vt0 - r2 * y0) / (r1 - r2)
                let cb = y0 - ca
                let e1 = exp(r1 * t), e2 = exp(r2 * t)
                y = ca * e1 + cb * e2
                vy = ca * r1 * e1 + cb * r2 * e2
            }
            return (target + y, vy / scale)
        }
    }

    /// The running motion, plus at most one that starts later (stagger delay).
    struct Spring {
        var cur = Segment()
        var next: Segment?

        init(x: Double, target: Double, k: Double, c: Double) {
            cur = Segment(start: 0, x0: x, v0: 0, target: target, k: k, c: c, scale: 1)
        }

        /// New motion from the CURRENT position and velocity (no jump when re-triggered mid-motion).
        mutating func command(target: Double, k: Double, c: Double, scale: Double, delay: Double, now: CFTimeInterval) {
            advance(now)
            let start = now + delay
            let from = cur.eval(at: start)
            let seg = Segment(start: start, x0: from.x, v0: from.v, target: target, k: k, c: c, scale: scale)
            if delay <= 0 { cur = seg; next = nil } else { next = seg }
        }

        mutating func advance(_ now: CFTimeInterval) {
            if let n = next, now >= n.start { cur = n; next = nil }
        }

        mutating func value(at now: CFTimeInterval) -> (x: Double, v: Double) {
            advance(now)
            return cur.eval(at: now)
        }

        mutating func settled(at now: CFTimeInterval) -> Bool {
            let s = value(at: now)
            return next == nil && abs(s.x - cur.target) < 0.0008 && abs(s.v) < 0.02
        }

        mutating func snap(at now: CFTimeInterval) {
            next = nil
            cur = Segment(start: now, x0: cur.target, v0: 0, target: cur.target, k: cur.k, c: cur.c, scale: cur.scale)
        }
    }

    struct Tween {
        var from = 0.0, to = 0.0, start: CFTimeInterval = 0, duration = 0.0
        func value(at now: CFTimeInterval) -> Double {
            guard duration > 0 else { return to }
            let t = min(1, max(0, (now - start) / duration))
            let e = 1 - (1 - t) * (1 - t) // ease-out
            return from + (to - from) * e
        }
        func done(at now: CFTimeInterval) -> Bool { duration <= 0 || now - start >= duration }
    }

    // Observed (small, rarely changing or once per frame; read only by the views listed above).
    /// Once per animation frame.
    var frame = 0
    /// True from the moment the menu starts opening until the close has finished.
    var presented = false
    /// Real on-screen centre of the bar's "+" (global coordinates), measured by the bar button itself.
    /// The menu draws its "+" exactly here, so there is no second, separately calculated position.
    var buttonCenter: CGPoint?

    // Everything else is plain stored state (not observed).
    @ObservationIgnored private(set) var phase: Phase = .closed
    @ObservationIgnored private var bubbleSprings = [Spring](repeating: Spring(x: 0, target: 0, k: 220, c: 17), count: 3)
    @ObservationIgnored private var masterSpring = Spring(x: 0, target: 0, k: 300, c: 26)
    @ObservationIgnored private var pressSpring = Spring(x: 1, target: 1, k: 520, c: 36)
    /// Values evaluated once per tick; the drawing views only read these.
    @ObservationIgnored private(set) var bubbleX: [Double] = [0, 0, 0]
    @ObservationIgnored private(set) var masterX = 0.0
    @ObservationIgnored private(set) var pressX = 1.0
    @ObservationIgnored private(set) var scrim = 0.0
    @ObservationIgnored private(set) var fade = 1.0
    @ObservationIgnored private var scrimTween = Tween()
    @ObservationIgnored private var fadeTween = Tween(from: 1, to: 1)
    @ObservationIgnored private var reduceClosing = false
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var linkTarget: LinkTarget?
    /// System uptime when the last open started (for the early-tap grace).
    @ObservationIgnored private(set) var openStartedAt = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored var pendingSelect: TTLiquidFABAction?
    @ObservationIgnored var onClosed: (() -> Void)?
    @ObservationIgnored var onOpened: (() -> Void)?

    private final class LinkTarget: NSObject {
        var handler: ((CADisplayLink) -> Void)?
        @objc func tick(_ link: CADisplayLink) { handler?(link) }
    }

    var isDriverRunning: Bool { link != nil } // PERF-TEMP

    /// PERF-TEMP: progress values and positions for the log.
    func debugSnapshot(center c: CGPoint) -> String {
        let parts = bubbleX.indices.map { i -> String in
            let p = bubbleX[i]
            let pos = TTBubbleArt.bubbleCenter(c: c, index: i, p: p)
            return "b\(i) p=\(String(format: "%.3f", p)) pos=(\(Int(pos.x)),\(Int(pos.y)))" + (p < 0.01 ? " NOT-DRAWN(p<0.01)" : "")
        }
        #if DEBUG || PERF_TEMP
        let counts = "bodyRuns=\(PerfBubbleLog.bodyRuns) "
        #else
        let counts = ""
        #endif
        return counts + "phase=\(phase) driver=\(isDriverRunning ? "on" : "off") master=\(String(format: "%.3f", masterX)) " + parts.joined(separator: " ")
    }

    // MARK: Commands

    func open() {
        guard phase != .opening, phase != .open else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let now = CACurrentMediaTime()
        let fromRest = phase == .closed
        let scale = Self.openMotionScale
        phase = .opening
        reduceClosing = false
        openStartedAt = ProcessInfo.processInfo.systemUptime
        #if DEBUG || PERF_TEMP
        PerfBubbleRecorder.begin("open", master: masterX) // PERF-TEMP
        PlusTapProbe.shared.opened() // PERF-TEMP
        #endif
        PerfTemp.interval("fab.open", seconds: 0.7 * scale) // PERF-TEMP
        scrimTween = Tween(from: scrim, to: 1, start: now, duration: reduceMotion ? 0.15 : 0.26 * scale)
        if reduceMotion {
            // No springs, no stagger, no necks: final state at once, short fade.
            for i in bubbleSprings.indices {
                bubbleSprings[i].command(target: 1, k: 220, c: 17, scale: 1, delay: 0, now: now)
                bubbleSprings[i].snap(at: now)
            }
            masterSpring.command(target: 1, k: 300, c: 26, scale: 1, delay: 0, now: now)
            masterSpring.snap(at: now)
            fadeTween = Tween(from: 0, to: 1, start: now, duration: 0.15)
        } else {
            fadeTween = Tween(from: 1, to: 1)
            let delays: [Double] = fromRest ? [0, 0.05 * scale, 0.10 * scale] : [0, 0, 0]
            for i in bubbleSprings.indices {
                bubbleSprings[i].command(target: 1, k: 220, c: 17, scale: scale, delay: delays[i], now: now)
            }
            masterSpring.command(target: 1, k: 300, c: 26, scale: scale, delay: 0, now: now)
        }
        evaluate(at: now)
        presented = true // observed: hides the bar's button, shows the overlay (same frame)
        frame &+= 1
        startLink()
        onOpened?()
        #if DEBUG || PERF_TEMP
        PerfBubbleLog.present(driver: isDriverRunning, phase: "\(phase)", reduceMotion: reduceMotion, isPresented: presented, barButton: buttonCenter) // PERF-TEMP
        let c = PerfBubbleLog.center
        PerfBubbleLog.scheduleSnapshots { [weak self] in self?.debugSnapshot(center: c) ?? "" } // PERF-TEMP
        #endif
    }

    func close() {
        guard phase != .closing, phase != .closed else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let now = CACurrentMediaTime()
        let fromRest = phase == .open
        let scale = Self.closeMotionScale
        phase = .closing
        #if DEBUG || PERF_TEMP
        PerfBubbleRecorder.begin("close", master: masterX) // PERF-TEMP
        #endif
        scrimTween = Tween(from: scrim, to: 0, start: now, duration: reduceMotion ? 0.15 : 0.24 * scale)
        if reduceMotion {
            fadeTween = Tween(from: fade, to: 0, start: now, duration: 0.15)
            reduceClosing = true
        } else {
            let delays: [Double] = fromRest ? [0.044 * scale, 0.022 * scale, 0] : [0, 0, 0]
            for i in bubbleSprings.indices {
                bubbleSprings[i].command(target: 0, k: 480, c: 44, scale: scale, delay: delays[i], now: now)
            }
            masterSpring.command(target: 0, k: 520, c: 46, scale: scale, delay: 0, now: now)
        }
        startLink()
    }

    /// Touch-down on the base: it scales to 0.92 at once; back to 1 on release or cancel.
    func setPressed(_ pressed: Bool) {
        pressSpring.command(target: pressed ? 0.92 : 1, k: 520, c: 36, scale: 1, delay: 0, now: CACurrentMediaTime())
        startLink()
    }

    // MARK: Driver

    private func startLink() {
        guard link == nil else { return }
        let target = LinkTarget()
        target.handler = { [weak self] link in
            MainActor.assumeIsolated { self?.tick(link) }
        }
        let link = CADisplayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
        // Native display rate (up to 120 Hz).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        linkTarget = target
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        linkTarget = nil
    }

    /// Evaluates every value once, at one point in time.
    private func evaluate(at now: CFTimeInterval) {
        for i in 0..<3 { bubbleX[i] = bubbleSprings[i].value(at: now).x }
        masterX = masterSpring.value(at: now).x
        pressX = pressSpring.value(at: now).x
        scrim = scrimTween.value(at: now)
        fade = fadeTween.value(at: now)
    }

    private func tick(_ link: CADisplayLink) {
        #if DEBUG || PERF_TEMP
        let began = CACurrentMediaTime() // PERF-TEMP
        #endif
        // One clock for everything: the time this frame will be shown.
        let now = link.targetTimestamp
        if reduceClosing, fadeTween.done(at: now) {
            for i in bubbleSprings.indices { bubbleSprings[i].snap(at: now) }
            masterSpring.snap(at: now)
            reduceClosing = false
        }
        evaluate(at: now)
        frame &+= 1

        var moving = !(scrimTween.done(at: now) && fadeTween.done(at: now)) || reduceClosing
        if !moving {
            for i in 0..<3 where !bubbleSprings[i].settled(at: now) { moving = true; break }
            if !moving, !masterSpring.settled(at: now) || !pressSpring.settled(at: now) { moving = true }
        }
        #if DEBUG || PERF_TEMP
        PerfBubbleRecorder.tick(timestamp: link.timestamp, tickMs: (CACurrentMediaTime() - began) * 1000) // PERF-TEMP
        #endif
        if !moving { settle(now) }
    }

    private func settle(_ now: CFTimeInterval) {
        for i in bubbleSprings.indices { bubbleSprings[i].snap(at: now) }
        masterSpring.snap(at: now)
        pressSpring.snap(at: now)
        evaluate(at: now)
        stopLink()
        let wasClosing = phase == .closing
        phase = wasClosing ? .closed : .open
        #if DEBUG || PERF_TEMP
        PerfBubbleRecorder.end() // PERF-TEMP
        #endif
        if wasClosing { presented = false } // observed: bar button back, overlay out of hit testing
        frame &+= 1
        if wasClosing { onClosed?() }
    }
}

private extension TTLiquidFABAction {
    /// Short visible label above the bubble.
    var bubbleLabel: LocalizedStringKey {
        switch id {
        case "ai": return "AI"
        case "traineeChat": return "Chat"
        default: return "Workout Plan"
        }
    }
}

/// Reports touch-down / release of the base so the engine can scale it at once.
private struct TTBubbleBasePressStyle: ButtonStyle {
    let onPress: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
    }
}

/// Hit testing and accessibility follow `presented`; the content is not re-evaluated.
private struct TTBubbleVisibility: ViewModifier {
    let engine: TTBubbleEngine

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(engine.presented)
            .accessibilityHidden(!engine.presented)
    }
}

/// The original rounded-square button, mounted once above the Canvas at the bar button's exact frame. It is visible
/// only while the menu is presented, and turns "+" into "x". Besides the Canvas renderer it is the only view that
/// reads `engine.frame`.
private struct TTBubbleBaseView: View {
    let engine: TTBubbleEngine

    var body: some View {
        let _ = engine.frame
        TTCenterSquareFace(glyphDegrees: 45 * TTBubbleArt.clamp(engine.masterX, 0, 1.1))
            // Stays exactly where the bar's "+" is; it only grows a little while the menu is open.
            .scaleEffect(CGFloat(engine.pressX) * TTBubbleArt.openGrow(engine.masterX))
            .opacity(engine.presented ? 1 : 0)
    }
}

/// The single drawing layer. Its body runs only when its inputs change; per animation frame only the renderer runs.
private struct TTBubbleCanvas: View {
    let engine: TTBubbleEngine
    let center: CGPoint
    let bubbles: [TTLiquidFABAction]

    var body: some View {
        #if DEBUG || PERF_TEMP
        let _ = { PerfBubbleLog.bodyRuns += 1 }() // PERF-TEMP
        #endif
        Canvas { ctx, size in
            render(&ctx, size: size)
        } symbols: {
            // Explicit symbols (no ForEach): ForEach element ids collide across groups and crash Canvas.
            // Built when the Canvas body runs (not per frame); the renderer only looks them up.
            symbolIcon(0).tag(0)
            symbolIcon(1).tag(1)
            symbolIcon(2).tag(2)
            symbolLabel(0).tag(10)
            symbolLabel(1).tag(11)
            symbolLabel(2).tag(12)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func symbolIcon(_ i: Int) -> some View {
        if bubbles.indices.contains(i) {
            TTIcon(icon: bubbles[i].icon, filled: false, size: 22).foregroundStyle(.white)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    @ViewBuilder
    private func symbolLabel(_ i: Int) -> some View {
        if bubbles.indices.contains(i) {
            Text(bubbles[i].bubbleLabel)
                .font(TTFont.workSans(13, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize()
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func render(_ ctx: inout GraphicsContext, size: CGSize) {
        #if DEBUG || PERF_TEMP
        let began = PerfBubbleRecorder.renderBegan() // PERF-TEMP
        defer { PerfBubbleRecorder.renderEnded(began: began, master: engine.masterX) } // PERF-TEMP
        #endif
        // The animated values live in an @ObservationIgnored class, so the Canvas has no input that changes.
        // Reading `frame` and `presented` HERE (inside the renderer) makes SwiftUI redraw the Canvas on every bump,
        // without re-running any view body. (Without this the Canvas draws once and stays on its first frame.)
        _ = engine.frame
        let presented = engine.presented

        guard presented || engine.phase != .closed else {
            // Hidden: resolve the symbols once off-screen so the first open does no icon / text work.
            for id in 0..<bubbles.count {
                for tag in [id, 10 + id] {
                    if let sym = ctx.resolveSymbol(id: tag) { ctx.draw(sym, at: CGPoint(x: -4000, y: -4000)) }
                }
            }
            return
        }

        let c = center
        let layer = engine.fade
        let mm = TTBubbleArt.clamp(engine.masterX, 0, 1)
        let r1 = TTBubbleArt.buttonRadius * CGFloat(engine.pressX) * TTBubbleArt.openGrow(engine.masterX) // inscribed circle of the rounded square

        // Scrim: flat black 45%.
        if engine.scrim > 0.001 {
            ctx.fill(Path(CGRect(x: -2, y: -2, width: size.width + 4, height: size.height + 4)),
                     with: .color(.black.opacity(0.45 * engine.scrim)))
        }

        // Glow: 0 when closed (the bar button has none), up to 65% when open.
        TTBubbleArt.drawGlow(ctx, c: c, opacity: 0.65 * mm)

        var layered = ctx
        layered.opacity = layer
        let count = min(bubbles.count, 3)

        // Necks first (anchored on the inscribed circle; the rounded square is drawn on top by the base view).
        for i in 0..<count {
            let p = engine.bubbleX[i]
            guard p >= 0.01 else { continue }
            let pos = TTBubbleArt.bubbleCenter(c: c, index: i, p: p)
            let r2 = TTBubbleArt.bubbleRadius(progress: p)
            let d = Double(hypot(pos.x - c.x, pos.y - c.y))
            let gap = d - Double(r1 + r2)
            let sm = TTBubbleArt.smoothstep(TTBubbleArt.clamp((gap + 10) / 44, 0, 1))
            if let neck = TTBubbleArt.neckPath(c1: c, r1: r1, c2: pos, r2: r2, v: 0.5 * (1 - sm)) {
                layered.fill(neck, with: TTBubbleArt.fill)
            }
        }
        for i in 0..<count {
            let p = engine.bubbleX[i]
            guard p >= 0.01 else { continue }
            layered.fill(TTBubbleArt.circle(TTBubbleArt.bubbleCenter(c: c, index: i, p: p),
                                            TTBubbleArt.bubbleRadius(progress: p)), with: TTBubbleArt.fill)
        }

        // Icons and labels.
        for i in 0..<count {
            let p = engine.bubbleX[i]
            guard p >= 0.01 else { continue }
            let pos = TTBubbleArt.bubbleCenter(c: c, index: i, p: p)
            let s = TTBubbleArt.clamp((p - 0.2) / 0.6, 0, 1)
            let io = TTBubbleArt.clamp((p - 0.35) / 0.4, 0, 1)
            if s > 0, io > 0, let sym = ctx.resolveSymbol(id: i) {
                var g = ctx
                g.opacity = io * layer
                g.translateBy(x: pos.x, y: pos.y)
                g.scaleBy(x: CGFloat(s), y: CGFloat(s))
                g.draw(sym, at: .zero)
            }
            let lo = TTBubbleArt.clamp((p - 0.75) / 0.25, 0, 1)
            if lo > 0, let sym = ctx.resolveSymbol(id: 10 + i) {
                var g = ctx
                g.opacity = lo * layer
                g.draw(sym, at: CGPoint(x: pos.x, y: pos.y - TTBubbleArt.bubbleRadius(progress: p) - 10), anchor: .bottom)
            }
        }
    }
}

#if canImport(UIKit)
/// Prepared selection haptic (the same `.selection` feedback as before), fired AFTER the close has started.
private final class TTBubbleSelectionHaptic {
    private let generator = UISelectionFeedbackGenerator()
    func prepare() { generator.prepare() }
    func fire() { generator.selectionChanged(); generator.prepare() }
}
#endif

/// Liquid-bubble quick-actions menu: AI, Chat, Workout Plan. Mounted once (never inserted or removed), draws nothing
/// while closed, and holds no state that changes during open / close.
struct TTBubbleMenuOverlay: View {
    let engine: TTBubbleEngine
    let actions: [TTLiquidFABAction]
    var onSelect: (TTLiquidFABAction) -> Void
    var bottomReserve: CGFloat = TTFloatingTabBar<Int>.liquidMenuFABBottomReserve

    @AccessibilityFocusState private var focusedBubble: Int?
    #if canImport(UIKit)
    @State private var haptic = TTCenterHaptic()
    @State private var selectionHaptic = TTBubbleSelectionHaptic()
    #endif

    /// Why: the base sits exactly where the "+" was. A quick second tap on "+" lands on it (or on the scrim)
    /// and would close the menu that is just opening. Taps this soon after opening starts are ignored.
    private static let earlyTapGrace: TimeInterval = 0.35

    /// Only these three actions are shown; Assign to trainee and Plan assignments keep their handlers
    /// (TrainerRootView.handleLiquidAction) but are not in this menu.
    private static let shownIds = ["ai", "traineeChat", "create"]

    private var bubbles: [TTLiquidFABAction] {
        Self.shownIds.compactMap { id in actions.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geo in
            // Same frame source as the old overlay: FAB bottom edge = safe-area bottom + bottomReserve above the screen bottom.
            let bottomOffset = geo.safeAreaInsets.bottom + bottomReserve
            GeometryReader { full in
                let calculated = CGPoint(x: full.size.width / 2,
                                         y: full.size.height - bottomOffset - TTBubbleArt.buttonRadius)
                let c = engine.buttonCenter ?? calculated
                #if DEBUG || PERF_TEMP
                let _ = { PerfBubbleLog.canvasSize = full.size; PerfBubbleLog.center = c }() // PERF-TEMP
                #endif
                ZStack {
                    TTBubbleCanvas(engine: engine, center: c, bubbles: bubbles)
                        .allowsHitTesting(false)
                    TTBubbleBaseView(engine: engine)
                        .position(c)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    hitLayers(center: c)
                }
            }
            .ignoresSafeArea()
        }
        .modifier(TTBubbleVisibility(engine: engine))
        .onAppear {
            engine.onClosed = { finishClose() }
            engine.onOpened = {
                #if canImport(UIKit)
                if UIAccessibility.isVoiceOverRunning {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focusedBubble = 0 }
                }
                #endif
            }
            #if canImport(UIKit)
            haptic.prepare()
            selectionHaptic.prepare()
            #endif
            #if DEBUG || PERF_TEMP
            // PERF-TEMP: launch with `-perfTempOpenBubbles` to open the menu 6 s after launch (no tap automation here).
            if PerfBubbleLog.autoOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { engine.open() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 11) { engine.close() } // PERF-TEMP: one close to record
                DispatchQueue.main.asyncAfter(deadline: .now() + 16) { engine.open() } // PERF-TEMP: and a re-open
            }
            #endif
        }
    }

    // MARK: Hit layers (real buttons; nothing here changes per frame)

    @ViewBuilder
    private func hitLayers(center c: CGPoint) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { dismissFromTap() }
            .accessibilityHidden(true)

        ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, action in
            Button {
                select(action, index: index)
            } label: {
                Color.clear
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(TTBubbleArt.bubbleCenter(c: c, index: index, p: 1))
            .accessibilityLabel(String(localized: String.LocalizationValue(action.title)))
            .accessibilityAddTraits(.isButton)
            .accessibilitySortPriority(Double(bubbles.count - index))
            .accessibilityFocused($focusedBubble, equals: index)
        }

        // Base: same hit area as the bar button (64 x 72: +12 up, +4 down), so a quick second tap lands here.
        Button {
            baseTapped()
        } label: {
            Color.clear
                .frame(width: 64, height: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(TTBubbleBasePressStyle { engine.setPressed($0) })
        .position(x: c.x, y: c.y - 4)
        .accessibilityLabel("Close menu")
        .accessibilitySortPriority(0)
    }

    // MARK: Close

    private func beginClose(then action: TTLiquidFABAction?) {
        guard engine.phase == .opening || engine.phase == .open else { return } // a close is already running
        engine.pendingSelect = action
        PerfTemp.interval("fab.close", seconds: 0.45 * TTBubbleEngine.closeMotionScale) // PERF-TEMP
        engine.close() // the motion starts first ...
        #if canImport(UIKit)
        haptic.fire() // ... then the haptics
        if action != nil { selectionHaptic.fire() }
        #endif
    }

    /// Scrim tap: ignored during the early-tap grace and while a close is running.
    private func dismissFromTap() {
        guard ProcessInfo.processInfo.systemUptime - engine.openStartedAt >= Self.earlyTapGrace else { return }
        beginClose(then: nil)
    }

    /// Base tap: same grace; while closing it re-opens at once, never ignored because an animation runs.
    private func baseTapped() {
        guard ProcessInfo.processInfo.systemUptime - engine.openStartedAt >= Self.earlyTapGrace else { return }
        if engine.phase == .closing {
            engine.pendingSelect = nil
            engine.open()
        } else {
            beginClose(then: nil)
        }
    }

    private func select(_ action: TTLiquidFABAction, index: Int) {
        // Only a bubble that is really out can be chosen, and not while a close is running.
        guard engine.phase == .opening || engine.phase == .open, engine.bubbleX[index] > 0.4 else { return }
        beginClose(then: action)
    }

    /// The close finished (the engine already stopped its driver and hid itself): run the chosen action.
    /// No view is removed and no root state is flipped here.
    private func finishClose() {
        guard let action = engine.pendingSelect else { return }
        engine.pendingSelect = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { onSelect(action) }
    }
}
