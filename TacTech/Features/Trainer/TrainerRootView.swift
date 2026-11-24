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
    /// State of the liquid-bubble menu. This view only HOLDS it and never reads its values in `body`, so opening or
    /// closing the menu re-runs no body here (only the menu's own small views observe it).
    @State private var bubbleMenu = TTBubbleEngine()
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
            TTTabBarItem(.dashboard, icon: .house1, label: String(localized: "tab.home", locale: locale), title: String(localized: "tab.home", locale: locale)),
            TTTabBarItem(.plans, icon: .barbellDiagonal, label: String(localized: "tab.plans", locale: locale), title: String(localized: "tab.plans", locale: locale)),
            TTTabBarItem(.chat, icon: .chat, label: String(localized: "tab.chat", locale: locale), title: String(localized: "tab.chat", locale: locale)),
            TTTabBarItem(.profile, icon: .user, label: String(localized: "tab.profile", locale: locale), title: String(localized: "tab.profile", locale: locale))
        ]
    }

    var body: some View {
        #if DEBUG || PERF_TEMP
        let _ = PerfTemp.trace("TrainerRootView") { Self._printChanges() } // PERF-TEMP
        #endif
        // PERF-TEMP switch "Bubble menu (new)": ON = liquid-bubble menu, OFF = the previous pill menu (Release: always ON).
        let bubbleMenuOn = PerfTemp.on(.bubbleMenu)
        ZStack {
            GeometryReader { geo in
                let tabClearance = rootTabBarVisible
                    ? TTFloatingTabBar<TrainerTab>.barBodyHeight + geo.safeAreaInsets.bottom
                    : geo.safeAreaInsets.bottom

                ZStack(alignment: .bottom) {
                    ZStack {
                        if isMounted(.dashboard) {
                            TrainerDashboardView()
                                .ttTabFade(tab: .dashboard, selection: tab, order: [.dashboard, .plans, .chat, .profile])
                                .allowsHitTesting(tab == .dashboard)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .dashboard { visible = true }
                                }
                        }
                        if isMounted(.plans) {
                            WorkoutPlansView()
                                .ttTabFade(tab: .plans, selection: tab, order: [.dashboard, .plans, .chat, .profile])
                                .allowsHitTesting(tab == .plans)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .plans { visible = true }
                                }
                        }
                        if isMounted(.chat) {
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
                        if isMounted(.profile) {
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
                        selection: tabSelection,
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
                            selection: tabSelection,
                            onCenterTap: openLiquidMenu,
                            bottomInset: geo.safeAreaInsets.bottom,
                            aiChatNamespace: aiChatNamespace,
                            isAIChatPresented: showAIChat,
                            isCenterMenuPresented: showLiquidMenu,
                            liquidFABNamespace: bubbleMenuOn ? nil : liquidFABNamespace,
                            bubbleEngine: bubbleMenuOn ? bubbleMenu : nil
                        )
                        .background(Color.clear)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .modifier(TTRootKeyboardIgnore(enabled: true))

            if bubbleMenuOn {
                // Mounted once (never inserted or removed, no transition); draws nothing while closed.
                TTBubbleMenuOverlay(
                    engine: bubbleMenu,
                    actions: TTLiquidFABAction.trainerCenterMenu,
                    onSelect: handleLiquidAction,
                    bottomReserve: TTFloatingTabBar<TrainerTab>.liquidMenuFABBottomReserve,
                    showLabelsInside: true
                )
                .zIndex(50)
            } else if showLiquidMenu {
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
            PerfTemp.interval("tab.switch", seconds: 0.4) // PERF-TEMP
            PerfTemp.screenTab("tab: \(newTab)") // PERF-TEMP
            mounted.insert(newTab)
        }
        // Build Plans, Chat and Profile quietly once the app has settled, one at a time, so the first visit
        // doesn't build a whole screen in the middle of the slide. They stay hidden (opacity 0, no touches).
        .task {
            PerfTemp.screenTab("tab: dashboard") // PERF-TEMP
            try? await Task.sleep(for: .seconds(1.5))
            for next in [TrainerTab.plans, .chat, .profile] {
                if Task.isCancelled { return }
                // Wait while the user is busy with the + menu or the AI chat.
                while showLiquidMenu || showAIChat || bubbleMenu.presented {
                    try? await Task.sleep(for: .milliseconds(400))
                    if Task.isCancelled { return }
                }
                if !mounted.contains(next) { mounted.insert(next) }
                try? await Task.sleep(for: .milliseconds(700))
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenTraineeMeals)) { _ in
            selectTab(.dashboard)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenRelationshipEnded)) { _ in
            selectTab(.dashboard)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttWorkoutSessionChanged)) { note in
            store.handleWorkoutSessionChanged(
                traineeId: (note.userInfo?["traineeId"] as? String) ?? "",
                action: (note.userInfo?["action"] as? String) ?? ""
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttRealtimeConnected)) { _ in
            store.handleRealtimeReconnected()
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

    /// A tab is built as soon as it is selected (never one frame later, from an onChange), and kept once built.
    private func isMounted(_ t: TrainerTab) -> Bool { mounted.contains(t) || tab == t }

    /// Tab bar and swipe write through this: the selected tab is marked as mounted in the same change.
    private var tabSelection: Binding<TrainerTab> {
        Binding(get: { tab }, set: { newTab in
            mounted.insert(newTab)
            tab = newTab
        })
    }

    private func openLiquidMenu() {
        if PerfTemp.raw(.bubbleMenu) {
            // Bubble menu: only its own isolated state changes (no animation transaction, no root state).
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { bubbleMenu.open() }
            return
        }
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
        guard PerfTemp.raw(.liveSync) else { return } // PERF-TEMP
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
        // One batch: requests run concurrently, the store is written once at the end (and only if changed).
        await store.refreshTraineesPerformance(traineeIds: ids)
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
