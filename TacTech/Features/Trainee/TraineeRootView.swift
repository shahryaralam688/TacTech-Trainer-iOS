import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, profile
}

struct TraineeRootView: View {
    @State private var tab: TraineeTab = .home
    @State private var mounted: Set<TraineeTab> = [.home]
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
                    ZStack {
                        if mounted.contains(.home) {
                            TraineeDashboardView()
                                .opacity(tab == .home ? 1 : 0)
                                .allowsHitTesting(tab == .home)
                        }
                        if mounted.contains(.workout) {
                            WorkoutHubView()
                                .opacity(tab == .workout ? 1 : 0)
                                .allowsHitTesting(tab == .workout)
                        }
                        if mounted.contains(.nutrition) {
                            NutritionView()
                                .opacity(tab == .nutrition ? 1 : 0)
                                .allowsHitTesting(tab == .nutrition)
                        }
                        if mounted.contains(.profile) {
                            TraineeProfileView()
                                .opacity(tab == .profile ? 1 : 0)
                                .allowsHitTesting(tab == .profile)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, TTFloatingTabBar<TraineeTab>.barBodyHeight + geo.safeAreaInsets.bottom)

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
            .modifier(TTRootKeyboardIgnore(enabled: true))
        }
        .fullScreenCover(isPresented: $showAIChat) {
            TTAICoachChatOverlay(
                isPresented: $showAIChat,
                audience: .trainee,
                namespace: aiChatNamespace
            )
        }
        .onChange(of: tab) { _, newTab in
            mounted.insert(newTab)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            mounted.insert(.profile)
        }
    }

    private func openAIChat() {
        showAIChat = true
    }
}

#Preview("Trainee Root") {
    TraineeRootView()
        .ttPreviewTrainee()
}
