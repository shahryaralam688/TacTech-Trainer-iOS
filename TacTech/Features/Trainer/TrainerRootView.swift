import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, plans, trainees, profile
}

struct TrainerRootView: View {
    @State private var tab: TrainerTab = .dashboard
    @State private var mounted: Set<TrainerTab> = [.dashboard]
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
                    ZStack {
                        if mounted.contains(.dashboard) {
                            TrainerDashboardView()
                                .opacity(tab == .dashboard ? 1 : 0)
                                .allowsHitTesting(tab == .dashboard)
                        }
                        if mounted.contains(.plans) {
                            WorkoutPlansView()
                                .opacity(tab == .plans ? 1 : 0)
                                .allowsHitTesting(tab == .plans)
                        }
                        if mounted.contains(.trainees) {
                            MyTraineesView()
                                .opacity(tab == .trainees ? 1 : 0)
                                .allowsHitTesting(tab == .trainees)
                        }
                        if mounted.contains(.profile) {
                            TrainerProfileView()
                                .opacity(tab == .profile ? 1 : 0)
                                .allowsHitTesting(tab == .profile)
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
                    .zIndex(20)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            // Tab chrome never lifts with keyboard; AI overlay tracks keyboard height itself.
            .modifier(TTRootKeyboardIgnore(enabled: true))

            // Overlay owns keyboard attachment (manual height).
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
        .onChange(of: tab) { _, newTab in
            mounted.insert(newTab)
        }
        .task {
            // Warm Profile after first frame so the first Profile tap isn't a cold Chart mount.
            try? await Task.sleep(for: .milliseconds(600))
            mounted.insert(.profile)
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
