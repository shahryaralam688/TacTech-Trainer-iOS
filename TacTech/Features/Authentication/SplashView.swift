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

/// Shown instead of the splash when the backend can't be reached at launch. Same black canvas, mark and type as the
/// splash; calm wording, one Retry button. The user stays signed in.
struct LaunchConnectionErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                TecTachLogoMark(size: 72)

                VStack(spacing: 8) {
                    Text("Can’t reach the server")
                        .font(TTFont.headingLG(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Check your connection and try again. You’re still signed in.")
                        .font(TTFont.textMD(.medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                TTButton(title: String(localized: "Try again", locale: LocalizationController.shared.locale), action: onRetry)
                    // The app's primary button in its light colours (white text on brand) so it reads on the black canvas.
                    .environment(\.colorScheme, .light)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Splash") {
    SplashView()
}

#Preview("Can't reach the server") {
    LaunchConnectionErrorView {}
}
