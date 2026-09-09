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

// MARK: - Overlay (options emerge from the + with liquid morph)

/// Full-screen liquid action menu. Options spring out of the trailing FAB with a
/// gooey orange backbone — designed to match the TacTech liquid FAB reference.
struct TTLiquidFABOverlay: View {
    @Binding var isPresented: Bool
    let actions: [TTLiquidFABAction]
    var onSelect: (TTLiquidFABAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var pulse = false

    private let orange = TTColor.actionOrange
    private let spring = Animation.spring(response: 0.48, dampingFraction: 0.78)
    private let settle = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                scrim

                VStack(alignment: .trailing, spacing: 0) {
                    Color.clear.frame(height: geo.safeAreaInsets.top + 10)

                    ZStack(alignment: .topTrailing) {
                        liquidBackbone
                            .allowsHitTesting(false)

                        VStack(alignment: .trailing, spacing: 12) {
                            fabButton

                            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                                actionPill(action)
                                    .opacity(expanded ? 1 : 0)
                                    .offset(y: expanded ? 0 : emergeOffset(for: index))
                                    .scaleEffect(expanded ? 1 : 0.42, anchor: .topTrailing)
                                    .rotation3DEffect(
                                        .degrees(expanded ? 0 : 12),
                                        axis: (x: 1, y: 0, z: 0),
                                        anchor: .top,
                                        perspective: 0.85
                                    )
                                    .animation(
                                        reduceMotion
                                            ? .easeOut(duration: 0.18)
                                            : spring.delay(Double(index) * 0.045),
                                        value: expanded
                                    )
                            }
                        }
                    }
                    .padding(.trailing, 16)

                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: expanded)
        .onAppear {
            pulse = true
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : spring) {
                expanded = true
            }
        }
    }

    // MARK: - Pieces

    private var scrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(expanded ? 0.38 : 0))
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
                // Soft liquid halo under the control.
                Circle()
                    .fill(orange.opacity(0.55))
                    .frame(width: 64, height: 64)
                    .blur(radius: 14)
                    .scaleEffect(pulse && expanded ? 1.18 : 0.9)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.35).repeatForever(autoreverses: true),
                        value: pulse
                    )

                Circle()
                    .fill(Color.black)
                    .frame(width: 52, height: 52)
                    .shadow(color: orange.opacity(0.45), radius: 16, y: 6)

                TTIcon(icon: .plus, filled: true, size: 20)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(expanded ? 45 : 0))
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close menu")
    }

    private var liquidBackbone: some View {
        let count = max(actions.count, 1)
        let openHeight: CGFloat = 64 + CGFloat(count) * 72

        return ZStack(alignment: .top) {
            Capsule(style: .continuous)
                .fill(orange.opacity(0.9))
                .frame(width: 44, height: expanded ? openHeight : 44)
                .blur(radius: 22)
                .opacity(expanded ? 1 : 0.35)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [orange, orange.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: expanded ? openHeight - 12 : 28)
                .blur(radius: 10)
                .opacity(expanded ? 0.95 : 0.4)

            // Metaball nodes behind each emerging pill.
            VStack(spacing: 28) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(orange.opacity(expanded ? 0.85 : 0.2))
                        .frame(width: expanded ? 36 : 12, height: expanded ? 36 : 12)
                        .blur(radius: 8)
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.15)
                                : spring.delay(Double(i) * 0.05),
                            value: expanded
                        )
                }
            }
            .padding(.top, 70)
        }
        .frame(width: 72, alignment: .top)
        .padding(.trailing, 6)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : spring, value: expanded)
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
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text(action.subtitle)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }

                Spacer(minLength: 8)
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .frame(width: 268, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
            )
            .overlay {
                if action.highlighted {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(orange.opacity(0.35), lineWidth: 1.2)
                }
            }
        }
        .buttonStyle(TTLiquidFABPillPressStyle())
    }

    private func emergeOffset(for index: Int) -> CGFloat {
        // Collapse toward the FAB so pills feel like they pour out of it.
        -CGFloat(index + 1) * 18 - 28
    }

    private func select(_ action: TTLiquidFABAction) {
        dismiss {
            onSelect(action)
        }
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : settle) {
            expanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.12 : 0.28)) {
            isPresented = false
            completion?()
        }
    }
}

private struct TTLiquidFABPillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
