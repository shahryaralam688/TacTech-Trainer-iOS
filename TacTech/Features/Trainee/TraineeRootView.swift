import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, profile
}

struct TraineeRootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: TraineeTab = .home
    @State private var mounted: Set<TraineeTab> = [.home]
    @State private var showAIChat = false
    @State private var showLiquidMenu = false
    @State private var showCoachChat = false
    @State private var pendingChatThreadId: String?
    @State private var rootTabBarVisible = true
    @State private var relationshipToast: TTToastMessage?
    @Namespace private var aiChatNamespace
    @Namespace private var liquidFABNamespace

    private var tabs: [TTTabBarItem<TraineeTab>] {
        let locale = LocalizationController.shared.locale
        return [
            TTTabBarItem(.home, icon: .house1, label: String(localized: "tab.home", locale: locale)),
            TTTabBarItem(.workout, icon: .barbellDiagonal, label: String(localized: "tab.workout", locale: locale)),
            TTTabBarItem(.nutrition, icon: .forkKnife, label: String(localized: "tab.nutrition", locale: locale)),
            TTTabBarItem(.profile, icon: .user, label: String(localized: "tab.profile", locale: locale))
        ]
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let tabClearance = rootTabBarVisible
                    ? TTFloatingTabBar<TraineeTab>.barBodyHeight + geo.safeAreaInsets.bottom
                    : geo.safeAreaInsets.bottom

                ZStack(alignment: .bottom) {
                    ZStack {
                        if mounted.contains(.home) {
                            TraineeDashboardView()
                                .opacity(tab == .home ? 1 : 0)
                                .allowsHitTesting(tab == .home)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .home { visible = true }
                                }
                        }
                        if mounted.contains(.workout) {
                            WorkoutHubView()
                                .opacity(tab == .workout ? 1 : 0)
                                .allowsHitTesting(tab == .workout)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .workout { visible = true }
                                }
                        }
                        if mounted.contains(.nutrition) {
                            NutritionView()
                                .opacity(tab == .nutrition ? 1 : 0)
                                .allowsHitTesting(tab == .nutrition)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .nutrition { visible = true }
                                }
                        }
                        if mounted.contains(.profile) {
                            TraineeProfileView()
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
                    .environment(\.ttRootTabBarClearance, rootTabBarVisible ? TTFloatingTabBar<TraineeTab>.barBodyHeight : 0)
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
        .onChange(of: showAIChat) { _, visible in
            if !visible {
                Task { await store.refreshAfterAIChat() }
            }
        }
        .fullScreenCover(isPresented: $showCoachChat) {
            HumanPeerChatView(audience: .trainee, preferredThreadId: pendingChatThreadId)
        }
        .onChange(of: tab) { _, newTab in
            mounted.insert(newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenAICoachChat)) { _ in
            openAIChat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenHumanChat)) { note in
            pendingChatThreadId = note.userInfo?["threadId"] as? String
            TTKeyboard.dismiss()
            showCoachChat = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenTraineeProfile)) { _ in
            mounted.insert(.profile)
            tab = .profile
            // Inbox tap may arrive without a live socket event — same coalesced accept sync.
            store.scheduleTraineeCoachLinkSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenTraineeProfileJoin)) { _ in
            mounted.insert(.profile)
            tab = .profile
            Task { await store.handleJoinRequestRealtime(type: "join_request_rejected") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttJoinRequestRealtime)) { note in
            let type = (note.userInfo?["type"] as? String) ?? ""
            Task { await store.handleJoinRequestRealtime(type: type) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttRelationshipChanged)) { note in
            // Root always reconciles — no need to be on Profile tab.
            store.handleRelationshipChanged(
                action: (note.userInfo?["action"] as? String) ?? "",
                reason: note.userInfo?["reason"] as? String,
                trainerUserId: note.userInfo?["trainerUserId"] as? String,
                traineeUserId: note.userInfo?["traineeUserId"] as? String,
                traineeProfileId: note.userInfo?["traineeProfileId"] as? String
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenRelationshipEnded)) { _ in
            mounted.insert(.profile)
            tab = .profile
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttPlanAssignmentChanged)) { note in
            // Root always refreshes — Home + Workout update even if Workout tab isn’t selected.
            store.handlePlanAssignmentChanged(
                action: (note.userInfo?["action"] as? String) ?? "",
                planId: note.userInfo?["planId"] as? String,
                planTitle: note.userInfo?["planTitle"] as? String,
                traineeProfileId: note.userInfo?["traineeProfileId"] as? String
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenWorkoutHub)) { _ in
            mounted.insert(.workout)
            tab = .workout
        }
        .onChange(of: store.softToast) { _, toast in
            guard let toast else { return }
            relationshipToast = toast
            store.softToast = nil
        }
        .ttToast($relationshipToast)
        .onChange(of: showCoachChat) { _, open in
            if !open { pendingChatThreadId = nil }
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
