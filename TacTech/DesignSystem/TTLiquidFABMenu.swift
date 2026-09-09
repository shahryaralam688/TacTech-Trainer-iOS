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

// MARK: - Overlay (rises from bottom center tab +)

/// Full-screen liquid action menu. Pills pour upward from the center tab FAB.
struct TTLiquidFABOverlay: View {
    @Binding var isPresented: Bool
    let actions: [TTLiquidFABAction]
    var onSelect: (TTLiquidFABAction) -> Void
    /// Space above home indicator so the morph sits on the tab cradle.
    var bottomReserve: CGFloat = TTFloatingTabBar<Int>.liquidMenuFABBottomReserve
    var namespace: Namespace.ID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var pulse = false
    @State private var scrimVisible = false

    private let orange = TTColor.actionOrange
    private let fabSize: CGFloat = TTFloatingTabBar<Int>.centerFABSize
    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.82)
    private let settle = Animation.spring(response: 0.34, dampingFraction: 0.9)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                scrim

                ZStack(alignment: .bottom) {
                    liquidBackbone
                        .allowsHitTesting(false)

                    VStack(spacing: 12) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            actionPill(action)
                                .opacity(expanded ? 1 : 0)
                                .offset(y: expanded ? 0 : emergeOffset(for: index))
                                .scaleEffect(expanded ? 1 : 0.35, anchor: .bottom)
                                .animation(
                                    reduceMotion
                                        ? .easeOut(duration: 0.14)
                                        : spring.delay(Double(actions.count - 1 - index) * 0.04),
                                    value: expanded
                                )
                        }

                        fabButton
                    }
                }
                .padding(.bottom, geo.safeAreaInsets.bottom + bottomReserve)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: expanded)
        .onAppear {
            pulse = true
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : spring) {
                expanded = true
                scrimVisible = true
            }
        }
    }

    // MARK: - Pieces

    private var scrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(scrimVisible ? 0.42 : 0))
            .ignoresSafeArea()
            .opacity(scrimVisible ? 1 : 0)
            .animation(settle, value: scrimVisible)
            .onTapGesture { dismiss() }
    }

    /// Exact cradle twin (56×56 orange squircle) so close morphs without a snap.
    private var fabButton: some View {
        Button {
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(orange.opacity(0.5))
                    .frame(width: fabSize + 16, height: fabSize + 16)
                    .blur(radius: 14)
                    .scaleEffect(pulse && expanded ? 1.16 : 0.95)
                    .opacity(expanded ? 1 : 0)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: pulse
                    )

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(expanded ? Color.black : orange)
                    .frame(width: fabSize, height: fabSize)
                    .shadow(color: orange.opacity(expanded ? 0.45 : 0.42), radius: expanded ? 14 : 10, y: 6)

                TTIcon(icon: .plus, filled: true, size: 20)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(expanded ? 45 : 0))
            }
            .frame(width: fabSize, height: fabSize)
        }
        .buttonStyle(.plain)
        .modifier(TTLiquidFABMatched(
            id: TTLiquidFABPortal.matchedID,
            namespace: namespace,
            isSource: true
        ))
        .accessibilityLabel("Close menu")
    }

    private var liquidBackbone: some View {
        let count = max(actions.count, 1)
        let openHeight: CGFloat = fabSize + CGFloat(count) * 74

        return ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(orange.opacity(0.92))
                .frame(width: 48, height: expanded ? openHeight : fabSize)
                .blur(radius: 24)
                .opacity(expanded ? 1 : 0)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [orange.opacity(0.7), orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: expanded ? openHeight - 16 : fabSize * 0.5)
                .blur(radius: 11)
                .opacity(expanded ? 0.95 : 0)

            VStack(spacing: 30) {
                ForEach(0..<count, id: \.self) { i in
                    let delayIndex = count - 1 - i
                    Circle()
                        .fill(orange.opacity(expanded ? 0.9 : 0))
                        .frame(width: expanded ? 40 : 8, height: expanded ? 40 : 8)
                        .blur(radius: 9)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.12)
                                : spring.delay(Double(delayIndex) * 0.04),
                            value: expanded
                        )
                }
            }
            .padding(.bottom, fabSize + 22)
        }
        .frame(width: 80, alignment: .bottom)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : spring, value: expanded)
    }

    private func actionPill(_ action: TTLiquidFABAction) -> some View {
        Button {
            select(action)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(action.highlighted ? orange : Color.black)
                    TTIcon(icon: action.icon, filled: true, size: 16)
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

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
            }
            .padding(.leading, 10)
            .padding(.trailing, 18)
            .padding(.vertical, 11)
            .frame(width: 300, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.14), radius: 20, y: 10)
            )
            .overlay {
                if action.highlighted {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(orange.opacity(0.4), lineWidth: 1.4)
                }
            }
        }
        .buttonStyle(TTLiquidFABPillPressStyle())
    }

    private func emergeOffset(for index: Int) -> CGFloat {
        let fromBottom = actions.count - 1 - index
        return CGFloat(fromBottom + 1) * 22 + 36
    }

    private func select(_ action: TTLiquidFABAction) {
        dismiss {
            onSelect(action)
        }
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        let collapse = reduceMotion ? Animation.easeOut(duration: 0.14) : settle
        // 1) Collapse pills + morph X → + while still covering the cradle.
        withAnimation(collapse) {
            expanded = false
            scrimVisible = false
        }
        // 2) Hand off to the tab-bar + in the same animated transaction (no snap).
        let handoff: TimeInterval = reduceMotion ? 0.12 : 0.28
        DispatchQueue.main.asyncAfter(deadline: .now() + handoff) {
            withAnimation(collapse) {
                isPresented = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                completion?()
            }
        }
    }
}

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
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
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
