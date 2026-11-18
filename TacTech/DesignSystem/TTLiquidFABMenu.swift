import SwiftUI
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
            .onTapGesture { dismiss() }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            dismiss()
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
