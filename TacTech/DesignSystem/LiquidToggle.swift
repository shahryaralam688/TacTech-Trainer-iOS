import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared rectangular toggle with native-like Liquid Glass optics.
/// Keeps product shape (rounded-rect track + rounded-square thumb), but materials /
/// refraction / speculars approximate iOS built-in glass switches.
struct LiquidToggle: View {
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let width: CGFloat = 52
    private let height: CGFloat = 30
    private let trackCorner: CGFloat = 7
    private let thumbInset: CGFloat = 3
    /// Matches UISwitch-style settle.
    private let animation = Animation.spring(response: 0.32, dampingFraction: 0.78)

    private let amber = Color(hex: 0xFF8A00)
    private let amberDeep = Color(hex: 0xFF6B00)
    private let activeBlue = Color(hex: 0x1E90FF)

    private var thumbSide: CGFloat { height - (thumbInset * 2) }
    private var thumbCorner: CGFloat { max(3.5, trackCorner - 2) }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            track
            thumb
                .padding(.horizontal, thumbInset)
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.08), radius: 2.5, y: 1.5)
        .shadow(color: tintGlow, radius: isOn || isPressed ? 7 : 0, y: 0)
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

    // MARK: - Track = frosted glass vessel + tinted liquid

    private var track: some View {
        ZStack {
            // Base glass plate (blur / material) — like UISwitch chassis.
            RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                .fill(reduceTransparency ? Color(white: 0.92) : Color.clear)
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }

            // Molten / tinted liquid inside the glass (translucent, not flat paint).
            RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                .fill(liquidTint)
                .opacity(reduceTransparency ? 1 : 0.92)
                .overlay {
                    // Soft diffusion / caustic bloom inside the liquid.
                    if isOn || isPressed {
                        RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.42),
                                        Color.white.opacity(0.10),
                                        Color.clear
                                    ],
                                    center: UnitPoint(x: isOn ? 0.78 : 0.22, y: 0.18),
                                    startRadius: 1,
                                    endRadius: 36
                                )
                            )
                            .blur(radius: 0.4)
                    }
                }
                .overlay {
                    // Bottom depth — darker liquid edge (surface tension).
                    RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(isOn ? 0.06 : 0.04),
                                    Color.black.opacity(isOn ? 0.14 : 0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.multiply)
                        .opacity(0.55)
                }

            // Inner glass bevel (light catching the rim).
            RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )

            // Thin top specular — clear glass lip.
            RoundedRectangle(cornerRadius: max(2, trackCorner - 1.5), style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.55)
                .padding(1.6)
                .blendMode(.screen)
                .allowsHitTesting(false)

            // Moving liquid highlight that follows the thumb.
            HStack {
                if isOn { Spacer(minLength: 0) }
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isOn || isPressed ? 0.28 : 0.14))
                    .frame(width: 11, height: height - 12)
                    .blur(radius: 2.5)
                    .padding(.horizontal, 9)
                if !isOn { Spacer(minLength: 0) }
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: trackCorner, style: .continuous))
        .modifier(NativeGlassTrackModifier())
    }

    // MARK: - Thumb = glass lens (rounded square)

    private var thumb: some View {
        ZStack {
            // Soft contact shadow under the lens.
            RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                .fill(Color.black.opacity(0.16))
                .blur(radius: 1.2)
                .offset(y: 0.8)
                .padding(0.5)

            RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color(white: 0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if !reduceTransparency {
                RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
            }

            // Specular dome — bright glass face.
            RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.15),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(.horizontal, 1.5)
                .padding(.top, 1.5)
                .padding(.bottom, thumbSide * 0.45)
                .allowsHitTesting(false)

            // Rim refraction.
            RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.35),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .frame(width: thumbSide, height: thumbSide)
        .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
        .shadow(color: Color.white.opacity(0.7), radius: 0.4, y: -0.4)
        .modifier(NativeGlassThumbModifier())
    }

    // MARK: - Tints

    private var liquidTint: some ShapeStyle {
        if isPressed {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        activeBlue.opacity(0.92),
                        Color(hex: 0x1570CC).opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        if isOn {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        amber.opacity(0.95),
                        amberDeep.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        // OFF — frosted gray glass (native switch track).
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.55),
                    Color(hex: 0xC7C7CC).opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var tintGlow: Color {
        if isPressed { return activeBlue.opacity(0.22) }
        if isOn { return amber.opacity(0.20) }
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

// MARK: - Native Liquid Glass (iOS 26+) with material fallback

private struct NativeGlassTrackModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 7))
        } else {
            content
        }
    }
}

private struct NativeGlassThumbModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 5))
        } else {
            content
        }
    }
}

#Preview("Liquid Toggle · Native Glass") {
    struct Host: View {
        @State private var a = false
        @State private var b = true
        var body: some View {
            VStack(spacing: 28) {
                LiquidToggle(isOn: $a)
                LiquidToggle(isOn: $b)
                Toggle("System", isOn: $a)
                    .labelsHidden()
                    .tint(Color(hex: 0xFF8A00))
            }
            .padding(40)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.97), Color(hex: 0xE8EEF6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    return Host()
}
