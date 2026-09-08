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

                if showAIChat {
                    TTAICoachChatOverlay(
                        isPresented: $showAIChat,
                        audience: .trainer,
                        namespace: aiChatNamespace
                    )
                    .zIndex(40)
                    .transition(.identity)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .modifier(TTRootKeyboardIgnore(enabled: !showAIChat))
    }

    private func openAIChat() {
        withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
            showAIChat = true
        }
    }
}

#Preview("Trainer Root") {
    TrainerRootView()
        .ttPreviewTrainer()
}
