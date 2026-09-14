import SwiftUI

/// Rectangular toggle matching product art: rounded-rect track + rounded-square thumb
/// (not a pill / not a circular knob). ON = amber `#FF8A00`, OFF = light gray.
struct LiquidToggle: View {
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    @GestureState private var isPressed = false

    private let width: CGFloat = 52
    private let height: CGFloat = 30
    /// Track corner — rectangular capsule, not a full pill.
    private let trackCorner: CGFloat = 7
    private let thumbInset: CGFloat = 3
    private let animation = Animation.easeOut(duration: 0.35)

    private let amber = Color(hex: 0xFF8A00)
    private let activeBlue = Color(hex: 0x1E90FF)
    private let offTrack = Color(hex: 0xD1D1D6)

    private var thumbSide: CGFloat { height - (thumbInset * 2) }
    private var thumbCorner: CGFloat { max(3.5, trackCorner - 2) }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            track
            thumb
                .padding(.horizontal, thumbInset)
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.12), radius: 3, y: 2)
        .shadow(color: glowColor, radius: 5, y: 1)
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
            withAnimation(animation) { isOn.toggle() }
        }
    }

    // MARK: - Layers

    private var track: some View {
        RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
            .fill(trackFill)
            .overlay {
                // Subtle glass edge (keeps Liquid Glass feel without changing shape).
                RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isOn ? 0.45 : 0.65),
                                Color.white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
    }

    private var thumb: some View {
        RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
            .fill(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
            }
            .frame(width: thumbSide, height: thumbSide)
            .shadow(color: Color.black.opacity(0.10), radius: 1.5, y: 1)
    }

    private var trackFill: Color {
        if isPressed { return activeBlue }
        return isOn ? amber : offTrack
    }

    private var glowColor: Color {
        if isPressed { return activeBlue.opacity(0.18) }
        if isOn { return amber.opacity(0.15) }
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
                withAnimation(animation) {
                    isOn.toggle()
                }
            }
    }
}

#Preview("Liquid Toggle · Shape") {
    struct Host: View {
        @State private var a = false
        @State private var b = true
        var body: some View {
            VStack(spacing: 28) {
                LiquidToggle(isOn: $a)
                LiquidToggle(isOn: $b)
            }
            .padding(40)
            .background(Color.white)
        }
    }
    return Host()
}
