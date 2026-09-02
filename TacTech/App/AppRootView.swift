import SwiftUI

struct AppRootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let session = store.session {
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
    }
}
