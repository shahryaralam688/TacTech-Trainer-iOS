import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, plans, trainees, profile
}

private struct TrainerTabRouterKey: EnvironmentKey {
    static let defaultValue: (TrainerTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switch the trainer root tab (Home / Plans / Trainees / Profile).
    var selectTrainerTab: (TrainerTab) -> Void {
        get { self[TrainerTabRouterKey.self] }
        set { self[TrainerTabRouterKey.self] = newValue }
    }
}

struct TrainerRootView: View {
    @State private var tab: TrainerTab = .dashboard
    @State private var mounted: Set<TrainerTab> = [.dashboard]
    @State private var showAIChat = false
    @State private var showLiquidMenu = false
    @State private var showCreatePlan = false
    @State private var showAssignSheet = false
    @State private var showAssignmentsList = false
    @State private var showTraineeChat = false
    @State private var pendingChatThreadId: String?
    @State private var rootTabBarVisible = true
    @Namespace private var aiChatNamespace
    @Namespace private var liquidFABNamespace

    private let tabs: [TTTabBarItem<TrainerTab>] = [
        TTTabBarItem(.dashboard, icon: .house1, label: "Home"),
        TTTabBarItem(.plans, icon: .barbellDiagonal, label: "Plans"),
        TTTabBarItem(.trainees, icon: .usersTwo, label: "Trainees"),
        TTTabBarItem(.profile, icon: .user, label: "Profile")
    ]

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let tabClearance = rootTabBarVisible
                    ? TTFloatingTabBar<TrainerTab>.barBodyHeight + geo.safeAreaInsets.bottom
                    : geo.safeAreaInsets.bottom

                ZStack(alignment: .bottom) {
                    ZStack {
                        if mounted.contains(.dashboard) {
                            TrainerDashboardView()
                                .opacity(tab == .dashboard ? 1 : 0)
                                .allowsHitTesting(tab == .dashboard)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .dashboard { visible = true }
                                }
                        }
                        if mounted.contains(.plans) {
                            WorkoutPlansView()
                                .opacity(tab == .plans ? 1 : 0)
                                .allowsHitTesting(tab == .plans)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .plans { visible = true }
                                }
                        }
                        if mounted.contains(.trainees) {
                            MyTraineesView()
                                .opacity(tab == .trainees ? 1 : 0)
                                .allowsHitTesting(tab == .trainees)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .trainees { visible = true }
                                }
                        }
                        if mounted.contains(.profile) {
                            TrainerProfileView()
                                .opacity(tab == .profile ? 1 : 0)
                                .allowsHitTesting(tab == .profile)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .profile { visible = true }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)
                    .contentMargins(.bottom, tabClearance, for: .scrollContent)
                    .environment(\.ttRootTabBarClearance, rootTabBarVisible ? TTFloatingTabBar<TrainerTab>.barBodyHeight : 0)
                    .onPreferenceChange(TTRootTabBarVisibleKey.self) { visible in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            rootTabBarVisible = visible
                        }
                    }

                    if rootTabBarVisible {
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
                        .background(Color.clear)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .modifier(TTRootKeyboardIgnore(enabled: true))

            if showLiquidMenu {
                TTLiquidFABOverlay(
                    isPresented: $showLiquidMenu,
                    actions: TTLiquidFABAction.trainerCenterMenu,
                    onSelect: handleLiquidAction,
                    bottomReserve: TTFloatingTabBar<TrainerTab>.liquidMenuFABBottomReserve,
                    namespace: liquidFABNamespace
                )
                .zIndex(50)
                .transition(.opacity)
            }
        }
        .environment(\.selectTrainerTab, selectTab)
        .fullScreenCover(isPresented: $showAIChat) {
            TTAICoachChatOverlay(
                isPresented: $showAIChat,
                audience: .trainer,
                namespace: aiChatNamespace
            )
        }
        .onChange(of: tab) { _, newTab in
            mounted.insert(newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenAICoachChat)) { _ in
            openAIChat()
        }
        .sheet(isPresented: $showCreatePlan) {
            CreatePlanView()
                .ttModalSheetPresentation()
        }
        .sheet(isPresented: $showAssignSheet) {
            PlanQuickAssignSheet()
                .ttModalSheetPresentation()
        }
        .sheet(isPresented: $showAssignmentsList) {
            PlanAssignmentsListSheet()
                .ttModalSheetPresentation()
        }
        .fullScreenCover(isPresented: $showTraineeChat) {
            HumanPeerChatView(audience: .trainer, preferredThreadId: pendingChatThreadId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenHumanChat)) { note in
            pendingChatThreadId = note.userInfo?["threadId"] as? String
            TTKeyboard.dismiss()
            showTraineeChat = true
        }
        .onChange(of: showTraineeChat) { _, open in
            if !open { pendingChatThreadId = nil }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            mounted.insert(.profile)
        }
    }

    private func selectTab(_ newTab: TrainerTab) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tab = newTab
            mounted.insert(newTab)
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
        case "traineeChat":
            TTKeyboard.dismiss()
            showTraineeChat = true
        case "create":
            showCreatePlan = true
            selectTab(.plans)
        case "assign":
            showAssignSheet = true
        case "assignments":
            showAssignmentsList = true
        default:
            break
        }
    }

    private func openAIChat() {
        TTKeyboard.dismiss()
        showAIChat = true
    }
}

#Preview("Trainer Root") {
    TrainerRootView()
        .ttPreviewTrainer()
}
