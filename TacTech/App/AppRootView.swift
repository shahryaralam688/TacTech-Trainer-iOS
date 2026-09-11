import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @State private var splashElapsed = false

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
                SplashView()
                    .transition(.opacity)
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
            try? await Task.sleep(for: .milliseconds(1400))
            splashElapsed = true
            if showsAuthenticatedContent {
                HumanCallStore.shared.startMonitoring()
                NotificationStore.shared.start()
            }
        }
        // Must be overlay (not another fullScreenCover) — roots already present chat/AI covers.
        .humanCallOverlay()
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
