import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, profile
}

struct TraineeRootView: View {
    @State private var tab: TraineeTab = .home
    @State private var mounted: Set<TraineeTab> = [.home]
    @State private var showAIChat = false
    @State private var showLiquidMenu = false
    @State private var showCoachChat = false
    @Namespace private var aiChatNamespace
    @Namespace private var liquidFABNamespace

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
                        onCenterTap: openLiquidMenu,
                        bottomInset: geo.safeAreaInsets.bottom,
                        aiChatNamespace: aiChatNamespace,
                        isAIChatPresented: showAIChat,
                        isCenterMenuPresented: showLiquidMenu,
                        liquidFABNamespace: liquidFABNamespace
                    )
                    .zIndex(20)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .modifier(TTRootKeyboardIgnore(enabled: true))

            if showLiquidMenu {
                TTLiquidFABOverlay(
                    isPresented: $showLiquidMenu,
                    actions: TTLiquidFABAction.traineeCenterMenu,
                    onSelect: handleLiquidAction,
                    bottomReserve: TTFloatingTabBar<TraineeTab>.liquidMenuFABBottomReserve,
                    namespace: liquidFABNamespace
                )
                .zIndex(50)
                .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showAIChat) {
            TTAICoachChatOverlay(
                isPresented: $showAIChat,
                audience: .trainee,
                namespace: aiChatNamespace
            )
        }
        .fullScreenCover(isPresented: $showCoachChat) {
            HumanPeerChatView(audience: .trainee)
        }
        .onChange(of: tab) { _, newTab in
            mounted.insert(newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenAICoachChat)) { _ in
            openAIChat()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            mounted.insert(.profile)
        }
    }

    private func openLiquidMenu() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showLiquidMenu = true
        }
    }

    private func handleLiquidAction(_ action: TTLiquidFABAction) {
        switch action.id {
        case "ai":
            openAIChat()
        case "coachChat":
            TTKeyboard.dismiss()
            showCoachChat = true
        default:
            break
        }
    }

    private func openAIChat() {
        TTKeyboard.dismiss()
        showAIChat = true
    }
}

#Preview("Trainee Root") {
    TraineeRootView()
        .ttPreviewTrainee()
}
