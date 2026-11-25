import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @State private var splashElapsed = false
    /// The wait limit (`TTNetworkTiming.serverWaitLimit`) ran out while the launch restore was still pending.
    @State private var launchWaitedTooLong = false
    /// Bumped by every retry: restarts the waits.
    @State private var launchAttempt = 0
    /// The restore has been pending longer than `TTNetworkTiming.stillConnectingAfter` → quiet "Still connecting…".
    @State private var stillConnecting = false
    /// A retry is running → quiet "Connecting…" on the splash (until it fails again or succeeds).
    @State private var isRetrying = false
    /// Automatic retries done since the last manual retry (picks the growing pause).
    @State private var autoRetryCount = 0
    /// Seconds until the next automatic retry.
    @State private var retryCountdown: Int?
    @Environment(\.scenePhase) private var scenePhase

    /// Splash replaced by the calm "Can't reach the server" state. The restore keeps running underneath, so if the
    /// server answers late the app simply continues.
    private var showsConnectionError: Bool {
        store.isRestoringSession && (store.launchConnectionFailed || launchWaitedTooLong)
    }

    /// The quiet line on the splash: "Connecting…" right after a retry, "Still connecting…" when the wait is long.
    private var splashStatus: LocalizedStringKey? {
        guard store.isRestoringSession else { return nil }
        if isRetrying { return "Connecting…" }
        return stillConnecting ? "Still connecting…" : nil
    }

    /// Drops the stuck work and sends the same launch restore again (one restore at a time).
    private func startRetry() {
        retryCountdown = nil
        launchWaitedTooLong = false
        stillConnecting = false
        isRetrying = true
        launchAttempt += 1
        store.retryLaunchRestore()
    }

    /// Key of the automatic-retry task: it only runs while the failure screen is visible and the app is active, so
    /// it stops by itself when the screen goes away.
    private var autoRetryKey: String {
        guard showsConnectionError, store.launchConnectionFailed, scenePhase == .active else { return "idle" }
        return "\(store.launchFailure.map { "\($0)" } ?? "?")-\(launchAttempt)-\(autoRetryCount)"
    }

    /// Server not responding: retry after 3, 6, 12, then every 30 s, with a quiet countdown.
    /// Offline: no timer — the network monitor (or the app coming back to the foreground) triggers the retry.
    private func runAutoRetry() async {
        guard autoRetryKey != "idle", store.launchFailure != .offline else {
            retryCountdown = nil
            return
        }
        let pauses = TTNetworkTiming.serverRetryPauses
        var remaining = pauses[min(autoRetryCount, pauses.count - 1)]
        while remaining > 0 {
            retryCountdown = remaining
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { retryCountdown = nil; return }
            remaining -= 1
        }
        retryCountdown = nil
        autoRetryCount += 1
        startRetry()
    }

    /// Cold launch only — never replay splash after interactive login/signup.
    private var showsSplash: Bool {
        !splashElapsed || store.isRestoringSession
    }

    /// Ready to show Home or Assessment (gates already resolved).
    private var showsAuthenticatedContent: Bool {
        store.session != nil
            && !store.isBootstrappingSession
            && !store.isRestoringSession
    }

    var body: some View {
        withLaunchRecovery(rootStack)
    }

    private var rootStack: some View {
        ZStack {
            Group {
                if showsAuthenticatedContent, let session = store.session {
                    switch session.role {
                    case .trainer:
                        trainerDestination
                            .transition(.opacity)
                    case .trainee:
                        traineeDestination
                            .transition(.opacity)
                    }
                } else if !store.isRestoringSession {
                    AuthFlowView()
                        .transition(.opacity)
                }
            }
            .opacity(showsSplash ? 0 : 1)

            if showsSplash {
                if showsConnectionError {
                    LaunchConnectionErrorView(
                        kind: store.launchFailure == .offline ? .offline : .notResponding,
                        retryCountdown: retryCountdown
                    ) {
                        autoRetryCount = 0
                        startRetry()
                    }
                    .transition(.opacity)
                } else {
                    SplashView(status: splashStatus)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.32), value: showsSplash)
        .animation(.easeInOut(duration: 0.28), value: showsAuthenticatedContent)
        .animation(.easeInOut(duration: 0.28), value: store.session?.userId)
        .onChange(of: store.session?.userId) { _, newId in
            if newId == nil {
                HumanCallStore.shared.stopMonitoring()
                Task { await NotificationStore.shared.unregisterCurrentToken() }
                NotificationStore.shared.stop()
            } else if showsAuthenticatedContent {
                HumanCallStore.shared.startMonitoring()
                NotificationStore.shared.start()
            }
        }
        .onChange(of: showsAuthenticatedContent) { _, ready in
            if ready, store.session != nil {
                HumanCallStore.shared.startMonitoring()
                NotificationStore.shared.start()
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            splashElapsed = true
            if showsAuthenticatedContent {
                HumanCallStore.shared.startMonitoring()
                NotificationStore.shared.start()
            }
        }
        // Must be overlay (not another fullScreenCover) — roots already present chat/AI covers.
        .humanCallOverlay()
        .sheet(isPresented: Binding(
            get: { store.showAIPaywall },
            set: { if !$0 { store.dismissAIPaywall(unlocked: false) } }
        )) {
            AIPaywallView(
                onUnlocked: {
                    store.dismissAIPaywall(unlocked: true)
                }
            )
            .ttModalSheetPresentation(dragIndicator: .visible)
            .environment(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttPresentAIPaywall)) { _ in
            store.presentAIPaywall()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttAIEntitlementDidChange)) { _ in
            Task { await store.refreshAIEntitlements() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ttAIPaywallUnlocked)) { _ in
            Task { await store.refreshAIEntitlements() }
        }
    }

    /// The launch-recovery timers and retry triggers (kept out of `body` so it type-checks quickly).
    private func withLaunchRecovery<Content: View>(_ content: Content) -> some View {
        content
        // Splash look unchanged until 3 s pass ("Still connecting…"), then the wait limit ("not responding").
        // Runs for the cold launch and for a slow post-sign-in load; every retry restarts it.
        .task(id: launchAttempt * 2 + (store.isRestoringSession ? 1 : 0)) {
            stillConnecting = false
            launchWaitedTooLong = false
            guard store.isRestoringSession else { return }
            try? await Task.sleep(for: TTNetworkTiming.stillConnectingAfter)
            guard !Task.isCancelled, store.isRestoringSession else { return }
            stillConnecting = true
            try? await Task.sleep(for: TTNetworkTiming.serverWaitLimit - TTNetworkTiming.stillConnectingAfter)
            guard !Task.isCancelled, store.isRestoringSession else { return }
            launchWaitedTooLong = true
        }
        .task(id: autoRetryKey) { await runAutoRetry() }
        // Back online or back in the foreground: retry launch error screen OR quietly sync an offline-entered session.
        .onReceive(NotificationCenter.default.publisher(for: .ttNetworkBecameReachable)) { _ in
            if store.needsOfflineSync {
                store.syncAfterReconnectIfNeeded()
            }
            guard showsConnectionError, store.launchConnectionFailed else { return }
            autoRetryCount = 0
            startRetry()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.needsOfflineSync {
                store.syncAfterReconnectIfNeeded()
            }
            guard phase == .active, showsConnectionError, store.launchConnectionFailed, store.launchFailure == .offline else { return }
            startRetry()
        }
        .onChange(of: store.launchConnectionFailed) { _, failed in
            if failed { isRetrying = false }
        }
        .onChange(of: store.isRestoringSession) { _, restoring in
            if !restoring { isRetrying = false; autoRetryCount = 0 }
        }
    }

    @ViewBuilder
    private var trainerDestination: some View {
        if !store.assessmentCompleted {
            TrainerAssessmentFlowView()
        } else {
            TrainerRootView()
        }
    }

    @ViewBuilder
    private var traineeDestination: some View {
        if !store.assessmentCompleted {
            FitnessAssessmentFlowView()
        } else {
            TraineeRootView()
        }
    }
}

#Preview("App Root · Trainee") {
    AppRootView()
        .ttPreviewTrainee()
}

#Preview("App Root · Trainer") {
    AppRootView()
        .ttPreviewTrainer()
}
