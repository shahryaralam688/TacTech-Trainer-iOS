import SwiftUI

/// Minimal brand splash — black canvas, orange mark, soft one-shot fade-in.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                TecTachLogoMark(size: 72)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text("TacTech")
                        .font(TTFont.headingLG(.bold))
                        .foregroundStyle(.white)

                    Text("Your AI fitness coach")
                        .font(TTFont.textMD(.medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 6)
            }
            .padding(.horizontal, 32)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("TacTech. Your AI fitness coach.")
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.55)) {
                    appeared = true
                }
            }
        }
    }
}

#Preview("Splash") {
    SplashView()
}
