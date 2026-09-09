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

// MARK: - Full-screen AI Coach

/// Edge-to-edge AI chat — presented via `fullScreenCover` from trainer/trainee roots.
struct TTAICoachChatOverlay: View {
    @Binding var isPresented: Bool
    var audience: TTAIChatAudience
    /// Kept for call-site compatibility (matched FAB morph no longer used for chat).
    var namespace: Namespace.ID

    @State private var store = CoachStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        AICoachView(
            store: store,
            audience: audience,
            onClose: close,
            showsGrabber: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : (reduceMotion ? 0 : 18))
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.9)) {
                appeared = true
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: isPresented)
    }

    private func close() {
        store.onDisappear()
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.92)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.22)) {
            isPresented = false
        }
    }
}

extension View {
    func ttAICoachFABSource(namespace: Namespace.ID, isChatPresented: Bool) -> some View {
        self
    }
}

/// When enabled, root content ignores the keyboard safe area (tab bar stays put).
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
