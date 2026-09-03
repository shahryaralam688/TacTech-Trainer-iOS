import SwiftUI

struct OnboardingPage: Identifiable, Equatable {
    let id: Int
    let imageName: String
    let title: String
    let subtitle: String
}

struct WelcomeOnboardingView: View {
    let onFinished: () -> Void

    @State private var pageIndex: Int? = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            imageName: "OnboardingHero",
            title: "Welcome to\nTacTech",
            subtitle: "Train with clarity."
        ),
        OnboardingPage(
            id: 1,
            imageName: "OnboardingPlans",
            title: "Personalized\nFitness Plans",
            subtitle: "Choose your own fitness journey with AI."
        ),
        OnboardingPage(
            id: 2,
            imageName: "OnboardingMetrics",
            title: "Health Metrics &\nFitness Analytics",
            subtitle: "Monitor your health profile with ease."
        ),
        OnboardingPage(
            id: 3,
            imageName: "OnboardingWorkouts",
            title: "Extensive Workout\nLibraries",
            subtitle: "Explore ~100K exercises made for you!"
        ),
        OnboardingPage(
            id: 4,
            imageName: "OnboardingCoach",
            title: "Virtual AI Coach\nMentoring",
            subtitle: "Say goodbye to manual coaching!"
        ),
        OnboardingPage(
            id: 5,
            imageName: "OnboardingNutrition",
            title: "Nutrition &\nDiet Guidance",
            subtitle: "Lose weight and get fit with TacTech!"
        )
    ]

    private var currentIndex: Int {
        min(max(pageIndex ?? 0, 0), pages.count - 1)
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(pages) { page in
                            OnboardingSlideView(page: page)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(page.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageIndex)
                .scrollIndicators(.hidden)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingProgressBar(count: pages.count, current: currentIndex)
                    .padding(.top, 10)
                    .allowsHitTesting(false)

                Color.clear
                    .allowsHitTesting(false)

                HStack(spacing: TTSpace.sm) {
                    OnboardingArrowButton(
                        imageName: "OnboardingArrowLeft",
                        label: "Back",
                        enabled: currentIndex > 0
                    ) {
                        go(to: currentIndex - 1)
                    }
                    OnboardingArrowButton(
                        imageName: "OnboardingArrowRight",
                        label: "Next",
                        enabled: true
                    ) {
                        advance()
                    }
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .safeAreaPadding(.top)
            .safeAreaPadding(.bottom)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func go(to index: Int) {
        guard pages.indices.contains(index) else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            pageIndex = index
        }
    }

    private func advance() {
        if currentIndex < pages.count - 1 {
            go(to: currentIndex + 1)
        } else {
            onFinished()
        }
    }
}

private struct OnboardingSlideView: View {
    let page: OnboardingPage

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Image(page.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.38),
                        .init(color: TTPurple.p100.opacity(0.55), location: 0.62),
                        .init(color: TTPurple.p100.opacity(0.92), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 14) {
                    Spacer()
                    Text(page.title)
                        .font(TTFont.display(34))
                        .foregroundStyle(TTColor.inkOnDark)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                    Text(page.subtitle)
                        .font(TTFont.textXL())
                        .foregroundStyle(TTColor.inkOnDarkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 118)
            }
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingProgressBar: View {
    let count: Int
    let current: Int

    private var progress: CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(current + 1) / CGFloat(count)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TTPurple.p50.opacity(0.45))
                Capsule()
                    .fill(TTColor.inkOnDark)
                    .frame(width: max(geo.size.width * progress, geo.size.height))
            }
        }
        .frame(width: 152, height: 4)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.28), value: current)
    }
}

private struct OnboardingArrowButton: View {
    let imageName: String
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 20)
                .foregroundStyle(TTPurple.p100)
                .frame(maxWidth: .infinity)
                .frame(height: TTSpace.heroButtonHeight)
                .background(TTColor.inkOnDark)
                .clipShape(RoundedRectangle(cornerRadius: TTRadius.buttonHero, style: .continuous))
        }
        .buttonStyle(TTPressStyle())
        .contentShape(RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous))
        .opacity(enabled ? 1 : 0.38)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

#Preview("Welcome Onboarding") {
    WelcomeOnboardingView(onFinished: {})
}
