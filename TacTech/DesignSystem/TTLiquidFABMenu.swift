import SwiftUI

// MARK: - Model

struct TTLiquidFABAction: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: SandowIcon
    /// Orange icon plate (AI / primary).
    var highlighted: Bool = false
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
            subtitle: "Chat · draft plans · cues",
            icon: .sparkle2,
            highlighted: true
        ),
        TTLiquidFABAction(
            id: "create",
            title: "Create workout plan",
            subtitle: "Build manually",
            icon: .clipboard
        ),
        TTLiquidFABAction(
            id: "assign",
            title: "Assign to trainee",
            subtitle: "Attach an existing plan",
            icon: .userCheck
        ),
        TTLiquidFABAction(
            id: "duplicate",
            title: "Duplicate plan",
            subtitle: "Copy and tweak",
            icon: .copy1
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
    @State private var expanded = false
    @State private var scrimVisible = false
    @State private var fabBoost = false
    @State private var liquidWave = false
    @State private var highlightedId: String?
    @State private var appearTick = 0

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
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                scrim

                ZStack(alignment: .bottom) {
                    liquidColumn
                        .allowsHitTesting(false)

                    VStack(spacing: 14) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            actionPill(action, index: index)
                        }

                        fabButton
                    }
                }
                .padding(.bottom, geo.safeAreaInsets.bottom + bottomReserve)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.8), trigger: appearTick)
        .sensoryFeedback(.selection, trigger: highlightedId)
        .onAppear { present() }
    }

    // MARK: - Present / dismiss

    private func present() {
        if reduceMotion {
            expanded = true
            scrimVisible = true
            appearTick += 1
            return
        }
        // Tiny kick so the FAB feels alive before pills pour out.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            fabBoost = true
        }
        withAnimation(openSpring.delay(0.04)) {
            expanded = true
            scrimVisible = true
            liquidWave = true
        }
        appearTick += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                // Keep a gentle liquid breathe while open.
                liquidWave = true
            }
        }
    }

    private func dismiss(completion: (() -> Void)? = nil) {
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
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.black.opacity(scrimVisible ? 0.22 : 0),
                        Color.black.opacity(scrimVisible ? 0.5 : 0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
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
                    .shadow(color: orange.opacity(expanded ? 0.55 : 0.4), radius: expanded ? 18 : 10, y: 8)
                    .scaleEffect(fabBoost && expanded ? 1.06 : 1)

                TTIcon(icon: .plus, filled: true, size: 20)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(expanded ? 45 : 0))
                    .scaleEffect(expanded ? 1.05 : 1)
            }
            .frame(width: fabSize, height: fabSize)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : openSpring, value: expanded)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: liquidWave)
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
                .blur(radius: 28)
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
            .blur(radius: expanded ? 16 : 4)
            .opacity(expanded ? 1 : 0)
            // High contrast after blur ≈ metaball / liquid merge.
            .contrast(expanded ? 1.35 : 1)
            .brightness(expanded ? 0.02 : 0)

            // Sharp highlight rim so liquid reads premium, not muddy.
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .frame(width: 22, height: expanded ? openHeight * 0.72 : 12)
                .blur(radius: 1)
                .opacity(expanded ? 0.7 : 0)
                .offset(y: -fabSize * 0.15)
        }
        .scaleEffect(x: breathe, y: 1, anchor: .bottom)
        .animation(reduceMotion ? .easeOut(duration: 0.14) : openSpring, value: expanded)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.55).repeatForever(autoreverses: true), value: liquidWave)
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
                    Circle()
                        .fill(action.highlighted ? orange : Color.black)
                        .shadow(
                            color: (action.highlighted ? orange : Color.black).opacity(0.25),
                            radius: 8,
                            y: 3
                        )
                    TTIcon(icon: action.icon, filled: true, size: 16)
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: expanded && action.highlighted)
                }
                .frame(width: 44, height: 44)
                .scaleEffect(expanded ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Text(action.subtitle)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                TTIcon(icon: .chevronRight, size: 12)
                    .foregroundStyle(TTColor.inkSubtle)
                    .opacity(expanded ? 0.7 : 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
            .frame(width: 308, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 22, y: 12)
                    .shadow(color: orange.opacity(action.highlighted ? 0.18 : 0), radius: 16, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        action.highlighted ? orange.opacity(0.45) : Color.white.opacity(0.8),
                        lineWidth: action.highlighted ? 1.4 : 0.5
                    )
            }
            .scaleEffect(isHot ? 0.96 : 1)
        }
        .buttonStyle(TTLiquidFABPillPressStyle())
        .opacity(expanded ? 1 : 0)
        .offset(y: expanded ? 0 : CGFloat(fromBottom + 1) * 28 + 48)
        .scaleEffect(expanded ? 1 : 0.42, anchor: .bottom)
        .rotation3DEffect(
            .degrees(expanded ? 0 : 18),
            axis: (x: 1, y: 0, z: 0),
            anchor: .bottom,
            perspective: 0.7
        )
        .blur(radius: expanded ? 0 : 6)
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
            .brightness(configuration.isPressed ? -0.02 : 0)
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
