import SwiftUI

@main
struct TacTechApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) private var pushDelegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .tint(TTColor.accent)
                .onChange(of: scenePhase) { _, phase in
                    guard store.session != nil else { return }
                    if phase == .active {
                        HumanCallStore.shared.startMonitoring()
                        NotificationStore.shared.start()
                        NotificationCenter.default.post(name: .ttRefreshIncomingCalls, object: nil)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttIncomingCallPush)) { note in
                    if let info = note.userInfo {
                        HumanCallStore.shared.handlePushPayload(info)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ttRefreshIncomingCalls)) { _ in
                    Task { await HumanCallStore.shared.refreshIncomingNow() }
                }
        }
    }
}

extension Notification.Name {
    /// Push / local bridge for `{ type: chat_call, ... }`.
    static let ttIncomingCallPush = Notification.Name("ttIncomingCallPush")
    static let ttRefreshIncomingCalls = Notification.Name("ttRefreshIncomingCalls")
}
