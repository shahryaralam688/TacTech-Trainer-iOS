import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, profile
}

struct TraineeRootView: View {
    @State private var tab: TraineeTab = .home
    @State private var showAIChat = false
    @State private var mountAIChat = false
    @State private var fabFrameGlobal: CGRect = .zero
    @Namespace private var aiChatNamespace

    private let tabs: [TTTabBarItem<TraineeTab>] = [
        TTTabBarItem(.home, icon: .house1, label: "Home"),
        TTTabBarItem(.workout, icon: .barbellDiagonal, label: "Workout"),
        TTTabBarItem(.nutrition, icon: .forkKnife, label: "Nutrition"),
        TTTabBarItem(.profile, icon: .user, label: "Profile")
    ]

    var body: some View {
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

                if mountAIChat {
                    TTAICoachChatOverlay(
                        isPresented: $showAIChat,
                        audience: .trainee,
                        namespace: aiChatNamespace,
                        fabFrameGlobal: fabFrameGlobal
                    )
                    .zIndex(40)
                    .transition(.identity)
                }
            }
            .onPreferenceChange(TTAICoachFABFrameKey.self) { fabFrameGlobal = $0 }
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard)
        .onChange(of: showAIChat) { _, open in
            if !open {
                // Wait for overlay morph-to-FAB to finish before unmount.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    if !showAIChat { mountAIChat = false }
                }
            }
        }
    }

    private func openAIChat() {
        mountAIChat = true
        // Overlay owns the morph spring — avoid a second competing animation here.
        showAIChat = true
    }
}

#Preview("Trainee Root") {
    TraineeRootView()
        .ttPreviewTrainee()
}
