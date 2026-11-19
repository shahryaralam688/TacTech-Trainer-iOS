import SwiftUI

/// How long the splash waits for the backend before it shows "Can't reach the server" with Retry.
private let launchServerWaitLimit: Duration = .seconds(8)

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @State private var splashElapsed = false
    /// The 8 s wait ran out while the launch restore was still pending.
    @State private var launchWaitedTooLong = false
    /// Bumped by Retry: restarts the 8 s wait.
    @State private var launchAttempt = 0

    /// Splash replaced by the calm "Can't reach the server" state. The restore keeps running underneath, so if the
    /// server answers late the app simply continues.
    private var showsConnectionError: Bool {
        store.isRestoringSession && (store.launchConnectionFailed || launchWaitedTooLong)
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
                    LaunchConnectionErrorView {
                        launchWaitedTooLong = false
                        launchAttempt += 1
                        store.retryLaunchRestore()
                    }
                    .transition(.opacity)
                } else {
                    SplashView()
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
        // Splash look unchanged until the wait limit passes; Retry restarts the wait.
        .task(id: launchAttempt) {
            try? await Task.sleep(for: launchServerWaitLimit)
            guard !Task.isCancelled, store.isRestoringSession else { return }
            launchWaitedTooLong = true
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
