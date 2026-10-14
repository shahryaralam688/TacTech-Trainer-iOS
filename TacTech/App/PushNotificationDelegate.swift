import UIKit
import UserNotifications

/// Captures APNs device tokens and routes remote notification taps.
final class PushNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            DispatchQueue.main.async {
                _ = NotificationStore.shared.handleUserInfo(remote, fromUserTap: true)
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            NotificationStore.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        // Expected when Push capability / paid Apple team / provisioning isn't set up yet.
        // Inbox + Socket notifications still work without APNs.
        print("APNs skipped: \(error.localizedDescription)")
        #endif
    }

    // Foreground: prefer Socket; honor Notification Settings (push / category / sound).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        Task { @MainActor in
            let store = NotificationStore.shared
            let handled = store.handleUserInfo(info, fromUserTap: false)
            // If Socket already delivered the same message/call, suppress banner noise.
            completionHandler(store.presentationOptions(
                for: info,
                suppressBannerBecauseDedupe: handled
            ))
            await store.refreshUnread()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            _ = NotificationStore.shared.handleUserInfo(info, fromUserTap: true)
            completionHandler()
        }
    }
}
