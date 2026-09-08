import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, profile
}

struct TraineeRootView: View {
    @State private var tab: TraineeTab = .home
    @State private var showAIChat = false
    @Namespace private var aiChatNamespace

    private let tabs: [TTTabBarItem<TraineeTab>] = [
        TTTabBarItem(.home, icon: .house1, label: "Home"),
        TTTabBarItem(.workout, icon: .barbellDiagonal, label: "Workout"),
        TTTabBarItem(.nutrition, icon: .forkKnife, label: "Nutrition"),
        TTTabBarItem(.profile, icon: .user, label: "Profile")
    ]

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Group {
                        switch tab {
                        case .home:
                            TraineeDashboardView()
                        case .workout:
                            WorkoutHubView()
                        case .nutrition:
                            NutritionView()
                        case .profile:
                            TraineeProfileView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, TTFloatingTabBar<TraineeTab>.contentHeight + geo.safeAreaInsets.bottom)

                    TTFloatingTabBar(
                        tabs: tabs,
                        selection: $tab,
                        onCenterTap: openAIChat,
                        bottomInset: geo.safeAreaInsets.bottom,
                        aiChatNamespace: aiChatNamespace,
                        isAIChatPresented: showAIChat
                    )
                }
            }
            .ignoresSafeArea(edges: .bottom)
            // Tab chrome never lifts with keyboard; AI overlay tracks keyboard height itself.
            .modifier(TTRootKeyboardIgnore(enabled: true))

            // Overlay owns keyboard attachment (manual height).
            if showAIChat {
                TTAICoachChatOverlay(
                    isPresented: $showAIChat,
                    audience: .trainee,
                    namespace: aiChatNamespace
                )
                .zIndex(40)
                .transition(.opacity)
            }
        }
    }

    private func openAIChat() {
        // Insert without animating the tree; the overlay owns its present spring.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showAIChat = true
        }
    }
}

#Preview("Trainee Root") {
    TraineeRootView()
        .ttPreviewTrainee()
}
