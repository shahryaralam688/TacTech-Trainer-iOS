import SwiftUI

/// Post sign-in / sign-up interstitial — cool motion before home or first assessment.
/// Returning users: short welcome-back. First-time: longer setup intro, then Continue.
struct PostLoginBridgeView: View {
    enum Mode: Equatable {
        case welcomeBack
        case firstSetup
    }

    let mode: Mode
    let name: String
    let role: UserRole
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    @State private var ring = false
    @State private var showCTA = false
    @State private var floatY: CGFloat = 0
    @State private var autoAdvanceTask: Task<Void, Never>?

    private let orange = TTColor.actionOrange

    private var firstName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return role == .trainer ? "Coach" : "Athlete" }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    private var headline: String {
        switch mode {
        case .welcomeBack: return "Welcome back,\n\(firstName)"
        case .firstSetup: return "You're in,\n\(firstName)"
        }
    }

    private var subtitle: String {
        switch mode {
        case .welcomeBack:
            return role == .trainer
                ? "Your roster and plans are ready."
                : "Your training hub is ready."
        case .firstSetup:
            return role == .trainer
                ? "A quick coaching profile helps TacTech tailor your workspace."
                : "A short fitness assessment unlocks your personalized plan."
        }
    }

    private var ctaTitle: String {
        switch mode {
        case .welcomeBack: return "Enter TacTech"
        case .firstSetup: return "Start assessment"
        }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .stroke(orange.opacity(0.22), lineWidth: 14)
                        .frame(width: 148, height: 148)
                        .scaleEffect(ring ? 1.08 : 0.92)
                        .opacity(ring ? 0.35 : 0.8)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [orange, orange.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .shadow(color: orange.opacity(0.45), radius: 28, y: 12)
                        .offset(y: floatY)

                    TTIcon(icon: role == .trainer ? .whistle : .barbellDiagonal, filled: true, size: 42)
                        .foregroundStyle(.white)
                        .offset(y: floatY)
                        .scaleEffect(phase >= 1 ? 1 : 0.7)
                        .opacity(phase >= 1 ? 1 : 0)
                }
                .padding(.bottom, 36)

                VStack(spacing: 14) {
                    Text(headline)
                        .font(TTFont.workSans(34, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .opacity(phase >= 2 ? 1 : 0)
                        .offset(y: phase >= 2 ? 0 : 18)

                    Text(subtitle)
                        .font(TTFont.workSans(16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .opacity(phase >= 3 ? 1 : 0)
                        .offset(y: phase >= 3 ? 0 : 12)
                }

                if mode == .firstSetup {
                    featurePills
                        .padding(.top, 28)
                        .opacity(phase >= 4 ? 1 : 0)
                        .offset(y: phase >= 4 ? 0 : 10)
                }

                Spacer()

                if showCTA {
                    Button(action: finish) {
                        Text(ctaTitle)
                            .font(TTFont.workSans(17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    if mode == .welcomeBack {
                        Text("Taking you in…")
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .padding(.bottom, 28)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: runIntro)
        .onDisappear {
            autoAdvanceTask?.cancel()
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.8), trigger: phase)
    }

    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [orange.opacity(0.35), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .blur(radius: 8)

            // Soft drifting orbs
            Circle()
                .fill(orange.opacity(0.12))
                .frame(width: 220, height: 220)
                .offset(x: ring ? 90 : -40, y: ring ? -160 : -120)
                .blur(radius: 30)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 180, height: 180)
                .offset(x: ring ? -110 : -60, y: ring ? 280 : 220)
                .blur(radius: 24)
        }
    }

    private var featurePills: some View {
        VStack(spacing: 10) {
            bridgePill(icon: .sparkle1, text: role == .trainer ? "Coaching focus" : "Goals & level")
            bridgePill(icon: .barbellDiagonal, text: role == .trainer ? "Client style" : "Schedule & diet")
            bridgePill(icon: .robotFace1, text: "AI coach tuned to you")
        }
        .padding(.horizontal, 40)
    }

    private func bridgePill(icon: SandowIcon, text: String) -> some View {
        HStack(spacing: 10) {
            TTIcon(icon: icon, filled: true, size: 14)
                .foregroundStyle(orange)
            Text(text)
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func runIntro() {
        if reduceMotion {
            phase = 4
            showCTA = true
            ring = true
            if mode == .welcomeBack {
                scheduleAutoAdvance(afterMs: 900)
            }
            return
        }

        withAnimation(.easeOut(duration: 0.55)) { phase = 1; ring = true }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            floatY = -8
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { phase = 2 }
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { phase = 3 }
            if mode == .firstSetup {
                try? await Task.sleep(for: .milliseconds(360))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { phase = 4 }
                try? await Task.sleep(for: .milliseconds(280))
            } else {
                try? await Task.sleep(for: .milliseconds(200))
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { showCTA = true }
            if mode == .welcomeBack {
                scheduleAutoAdvance(afterMs: 1600)
            }
        }
    }

    private func scheduleAutoAdvance(afterMs: UInt64) {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(afterMs))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        autoAdvanceTask?.cancel()
        onFinished()
    }
}

#Preview("Welcome back") {
    PostLoginBridgeView(mode: .welcomeBack, name: "Maya", role: .trainee, onFinished: {})
}

#Preview("First setup") {
    PostLoginBridgeView(mode: .firstSetup, name: "Alex", role: .trainer, onFinished: {})
}
