import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, plans, trainees, profile
}

struct TrainerRootView: View {
    @State private var tab: TrainerTab = .dashboard
    @State private var showAIChat = false
    @State private var mountAIChat = false
    @State private var fabFrameGlobal: CGRect = .zero
    @Namespace private var aiChatNamespace

    private let tabs: [TTTabBarItem<TrainerTab>] = [
        TTTabBarItem(.dashboard, icon: .house1, label: "Home"),
        TTTabBarItem(.plans, icon: .barbellDiagonal, label: "Plans"),
        TTTabBarItem(.trainees, icon: .usersTwo, label: "Trainees"),
        TTTabBarItem(.profile, icon: .user, label: "Profile")
    ]

    private let morph = Animation.spring(response: 0.5, dampingFraction: 0.86)

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

                if mountAIChat {
                    TTAICoachChatOverlay(
                        isPresented: $showAIChat,
                        audience: .trainer,
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    if !showAIChat { mountAIChat = false }
                }
            }
        }
    }

    private func openAIChat() {
        mountAIChat = true
        withAnimation(morph) {
            showAIChat = true
        }
    }
}

#Preview("Trainer Root") {
    TrainerRootView()
        .ttPreviewTrainer()
}
