import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared rectangular toggle (no liquid glass).
/// Shape: rounded-rect track + rounded-square thumb. ON `#FF8A00` · OFF gray.
struct LiquidToggle: View {
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    @GestureState private var isPressed = false

    private let width: CGFloat = 52
    private let height: CGFloat = 30
    private let trackCorner: CGFloat = 7
    private let thumbInset: CGFloat = 3
    private let animation = Animation.easeOut(duration: 0.35)

    private let amber = Color(hex: 0xFF8A00)
    private let offTrack = Color(hex: 0xD1D1D6)

    private var thumbSide: CGFloat { height - (thumbInset * 2) }
    private var thumbCorner: CGFloat { max(3.5, trackCorner - 2) }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: trackCorner, style: .continuous)
                .fill(isOn ? amber : offTrack)

            RoundedRectangle(cornerRadius: thumbCorner, style: .continuous)
                .fill(Color.white)
                .frame(width: thumbSide, height: thumbSide)
                .shadow(color: Color.black.opacity(0.10), radius: 1.5, y: 1)
                .padding(.horizontal, thumbInset)
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.12), radius: 3, y: 2)
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

#Preview("Toggle") {
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
