import SwiftUI

enum TrainerTab: Hashable {
    case dashboard, plans, chat, profile
}

private struct TrainerTabRouterKey: EnvironmentKey {
    static let defaultValue: (TrainerTab) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Switch the trainer root tab (Home / Plans / Chat / Profile).
    var selectTrainerTab: (TrainerTab) -> Void {
        get { self[TrainerTabRouterKey.self] }
        set { self[TrainerTabRouterKey.self] = newValue }
    }
}

struct TrainerRootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: TrainerTab = .dashboard
    @State private var mounted: Set<TrainerTab> = [.dashboard]
    @State private var showAIChat = false
    @State private var showLiquidMenu = false
    @State private var showCreatePlan = false
    @State private var showAssignSheet = false
    @State private var showAssignmentsList = false
    @State private var showTraineeChat = false
    @State private var showJoinRequests = false
    @State private var showRoster = false
    @State private var pendingChatThreadId: String?
    @State private var rootTabBarVisible = true
    @State private var relationshipToast: TTToastMessage?
    @Namespace private var aiChatNamespace
    @Namespace private var liquidFABNamespace

    private var tabs: [TTTabBarItem<TrainerTab>] {
        let locale = LocalizationController.shared.locale
        return [
            TTTabBarItem(.dashboard, icon: .house1, label: String(localized: "tab.home", locale: locale)),
            TTTabBarItem(.plans, icon: .barbellDiagonal, label: String(localized: "tab.plans", locale: locale)),
            TTTabBarItem(.chat, icon: .chat, label: String(localized: "tab.chat", locale: locale)),
            TTTabBarItem(.profile, icon: .user, label: String(localized: "tab.profile", locale: locale))
        ]
    }

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
                                .ttTabFade(tab: .dashboard, selection: tab, order: [.dashboard, .plans, .chat, .profile])
                                .allowsHitTesting(tab == .dashboard)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .dashboard { visible = true }
                                }
                        }
                        if mounted.contains(.plans) {
                            WorkoutPlansView()
                                .ttTabFade(tab: .plans, selection: tab, order: [.dashboard, .plans, .chat, .profile])
                                .allowsHitTesting(tab == .plans)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .plans { visible = true }
                                }
                        }
                        if mounted.contains(.chat) {
                            // Same chat screen as everywhere else; AI Coach pinned on top.
                            HumanPeerChatView(
                                audience: .trainer,
                                isEmbedded: true,
                                isActive: tab == .chat,
                                onOpenAICoach: openAIChat,
                                onOpenRoster: { showRoster = true }
                            )
                            .ttTabFade(tab: .chat, selection: tab, order: [.dashboard, .plans, .chat, .profile])
                            .allowsHitTesting(tab == .chat)
                            .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                if tab != .chat { visible = true }
                            }
                        }
                        if mounted.contains(.profile) {
                            TrainerProfileView()
                                .ttTabFade(tab: .profile, selection: tab, order: [.dashboard, .plans, .chat, .profile])
                                .allowsHitTesting(tab == .profile)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .profile { visible = true }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)
                    .ttSwipeBetweenTabs(
                        order: [.dashboard, .plans, .chat, .profile],
                        selection: $tab,
                        enabled: rootTabBarVisible && !showLiquidMenu
                    )
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
        .onChange(of: showAIChat) { _, visible in
            if !visible {
                Task { await store.refreshAfterAIChat() }
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
        .sheet(isPresented: $showJoinRequests) {
            JoinRequestsView()
                .ttModalSheetPresentation()
        }
        .sheet(isPresented: $showRoster) {
            // Invite code, join requests, search and trainee profiles live here now.
            MyTraineesView()
                .ttModalSheetPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenJoinRequests)) { _ in
            selectTab(.dashboard)
            showJoinRequests = true
            Task { await store.fetchTrainerJoinRequests() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttJoinRequestRealtime)) { note in
            let type = (note.userInfo?["type"] as? String) ?? ""
            Task { await store.handleJoinRequestRealtime(type: type) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttRelationshipChanged)) { note in
            // Root always reconciles — roster updates even on Dashboard / Plans.
            store.handleRelationshipChanged(
                action: (note.userInfo?["action"] as? String) ?? "",
                reason: note.userInfo?["reason"] as? String,
                trainerUserId: note.userInfo?["trainerUserId"] as? String,
                traineeUserId: note.userInfo?["traineeUserId"] as? String,
                traineeProfileId: note.userInfo?["traineeProfileId"] as? String
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenRelationshipEnded)) { _ in
            selectTab(.dashboard)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttPlanAssignmentChanged)) { note in
            // Trainer 2nd device: soft refresh plans/roster (actor device already updated via REST).
            store.handlePlanAssignmentChanged(
                action: (note.userInfo?["action"] as? String) ?? "",
                planId: note.userInfo?["planId"] as? String,
                planTitle: note.userInfo?["planTitle"] as? String,
                traineeProfileId: note.userInfo?["traineeProfileId"] as? String
            )
        }
        .onChange(of: store.softToast) { _, toast in
            guard let toast else { return }
            relationshipToast = toast
            store.softToast = nil
        }
        .ttToast($relationshipToast)
        .ttTrainerLiveSync()
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
            selectTab(.chat)
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

// MARK: - Live sync (trainee activity → trainer screens)

/// Keeps the trainer's view of trainee activity (workout logs + analytics) fresh.
///
/// Why this exists: the trainer workspace was loaded once at launch, and the socket has no
/// "workout completed" event. Trainee logs therefore only reached the trainer after opening a
/// trainee or pulling to refresh. This reuses the existing `refreshTraineePerformance` call.
@MainActor
enum TrainerLiveSync {
    private static var lastRun: Date = .distantPast
    private static var inFlight = false

    /// Refreshes logs + analytics for every trainee on the roster (or one trainee).
    /// Throttled so foreground/notification bursts don't hammer the API. Errors are swallowed:
    /// stale data stays on screen rather than blanking it.
    static func refresh(store: AppStore, traineeId: String? = nil, force: Bool = false) async {
        guard store.session?.role == .trainer, !inFlight else { return }
        if !force, Date().timeIntervalSince(lastRun) < 5 { return }
        inFlight = true
        defer { inFlight = false; lastRun = Date() }

        let ids: [String]
        if let traineeId {
            ids = [traineeId]
        } else {
            ids = store.currentTrainer.map { store.trainees(for: $0).map(\.id) } ?? []
        }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { try? await store.refreshTraineePerformance(traineeId: id) }
            }
        }
    }
}

private struct TrainerLiveSyncModifier: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    private let notifications = NotificationStore.shared

    func body(content: Content) -> some View {
        content
            // Coming back to the app: trainee may have trained while the app was in background.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await TrainerLiveSync.refresh(store: store) }
            }
            // A new inbox item about a workout/metrics → refresh that trainee right away.
            .onChange(of: notifications.items.first?.id) { _, _ in
                guard let note = notifications.items.first else { return }
                let type = note.type.lowercased()
                guard type == "workout" || type == "metrics" || type.hasPrefix("workout_") else { return }
                let profileId = note.data["traineeProfileId"] ?? note.data["trainee_profile_id"] ?? note.data["traineeId"]
                Task { await TrainerLiveSync.refresh(store: store, traineeId: profileId, force: true) }
            }
    }
}

extension View {
    /// Trainer roots: refresh trainee activity on foreground and on workout notifications.
    func ttTrainerLiveSync() -> some View { modifier(TrainerLiveSyncModifier()) }
}
