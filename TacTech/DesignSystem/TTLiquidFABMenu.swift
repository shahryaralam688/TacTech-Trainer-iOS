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

// MARK: - Overlay (reference: bottom-trailing liquid FAB → options rise out)

/// Full-screen liquid action menu. Pills pour upward from the black FAB with a
/// gooey orange backbone — matches `docs/references/tactech-liquid-fab-reference.png`.
struct TTLiquidFABOverlay: View {
    @Binding var isPresented: Bool
    let actions: [TTLiquidFABAction]
    var onSelect: (TTLiquidFABAction) -> Void
    /// Clears space above the home-indicator / tab cradle.
    var bottomReserve: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var pulse = false

    private let orange = TTColor.actionOrange
    private let spring = Animation.spring(response: 0.52, dampingFraction: 0.76)
    private let settle = Animation.spring(response: 0.36, dampingFraction: 0.88)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                scrim

                ZStack(alignment: .bottomTrailing) {
                    liquidBackbone
                        .allowsHitTesting(false)
                        .offset(x: -10, y: -4)

                    VStack(alignment: .trailing, spacing: 12) {
                        // Top → bottom: AI … Duplicate, then FAB (reference order).
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            actionPill(action)
                                .opacity(expanded ? 1 : 0)
                                .offset(y: expanded ? 0 : emergeOffset(for: index))
                                .scaleEffect(expanded ? 1 : 0.35, anchor: .bottomTrailing)
                                .animation(
                                    reduceMotion
                                        ? .easeOut(duration: 0.16)
                                        : spring.delay(Double(actions.count - 1 - index) * 0.05),
                                    value: expanded
                                )
                        }

                        fabButton
                    }
                }
                .padding(.trailing, 18)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 8) + bottomReserve)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: expanded)
        .onAppear {
            pulse = true
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : spring) {
                expanded = true
            }
        }
    }

    // MARK: - Pieces

    private var scrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(expanded ? 0.42 : 0))
            .ignoresSafeArea()
            .opacity(expanded ? 1 : 0)
            .animation(settle, value: expanded)
            .onTapGesture { dismiss() }
    }

    private var fabButton: some View {
        Button {
            dismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(orange.opacity(0.6))
                    .frame(width: 72, height: 72)
                    .blur(radius: 16)
                    .scaleEffect(pulse && expanded ? 1.22 : 0.92)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: pulse
                    )

                Circle()
                    .fill(Color.black)
                    .frame(width: 58, height: 58)
                    .shadow(color: orange.opacity(0.5), radius: 18, y: 8)

                TTIcon(icon: .plus, filled: true, size: 22)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(expanded ? 45 : 0))
                    .animation(spring, value: expanded)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close menu")
    }

    private var liquidBackbone: some View {
        let count = max(actions.count, 1)
        let openHeight: CGFloat = 70 + CGFloat(count) * 74

        return ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(orange.opacity(0.92))
                .frame(width: 48, height: expanded ? openHeight : 48)
                .blur(radius: 24)
                .opacity(expanded ? 1 : 0.25)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [orange.opacity(0.7), orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 30, height: expanded ? openHeight - 16 : 30)
                .blur(radius: 11)
                .opacity(expanded ? 0.95 : 0.3)

            VStack(spacing: 30) {
                ForEach(0..<count, id: \.self) { i in
                    let delayIndex = count - 1 - i
                    Circle()
                        .fill(orange.opacity(expanded ? 0.9 : 0.15))
                        .frame(width: expanded ? 40 : 10, height: expanded ? 40 : 10)
                        .blur(radius: 9)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.14)
                                : spring.delay(Double(delayIndex) * 0.05),
                            value: expanded
                        )
                }
            }
            .padding(.bottom, 78)
        }
        .frame(width: 80, alignment: .bottom)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : spring, value: expanded)
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
            .frame(width: 278, alignment: .leading)
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

    /// Collapse toward the FAB (downward) so open feels like rising out of it.
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
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : settle) {
            expanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.1 : 0.3)) {
            isPresented = false
            completion?()
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

#Preview("Liquid FAB") {
    ZStack {
        Color(white: 0.92).ignoresSafeArea()
        TTLiquidFABOverlay(
            isPresented: .constant(true),
            actions: [
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
                    id: "dup",
                    title: "Duplicate plan",
                    subtitle: "Copy and tweak",
                    icon: .copy1
                )
            ],
            onSelect: { _ in }
        )
    }
}
