import SwiftUI

// MARK: - Audience (shared with AICoachView)

enum TTAIChatAudience {
    case trainer
    case trainee

    var headerSubtitle: String {
        switch self {
        case .trainer: "Plan · clients · feedback"
        case .trainee: "Workouts · form · nutrition"
        }
    }

    var suggestions: [String] {
        switch self {
        case .trainer:
            ["Draft a 4-day plan", "Check trainee progress", "Write form cues"]
        case .trainee:
            ["What’s my next workout?", "Form tips for squats", "Meal ideas today"]
        }
    }

    var welcome: String {
        switch self {
        case .trainer:
            "I’m your TacTech AI. Ask about plans, trainees, or cues — type, talk, or share a photo."
        case .trainee:
            "I’m your TacTech AI. Ask about workouts, form, or nutrition — type, talk, or share a photo."
        }
    }
}

enum TTAICoachPortal {
    static let matchedID = "tactech.aiCoach.portal"
}

// MARK: - Liquid floating chat (Plus FAB → live CoachStore)

struct TTAICoachChatOverlay: View {
    @Binding var isPresented: Bool
    var audience: TTAIChatAudience
    var namespace: Namespace.ID

    @State private var store = CoachStore()
    @State private var expanded = false

    private let orange = TTColor.actionOrange
    private let present = Animation.spring(response: 0.46, dampingFraction: 0.88)
    private let resize = Animation.spring(response: 0.34, dampingFraction: 0.98)

    private let sidePad: CGFloat = 14
    private let topGap: CGFloat = 10
    private let bottomGap: CGFloat = 12

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(expanded ? 0.22 : 0))
                .ignoresSafeArea()
                .opacity(expanded ? 1 : 0)
                .animation(present, value: expanded)
                .onTapGesture { close() }
                .allowsHitTesting(expanded)

            GeometryReader { geo in
                let topInset = geo.safeAreaInsets.top + topGap
                let bottomInset = geo.safeAreaInsets.bottom + bottomGap
                let maxBubbleHeight = max(280, geo.size.height - topInset - bottomInset)
                let bubbleHeight = min(max(440, maxBubbleHeight * 0.9), maxBubbleHeight)

                floatingBubble(height: bubbleHeight)
                    .padding(.horizontal, sidePad)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(expanded ? 1 : 0.84, anchor: UnitPoint(x: 0.5, y: 1.0))
                    .opacity(expanded ? 1 : 0)
                    .offset(y: expanded ? 0 : 28)
                    .animation(present, value: expanded)
                    .animation(resize, value: bubbleHeight)
                    .animation(resize, value: bottomInset)
                    .animation(resize, value: topInset)
            }
        }
        .onAppear(perform: openSequence)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: isPresented)
    }

    private func floatingBubble(height: CGFloat) -> some View {
        AICoachView(store: store, audience: audience, onClose: close)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background { liquidBackground }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                orange.opacity(0.35),
                                Color.white.opacity(0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: orange.opacity(expanded ? 0.22 : 0.08), radius: expanded ? 28 : 10, y: expanded ? 14 : 6)
            .shadow(color: Color.black.opacity(expanded ? 0.16 : 0.06), radius: expanded ? 30 : 12, y: expanded ? 18 : 8)
    }

    private var liquidBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.88))
            Circle()
                .fill(orange.opacity(0.14))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: 110, y: -160)
                .allowsHitTesting(false)
        }
    }

    private func openSequence() {
        withAnimation(present) { expanded = true }
    }

    private func close() {
        store.onDisappear()
        withAnimation(present) { expanded = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            isPresented = false
        }
    }
}

extension View {
    func ttAICoachFABSource(namespace: Namespace.ID, isChatPresented: Bool) -> some View {
        // Plus stays visible — no appear/disappear on chat open.
        self
    }
}

/// When enabled, root content ignores the keyboard safe area (tab bar stays put).
/// Disabled while AI chat is open so the floating bubble can lift with the keyboard.
struct TTRootKeyboardIgnore: ViewModifier {
    var enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.keyboard)
        } else {
            content
        }
    }
}
