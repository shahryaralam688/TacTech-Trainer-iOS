import Combine
import SwiftUI
import UIKit

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
    /// Manual keyboard tracking — avoids SwiftUI double-counting keyboard safe-area + resized height.
    @State private var keyboardHeight: CGFloat = 0

    private let orange = TTColor.actionOrange
    private let present = Animation.spring(response: 0.46, dampingFraction: 0.88)
    private let resize = Animation.spring(response: 0.34, dampingFraction: 0.98)

    private let sidePad: CGFloat = 12
    /// Small gap under Dynamic Island / status bar (camera bar).
    private let topGap: CGFloat = 6
    private let bottomGapResting: CGFloat = 12
    private let bottomGapKeyboard: CGFloat = 6

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
                let keyboardOpen = keyboardHeight > 0
                // Full-screen reader ignores keyboard; `keyboardHeight` is screen-bottom based.
                let topInset = geo.safeAreaInsets.top + topGap
                let keyboardOverlap = keyboardOpen
                    ? max(0, keyboardHeight - geo.safeAreaInsets.bottom)
                    : 0
                let bottomInset = keyboardOpen
                    ? keyboardOverlap + bottomGapKeyboard
                    : geo.safeAreaInsets.bottom + bottomGapResting
                let available = max(240, geo.size.height - topInset - bottomInset)
                // Keyboard open → fill from under camera bar down to keyboard.
                // Resting → slightly shorter floating bubble.
                let bubbleHeight = keyboardOpen
                    ? available
                    : min(max(440, available * 0.9), available)

                floatingBubble(height: bubbleHeight, keyboardOpen: keyboardOpen)
                    .padding(.horizontal, sidePad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .scaleEffect(expanded ? 1 : 0.84, anchor: UnitPoint(x: 0.5, y: 1.0))
                    .opacity(expanded ? 1 : 0)
                    .offset(y: expanded ? 0 : 28)
                    .animation(present, value: expanded)
                    .animation(resize, value: bubbleHeight)
                    .animation(resize, value: bottomInset)
                    .animation(resize, value: topInset)
            }
            // Own keyboard insets — GeometryReader stays full-height; we pad with `keyboardHeight`.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear(perform: openSequence)
        .onReceive(keyboardPublisher) { height in
            withAnimation(resize) { keyboardHeight = height }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: isPresented)
    }

    private var keyboardPublisher: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification -> CGFloat? in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return nil }
                return frame.height
            }
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap { notification -> CGFloat? in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return nil }
                // 0 when keyboard fully dismissed off-screen.
                let screenH = UIScreen.main.bounds.height
                let visible = max(0, screenH - frame.origin.y)
                return visible
            }
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
        return Publishers.Merge3(willShow, willChange, willHide)
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    private func floatingBubble(height: CGFloat, keyboardOpen: Bool) -> some View {
        let corner: CGFloat = keyboardOpen ? 24 : 32
        return AICoachView(store: store, audience: audience, onClose: close)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background { liquidBackground(corner: corner) }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
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

    private func liquidBackground(corner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.94))
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
/// AI coach overlay tracks keyboard height manually and must not double-count insets.
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
