import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, plans, trainees, profile
}

struct TrainerRootView: View {
    @State private var tab: TrainerTab = .dashboard
    @State private var mounted: Set<TrainerTab> = [.dashboard]
    @State private var showAIChat = false
    @State private var showLiquidMenu = false
    @State private var showCreatePlan = false
    @State private var showAssignSheet = false
    @State private var showDuplicateSheet = false
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
                    .padding(.bottom, TTFloatingTabBar<TrainerTab>.barBodyHeight + geo.safeAreaInsets.bottom)

                    TTFloatingTabBar(
                        tabs: tabs,
                        selection: $tab,
                        onCenterTap: openLiquidMenu,
                        bottomInset: geo.safeAreaInsets.bottom,
                        aiChatNamespace: aiChatNamespace,
                        isAIChatPresented: showAIChat,
                        isCenterMenuPresented: showLiquidMenu
                    )
                    .zIndex(20)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .modifier(TTRootKeyboardIgnore(enabled: true))

            if showAIChat {
                TTAICoachChatOverlay(
                    isPresented: $showAIChat,
                    audience: .trainer,
                    namespace: aiChatNamespace
                )
                .zIndex(40)
                .transition(.opacity)
            }

            if showLiquidMenu {
                TTLiquidFABOverlay(
                    isPresented: $showLiquidMenu,
                    actions: TTLiquidFABAction.trainerCenterMenu,
                    onSelect: handleLiquidAction,
                    bottomReserve: 18
                )
                .zIndex(50)
                .transition(.opacity)
            }
        }
        .onChange(of: tab) { _, newTab in
            mounted.insert(newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenAICoachChat)) { _ in
            openAIChat()
        }
        .sheet(isPresented: $showCreatePlan) {
            CreatePlanView()
        }
        .sheet(isPresented: $showAssignSheet) {
            PlanQuickAssignSheet()
        }
        .sheet(isPresented: $showDuplicateSheet) {
            PlanDuplicateSheet()
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
        case "create":
            showCreatePlan = true
            tab = .plans
            mounted.insert(.plans)
        case "assign":
            showAssignSheet = true
        case "duplicate":
            showDuplicateSheet = true
        default:
            break
        }
    }

    private func openAIChat() {
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
