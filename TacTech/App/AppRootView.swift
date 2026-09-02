import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.isRestoringSession {
                ZStack {
                    TTColor.canvas.ignoresSafeArea()
                    ProgressView()
                        .tint(TTColor.brand)
                }
            } else if let session = store.session {
                switch session.role {
                case .trainer:
                    TrainerRootView()
                case .trainee:
                    TraineeRootView()
                }
            } else {
                AuthFlowView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.session?.userId)
        .animation(.easeInOut(duration: 0.2), value: store.isRestoringSession)
    }
}
