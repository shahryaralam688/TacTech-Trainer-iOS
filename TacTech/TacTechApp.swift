import SwiftUI

@main
struct TacTechApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .tint(TTColor.accent)
        }
    }
}
