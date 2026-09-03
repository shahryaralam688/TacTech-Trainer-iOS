import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    @State private var splashElapsed = false

    private var showsSplash: Bool {
        !splashElapsed || store.isRestoringSession
    }

    var body: some View {
        ZStack {
            Group {
                if let session = store.session {
                    switch session.role {
                    case .trainer:
                        trainerDestination
                    case .trainee:
                        traineeDestination
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
        .animation(.easeInOut(duration: 0.25), value: store.session?.userId)
        .animation(.easeInOut(duration: 0.25), value: store.assessmentCompleted)
        .task {
            try? await Task.sleep(for: .milliseconds(2600))
            splashElapsed = true
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
