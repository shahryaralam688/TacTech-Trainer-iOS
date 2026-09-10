import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @State private var splashElapsed = false
    @State private var postLoginBridgeDone = false

    private var showsSplash: Bool {
        !splashElapsed || store.isRestoringSession
    }

    private var showsPostLoginBridge: Bool {
        store.session != nil
            && store.pendingPostLoginBridge
            && !postLoginBridgeDone
            && !showsSplash
    }

    var body: some View {
        ZStack {
            Group {
                if let session = store.session {
                    if showsPostLoginBridge {
                        PostLoginBridgeView(
                            mode: store.assessmentCompleted ? .welcomeBack : .firstSetup,
                            name: store.currentUser?.name ?? "",
                            role: session.role,
                            onFinished: finishPostLoginBridge
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        switch session.role {
                        case .trainer:
                            trainerDestination
                        case .trainee:
                            traineeDestination
                        }
                    }
                } else if !store.isRestoringSession {
                    AuthFlowView()
                }
            }
            .opacity(showsSplash ? 0 : 1)

            if showsSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showsSplash)
        .animation(.spring(response: 0.48, dampingFraction: 0.88), value: showsPostLoginBridge)
        .animation(.easeInOut(duration: 0.25), value: store.session?.userId)
        .animation(.easeInOut(duration: 0.25), value: store.assessmentCompleted)
        .onChange(of: store.session?.userId) { _, newId in
            // New account session → allow bridge again for that login.
            if newId == nil {
                postLoginBridgeDone = false
                HumanCallStore.shared.stopMonitoring()
            } else {
                HumanCallStore.shared.startMonitoring()
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1400))
            splashElapsed = true
            if store.session != nil {
                HumanCallStore.shared.startMonitoring()
            }
        }
        // Must be overlay (not another fullScreenCover) — roots already present chat/AI covers.
        .humanCallOverlay()
    }

    private func finishPostLoginBridge() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            postLoginBridgeDone = true
            store.consumePostLoginBridge()
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
