import SwiftUI

struct OnboardingPage: Identifiable, Equatable {
    let id: Int
    let imageName: String
    let title: String
    let subtitle: String
}

struct WelcomeOnboardingView: View {
    let onFinished: () -> Void

    @State private var pageIndex = 0

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

    var body: some View {
        ZStack {
            TabView(selection: $pageIndex) {
                ForEach(pages) { page in
                    OnboardingSlideView(page: page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingProgressBar(count: pages.count, current: pageIndex)
                    .padding(.top, 12)

                Spacer()

                HStack(spacing: 12) {
                    OnboardingArrowButton(systemName: "arrow.left", enabled: pageIndex > 0) {
                        go(to: pageIndex - 1)
                    }
                    OnboardingArrowButton(systemName: "arrow.right", enabled: true) {
                        advance()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .safeAreaPadding(.vertical)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.28), value: pageIndex)
    }

    private func go(to index: Int) {
        guard pages.indices.contains(index) else { return }
        pageIndex = index
    }

    private func advance() {
        if pageIndex < pages.count - 1 {
            pageIndex += 1
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
                        .init(color: .black.opacity(0.45), location: 0.62),
                        .init(color: .black.opacity(0.88), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 14) {
                    Spacer()
                    Text(page.title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                    Text(page.subtitle)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 240)
            }
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingProgressBar: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(index <= current ? 1 : 0.32))
                    .frame(height: 3.5)
            }
        }
        .frame(maxWidth: 168)
    }
}

private struct OnboardingArrowButton: View {
    let systemName: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.38)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "arrow.left" ? "Back" : "Next")
    }
}
