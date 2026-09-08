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

// MARK: - Keyboard overlap (stable publisher — never recreate in View.body)

/// Single metric for keyboard occlusion: visible height from the bottom of the screen.
/// Recreating Combine publishers inside `body` / `onReceive` re-subscribes every render and
/// was a major source of focus→keyboard hang (duplicate events + spring layout thrash).
private enum TTKeyboardOverlap {
    struct Event: Equatable {
        var height: CGFloat
        var duration: TimeInterval
    }

    /// Created once for the process. Prefer `willChangeFrame` only (covers show/move/hide end frames).
    static let publisher: AnyPublisher<Event, Never> = {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap { note -> Event? in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return nil
                }
                let screenH = UIScreen.main.bounds.height
                let visible = max(0, screenH - frame.origin.y)
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
                    .doubleValue ?? 0.25
                return Event(height: visible, duration: duration)
            }
            .removeDuplicates { abs($0.height - $1.height) < 0.5 }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }()
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

    private let sidePad: CGFloat = 12
    /// Small gap under Dynamic Island / status bar (camera bar).
    private let topGap: CGFloat = 6
    private let bottomGapResting: CGFloat = 12
    private let bottomGapKeyboard: CGFloat = 6
    /// Stable corner — changing radius while the keyboard animates forces clip/shadow rebuilds.
    private let bubbleCorner: CGFloat = 32

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
                let keyboardOpen = keyboardHeight > 0.5
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

                floatingBubble(height: bubbleHeight)
                    .padding(.horizontal, sidePad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .scaleEffect(expanded ? 1 : 0.84, anchor: UnitPoint(x: 0.5, y: 1.0))
                    .opacity(expanded ? 1 : 0)
                    .offset(y: expanded ? 0 : 28)
                    .animation(present, value: expanded)
            }
            // Own keyboard insets — GeometryReader stays full-height; we pad with `keyboardHeight`.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear(perform: openSequence)
        .onReceive(TTKeyboardOverlap.publisher) { event in
            applyKeyboardHeight(event.height, duration: event.duration)
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: isPresented)
    }

    /// Match UIKit keyboard timing — do not stack a second spring on every frame.
    private func applyKeyboardHeight(_ height: CGFloat, duration: TimeInterval) {
        guard abs(keyboardHeight - height) >= 0.5 else { return }
        let animation: Animation? = duration > 0 ? .easeOut(duration: duration) : nil
        if let animation {
            withAnimation(animation) { keyboardHeight = height }
        } else {
            keyboardHeight = height
        }
    }

    private func floatingBubble(height: CGFloat) -> some View {
        AICoachView(store: store, audience: audience, onClose: close)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background { liquidBackground }
            .clipShape(RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
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
            RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
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
