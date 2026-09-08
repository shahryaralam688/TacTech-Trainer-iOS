import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, plans, trainees, profile
}

struct TrainerRootView: View {
    @State private var tab: TrainerTab = .dashboard
    @State private var showAIChat = false
    @Namespace private var aiChatNamespace

    private let tabs: [TTTabBarItem<TrainerTab>] = [
        TTTabBarItem(.dashboard, icon: .house1, label: "Home"),
        TTTabBarItem(.plans, icon: .barbellDiagonal, label: "Plans"),
        TTTabBarItem(.trainees, icon: .usersTwo, label: "Trainees"),
        TTTabBarItem(.profile, icon: .user, label: "Profile")
    ]

    var body: some View {
        ZStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Group {
                        switch tab {
                        case .dashboard:
                            TrainerDashboardView()
                        case .plans:
                            WorkoutPlansView()
                        case .trainees:
                            MyTraineesView()
                        case .profile:
                            TrainerProfileView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, TTFloatingTabBar<TrainerTab>.contentHeight + geo.safeAreaInsets.bottom)

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
            .modifier(TTRootKeyboardIgnore(enabled: !showAIChat))

            // Outside the tab GeometryReader so keyboard safe-area insets apply.
            if showAIChat {
                TTAICoachChatOverlay(
                    isPresented: $showAIChat,
                    audience: .trainer,
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

#Preview("Trainer Root") {
    TrainerRootView()
        .ttPreviewTrainer()
}
