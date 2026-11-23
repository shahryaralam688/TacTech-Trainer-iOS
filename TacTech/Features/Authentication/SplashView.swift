import SwiftUI

/// Minimal brand splash — black canvas, orange mark, soft one-shot fade-in.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// Quiet line under the mark while a slow launch is still connecting ("Connecting…", "Still connecting…").
    /// It sits in an overlay, so the centred splash layout never moves.
    var status: LocalizedStringKey?

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
        .overlay(alignment: .bottom) {
            if let status {
                Text(status)
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.bottom, 96)
                    .accessibilityAddTraits(.updatesFrequently)
            }
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

/// Shown instead of the splash when the app can't reach the backend at launch. Same black canvas, mark and type as
/// the splash; calm wording, one Retry button. The user stays signed in.
struct LaunchConnectionErrorView: View {
    enum Kind: Equatable {
        /// The device has no internet.
        case offline
        /// The device is online but the server is not answering (refused, timeout, 5xx).
        case notResponding
    }

    var kind: Kind = .notResponding
    /// Seconds until the next automatic retry ("Retrying in N s"); nil when none is scheduled.
    var retryCountdown: Int?
    let onRetry: () -> Void

    private var title: LocalizedStringKey {
        kind == .offline ? "You’re offline" : "Can’t reach TacTech"
    }

    private var message: LocalizedStringKey {
        kind == .offline
            ? "Connect to the internet to open TacTech. You’re still signed in."
            : "This is usually temporary. Your account and data are safe."
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                TecTachLogoMark(size: 72)

                VStack(spacing: 8) {
                    Text(title)
                        .font(TTFont.headingLG(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(TTFont.textMD(.medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }

                TTButton(title: String(localized: "Try again", locale: LocalizationController.shared.locale), action: onRetry)
                    // The app's primary button in its light colours (white text on brand) so it reads on the black canvas.
                    .environment(\.colorScheme, .light)
                    .padding(.top, 8)

                // Fixed height, so "Retrying in N s" appearing never moves anything.
                Group {
                    if let seconds = retryCountdown {
                        Text("Retrying in \(seconds) s")
                    } else {
                        Text(verbatim: " ")
                    }
                }
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(height: 20)
                    .opacity(retryCountdown == nil ? 0 : 1)
                    .accessibilityHidden(retryCountdown == nil)
            }
            .padding(.horizontal, 32)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .onAppear { announce() }
        .onChange(of: kind) { _, _ in announce() }
    }

    /// VoiceOver hears the state change.
    private func announce() {
        let locale = LocalizationController.shared.locale
        let text = kind == .offline
            ? String(localized: "You’re offline", locale: locale)
            : String(localized: "Can’t reach TacTech", locale: locale)
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

#Preview("Splash") {
    SplashView()
}

#Preview("Offline") {
    LaunchConnectionErrorView(kind: .offline) {}
}

#Preview("Not responding") {
    LaunchConnectionErrorView(kind: .notResponding, retryCountdown: 6) {}
}
