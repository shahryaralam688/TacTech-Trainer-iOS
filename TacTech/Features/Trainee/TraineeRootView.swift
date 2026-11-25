import SwiftUI

enum TraineeTab: Hashable {
    case home, workout, nutrition, profile
}

struct TraineeRootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: TraineeTab = .home
    @State private var mounted: Set<TraineeTab> = [.home]
    @State private var showAIChat = false
    /// State of the liquid-bubble menu. This view only HOLDS it and never reads its values in `body` (same as the Trainer root).
    @State private var bubbleMenu = TTBubbleEngine()
    /// "Add meal" from the + menu: triggers the same camera/photo-library → ManualMealView flow as Home.
    @State private var mealCaptureTrigger = 0
    /// "Chat with your coach" from the + menu: the direct conversation (linked coach), or coach discovery when none.
    @State private var coachChatTarget: TTChatTarget?
    private struct HumanChatRoute: Identifiable {
        let id = UUID()
        let threadId: String?
    }

    @State private var showFindCoaches = false
    @State private var humanChatRoute: HumanChatRoute?
    @State private var showProfileSheet = false   // Profile moved off the tab bar → opened as a sheet
    @State private var rootTabBarVisible = true
    @State private var relationshipToast: TTToastMessage?
    @Namespace private var aiChatNamespace

    private var tabs: [TTTabBarItem<TraineeTab>] {
        let locale = LocalizationController.shared.locale
        return [
            TTTabBarItem(.home, icon: .house1, label: String(localized: "tab.home", locale: locale), title: String(localized: "tab.home", locale: locale)),
            TTTabBarItem(.workout, icon: .barbellDiagonal, label: String(localized: "tab.workout", locale: locale), title: String(localized: "tab.workout", locale: locale)),
            TTTabBarItem(.nutrition, icon: .forkKnife, label: String(localized: "tab.nutrition", locale: locale), title: String(localized: "tab.nutrition", locale: locale)),
            TTTabBarItem(.profile, icon: .user, label: String(localized: "tab.profile", locale: locale), title: String(localized: "tab.profile", locale: locale))
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
                        if isMounted(.home) {
                            TraineeDashboardView()
                                .ttTabFade(tab: .home, selection: tab, order: [.home, .workout, .nutrition, .profile])
                                .allowsHitTesting(tab == .home)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .home { visible = true }
                                }
                        }
                        if isMounted(.workout) {
                            WorkoutHubView()
                                .ttTabFade(tab: .workout, selection: tab, order: [.home, .workout, .nutrition, .profile])
                                .allowsHitTesting(tab == .workout)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .workout { visible = true }
                                }
                        }
                        if isMounted(.nutrition) {
                            NutritionView()
                                .ttTabFade(tab: .nutrition, selection: tab, order: [.home, .workout, .nutrition, .profile])
                                .allowsHitTesting(tab == .nutrition)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .nutrition { visible = true }
                                }
                        }
                        if isMounted(.profile) {
                            // Progress now opens from Profile ("My progress").
                            TraineeProfileView()
                                .ttTabFade(tab: .profile, selection: tab, order: [.home, .workout, .nutrition, .profile])
                                .allowsHitTesting(tab == .profile)
                                .transformPreference(TTRootTabBarVisibleKey.self) { visible in
                                    if tab != .profile { visible = true }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)
                    .ttSwipeBetweenTabs(
                        order: [.home, .workout, .nutrition, .profile],
                        selection: tabSelection,
                        enabled: rootTabBarVisible
                    )
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
                            selection: tabSelection,
                            onCenterTap: openLiquidMenu,
                            bottomInset: geo.safeAreaInsets.bottom,
                            aiChatNamespace: aiChatNamespace,
                            isAIChatPresented: showAIChat,
                            bubbleEngine: bubbleMenu,
                            centerMenuHint: "AI assistant, log a meal, or chat with your coach"
                        )
                        .background(Color.clear)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .modifier(TTRootKeyboardIgnore(enabled: true))

            // Mounted once (never inserted or removed, no transition); draws nothing while closed. Same as the Trainer root.
            TTBubbleMenuOverlay(
                engine: bubbleMenu,
                actions: TTLiquidFABAction.traineeCenterMenu,
                onSelect: handleLiquidAction,
                bottomReserve: TTFloatingTabBar<TraineeTab>.liquidMenuFABBottomReserve,
                shownIds: TTLiquidFABAction.traineeBubbleIds,
                showLabelsInside: true
            )
            .zIndex(50)
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
        .fullScreenCover(item: $humanChatRoute) { route in
            HumanPeerChatView(audience: .trainee, preferredThreadId: route.threadId)
        }
        // + menu → Add meal: same camera/photo-library → ManualMealView flow as Home.
        .modifier(TTPhotoMealCaptureModifier(
            trigger: $mealCaptureTrigger,
            onNotice: { relationshipToast = TTToastMessage(text: $0, style: .info) },
            onSaved: { relationshipToast = $0 }
        ))
        // + menu → Chat with your coach: the direct conversation; Back closes it and returns to where the trainee was.
        .fullScreenCover(item: $coachChatTarget) { target in
            HumanPeerChatView(audience: .trainee, preferredPeerUserId: target.id, preferredPeerName: target.name)
        }
        // + menu → Chat with your coach, with no linked coach: the existing coach discovery.
        .sheet(isPresented: $showFindCoaches) {
            FindCoachesView().ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .onChange(of: tab) { _, newTab in
            PerfTemp.interval("tab.switch", seconds: 0.4) // PERF-TEMP
            PerfTemp.screenTab("tab: \(newTab)") // PERF-TEMP
            mounted.insert(newTab)
            // Back on Home: take the server's unread number for the coach row.
            if newTab == .home { Task { await HumanChatStore.shared.refreshInbox(quiet: true) } }
        }
        // Keep the chat inbox live (socket + poll) while the trainee shell is up, so Home's unread number follows new
        // messages and reads from other devices. Opening and closing the chat does not tear it down.
        .task {
            await HumanChatStore.shared.startInboxMonitoring()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
            HumanChatStore.shared.stopInboxMonitoring()
        }
        .modifier(NotificationModifier(
            store: store,
            tab: $tab,
            mounted: $mounted,
            showProfileSheet: $showProfileSheet,
            showFindCoaches: $showFindCoaches,
            humanChatRoute: $humanChatRoute,
            relationshipToast: $relationshipToast,
            openAIChat: openAIChat
        ))
        .sheet(isPresented: $showProfileSheet) {
            TraineeProfileView(showsBack: true)
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
    }

    /// A tab is built as soon as it is selected (never one frame later, from an onChange), and kept once built.
    private func isMounted(_ t: TraineeTab) -> Bool { mounted.contains(t) || tab == t }

    /// Tab bar and swipe write through this: the selected tab is marked as mounted in the same change.
    private var tabSelection: Binding<TraineeTab> {
        Binding(get: { tab }, set: { newTab in
            mounted.insert(newTab)
            tab = newTab
        })
    }

    private func openLiquidMenu() {
        // Bubble menu: only its own isolated state changes (no animation transaction, no root state). Same as the Trainer.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { bubbleMenu.open() }
    }

    private func handleLiquidAction(_ action: TTLiquidFABAction) {
        switch action.id {
        case "ai":
            openAIChat()
        case "logMeal":
            TTKeyboard.dismiss()
            mealCaptureTrigger += 1
        case "coachChat":
            openCoachChat()
        default:
            break
        }
    }

    private func openCoachChat() {
        TTKeyboard.dismiss()
        guard store.hasLinkedTrainer,
              let trainee = store.currentTrainee,
              let trainer = store.trainer(for: trainee) else {
            // No linked coach: coach discovery (the same sheet Home's "Enter an invite code" row opens).
            showFindCoaches = true
            return
        }
        let name = store.users.first { $0.id == trainer.userId }?.name
        coachChatTarget = TTChatTarget(id: trainer.userId, name: (name?.isEmpty == false) ? name : nil)
    }

    private func openAIChat() {
        TTKeyboard.dismiss()
        showAIChat = true
    }

    private struct NotificationModifier: ViewModifier {
        let store: AppStore
        @Binding var tab: TraineeTab
        @Binding var mounted: Set<TraineeTab>
        @Binding var showProfileSheet: Bool
        @Binding var showFindCoaches: Bool
        @Binding var humanChatRoute: HumanChatRoute?
        @Binding var relationshipToast: TTToastMessage?
        let openAIChat: () -> Void

        func body(content: Content) -> some View {
            content
                .onReceive(NotificationCenter.default.publisher(for: .ttOpenAICoachChat)) { _ in
                    openAIChat()
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttOpenHumanChat)) { note in
                    let threadId = note.userInfo?["threadId"] as? String
                    TTKeyboard.dismiss()
                    showProfileSheet = false
                    showFindCoaches = false
                    humanChatRoute = HumanChatRoute(threadId: threadId)
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttOpenTraineeProfile)) { _ in
                    showProfileSheet = true
                    store.scheduleTraineeCoachLinkSync()
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttOpenTraineeProfileJoin)) { _ in
                    showProfileSheet = true
                    Task { await store.handleJoinRequestRealtime(type: "join_request_rejected") }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttJoinRequestRealtime)) { note in
                    let type = (note.userInfo?["type"] as? String) ?? ""
                    Task { await store.handleJoinRequestRealtime(type: type) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttRelationshipChanged)) { note in
                    store.handleRelationshipChanged(
                        action: (note.userInfo?["action"] as? String) ?? "",
                        reason: note.userInfo?["reason"] as? String,
                        trainerUserId: note.userInfo?["trainerUserId"] as? String,
                        traineeUserId: note.userInfo?["traineeUserId"] as? String,
                        traineeProfileId: note.userInfo?["traineeProfileId"] as? String
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttOpenRelationshipEnded)) { _ in
                    showProfileSheet = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttPlanAssignmentChanged)) { note in
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
        }
    }
}

#Preview("Trainee Root") {
    TraineeRootView()
        .ttPreviewTrainee()
}
