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
                        TrainerRootView()
                    case .trainee:
                        TraineeRootView()
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
        .task {
            try? await Task.sleep(for: .milliseconds(2600))
            splashElapsed = true
        }
    }
}
