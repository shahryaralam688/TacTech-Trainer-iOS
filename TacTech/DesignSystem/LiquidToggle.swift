import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared rectangular “Liquid Glass” toggle for the whole app.
/// Shape: rounded-rect track + rounded-square thumb (not pill / not circle).
/// ON `#FF8A00` · pressed `#1E90FF` · OFF frosted gray · 0.35s ease-out.
struct LiquidToggle: View {
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    @GestureState private var isPressed = false

    private let width: CGFloat = 52
    private let height: CGFloat = 30
    private let trackCorner: CGFloat = 7
    private let thumbInset: CGFloat = 3
    private let stroke: CGFloat = 0.75
    private let animation = Animation.easeOut(duration: 0.35)

    private let amber = Color(hex: 0xFF8A00)
    private let amberDeep = Color(hex: 0xFF6B00)
    private let activeBlue = Color(hex: 0x1E90FF)
    private let offTrack = Color(hex: 0xD1D1D6)

    private var thumbSide: CGFloat { height - (thumbInset * 2) }
    private var thumbCorner: CGFloat { max(3.5, trackCorner - 2) }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            track
            liquidSheen
            thumb
                .padding(.horizontal, thumbInset)
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.10), radius: 3, y: 2)
        .shadow(color: glowColor, radius: 6, y: 1)
        .scaleEffect(isPressed ? 0.97 : 1)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(animation, value: isOn)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .contentShape(RoundedRectangle(cornerRadius: trackCorner, style: .continuous))
        .gesture(tapGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(isEnabled ? "Double tap to toggle" : "")
        .accessibilityAction {
            guard isEnabled else { return }
            fireHaptic()
            withAnimation(animation) { isOn.toggle() }
        }
    }

    // MARK: - Track (glass body + molten core)

    private var track: some View {
        RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
            .fill(trackBase)
            .overlay {
                // Viscous liquid fill — soft blur = surface tension / diffusion.
                RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                    .fill(liquidCore)
                    .blur(radius: (isOn || isPressed) ? 0.55 : 0)
            }
            .overlay {
                // Internal caustic when ON / pressed.
                if isOn || isPressed {
                    RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.08),
                                    Color.clear
                                ],
                                center: UnitPoint(x: isOn ? 0.72 : 0.28, y: 0.22),
                                startRadius: 0,
                                endRadius: 34
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                // Glass edge refraction (IOR-style rim).
                RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: stroke
                    )
            }
            .overlay {
                // Top specular strip.
                RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    .padding(1.25)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .background {
                // Frosted glass plate under the fill.
                RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: trackCorner, style: .continuous))
    }

    /// Subtle moving highlight that follows the thumb (liquid motion feel).
    private var liquidSheen: some View {
        HStack {
            if isOn { Spacer(minLength: 0) }
            Capsule()
                .fill(Color.white.opacity(isOn || isPressed ? 0.22 : 0.12))
                .frame(width: 14, height: height - 10)
                .blur(radius: 3)
                .padding(.horizontal, 8)
            if !isOn { Spacer(minLength: 0) }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Thumb (glass rounded square)

    private var thumb: some View {
        RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.98),
                                Color.white.opacity(0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                // Glass face highlight.
                RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(1)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.35),
                                Color.black.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .frame(width: thumbSide, height: thumbSide)
            .shadow(color: Color.black.opacity(0.14), radius: 2, y: 1)
            .shadow(color: Color.white.opacity(0.55), radius: 0.5, y: -0.5)
    }

    // MARK: - Colors

    private var trackBase: Color {
        if isPressed { return activeBlue.opacity(0.92) }
        if isOn { return amber.opacity(0.95) }
        return offTrack.opacity(0.92)
    }

    private var liquidCore: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [activeBlue.opacity(0.95), Color(hex: 0x1873D4).opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        if isOn {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [amber.opacity(0.98), amberDeep.opacity(0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.28))
    }

    private var glowColor: Color {
        if isPressed { return activeBlue.opacity(0.20) }
        if isOn { return amber.opacity(0.18) }
        return .clear
    }

    private var tapGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, state, _ in
                guard isEnabled else { return }
                state = true
            }
            .onEnded { _ in
                guard isEnabled else { return }
                fireHaptic()
                withAnimation(animation) {
                    isOn.toggle()
                }
            }
    }

    private func fireHaptic() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

#Preview("Liquid Toggle · Glass") {
    struct Host: View {
        @State private var a = false
        @State private var b = true
        var body: some View {
            VStack(spacing: 28) {
                LiquidToggle(isOn: $a)
                LiquidToggle(isOn: $b)
            }
            .padding(40)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.97), Color(white: 0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
    return Host()
}
