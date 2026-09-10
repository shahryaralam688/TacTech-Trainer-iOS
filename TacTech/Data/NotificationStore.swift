import Foundation
import UIKit
import UserNotifications

/// App notification inbox + badge + APNs token registration.
@MainActor
@Observable
final class NotificationStore {
    static let shared = NotificationStore()

    var items: [AppNotificationDTO] = []
    var unreadCount: Int = 0
    var isLoading = false
    var lastError: String?
    var preferences: NotificationPreferencesDTO = .init()

    private let api = NotificationAPI()
    private var nextCursor: String?
    private var monitoring = false
    private var seenMessageIds = Set<String>()
    private var seenSessionIds = Set<String>()
    private let tokenDefaultsKey = "tt.pushDeviceToken"

    private(set) var deviceTokenHex: String? {
        didSet {
            if let deviceTokenHex, !deviceTokenHex.isEmpty {
                UserDefaults.standard.set(deviceTokenHex, forKey: tokenDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
            }
        }
    }

    private init() {
        deviceTokenHex = UserDefaults.standard.string(forKey: tokenDefaultsKey)
    }

    // MARK: Lifecycle

    func start() {
        guard !monitoring else {
            Task { await refreshUnread() }
            return
        }
        monitoring = true
        Task {
            await refreshInbox()
            await refreshUnread()
            await loadPreferences()
            await requestAuthorizationAndRegister()
            if let token = deviceTokenHex {
                await registerTokenWithBackend(token)
            }
        }
    }

    func stop() {
        monitoring = false
        items = []
        unreadCount = 0
        nextCursor = nil
        seenMessageIds.removeAll()
        seenSessionIds.removeAll()
    }

    // MARK: Inbox

    func refreshInbox() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.listNotifications()
            items = page.items
            nextCursor = page.nextCursor
            if let count = page.unreadCount {
                unreadCount = count
            } else {
                unreadCount = page.items.filter(\.isUnread).count
            }
            rememberDedupeKeys(from: page.items)
            lastError = nil
            syncAppBadge()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshUnread() async {
        do {
            unreadCount = try await api.unreadCount()
            syncAppBadge()
        } catch {
            // Soft fail — inbox refresh may still work.
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !cursor.isEmpty else { return }
        do {
            let page = try await api.listNotifications(cursor: cursor)
            prependOrAppend(page.items, prepend: false)
            nextCursor = page.nextCursor
            if let count = page.unreadCount { unreadCount = count }
            syncAppBadge()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func markRead(_ notification: AppNotificationDTO) async {
        do {
            unreadCount = try await api.markRead(notificationId: notification.id)
            if let idx = items.firstIndex(where: { $0.id == notification.id }) {
                items[idx].readAt = items[idx].readAt ?? Date()
            }
            syncAppBadge()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func markAllRead() async {
        do {
            unreadCount = try await api.markRead(notificationId: nil)
            let now = Date()
            for i in items.indices where items[i].readAt == nil {
                items[i].readAt = now
            }
            syncAppBadge()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Socket `notification.created` — prepend + bump badge (dedupe by id).
    func handleCreated(_ note: AppNotificationDTO) {
        if items.contains(where: { $0.id == note.id }) { return }
        if let mid = note.messageId, seenMessageIds.contains(mid) { return }
        if let sid = note.sessionId, seenSessionIds.contains(sid) {
            // Still show inbox row if missing, but don't double-bump call UX.
        }
        items.insert(note, at: 0)
        if note.isUnread { unreadCount += 1 }
        rememberDedupeKeys(from: [note])
        syncAppBadge()
    }

    // MARK: Preferences

    func loadPreferences() async {
        do {
            preferences = try await api.getPreferences()
            mirrorPreferencesToAppStorage()
            lastError = nil
        } catch {
            // Keep local defaults.
        }
    }

    func savePreferences(_ prefs: NotificationPreferencesDTO) async throws {
        preferences = try await api.putPreferences(prefs)
        mirrorPreferencesToAppStorage()
    }

    // MARK: Push token

    func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        guard hex.count >= 8 else { return }
        deviceTokenHex = hex
        Task { await registerTokenWithBackend(hex) }
    }

    func registerTokenWithBackend(_ token: String) async {
        guard TokenStore.accessToken() != nil else { return }
        do {
            _ = try await api.registerPushToken(token: token)
        } catch {
            // Soft fail — will retry on next start / token refresh.
        }
    }

    func unregisterCurrentToken() async {
        guard let token = deviceTokenHex else { return }
        try? await api.deletePushToken(token)
    }

    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        // Personal (free) Apple teams cannot use Push Notifications / aps-environment.
        // Registration is attempted when available; failure is ignored and inbox/socket still work.
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: Deep links

    /// Route push / inbox tap. Returns true if handled.
    @discardableResult
    func handleUserInfo(_ userInfo: [AnyHashable: Any], fromUserTap: Bool) -> Bool {
        let flat = Self.flatten(userInfo)
        let type = flat["type"] ?? (userInfo["type"] as? String)

        if type == "chat_call" || flat["sessionId"] != nil && (type == nil || type == "chat_call") {
            if let sid = flat["sessionId"], seenSessionIds.contains(sid), !fromUserTap {
                return true
            }
            if let sid = flat["sessionId"] { seenSessionIds.insert(sid) }
            NotificationCenter.default.post(name: .ttIncomingCallPush, object: nil, userInfo: flat)
            return true
        }

        if type == "chat" {
            if let mid = flat["messageId"], seenMessageIds.contains(mid), !fromUserTap {
                return true
            }
            if let mid = flat["messageId"] { seenMessageIds.insert(mid) }
            guard let threadId = flat["threadId"], !threadId.isEmpty else { return false }
            if fromUserTap {
                var info: [AnyHashable: Any] = ["threadId": threadId]
                if let mid = flat["messageId"] { info["messageId"] = mid }
                NotificationCenter.default.post(name: .ttOpenHumanChat, object: nil, userInfo: info)
            }
            return true
        }

        return false
    }

    func openNotification(_ note: AppNotificationDTO) {
        Task { await markRead(note) }
        switch note.type {
        case "chat_call":
            var info: [AnyHashable: Any] = ["type": "chat_call"]
            for (k, v) in note.data { info[k] = v }
            NotificationCenter.default.post(name: .ttIncomingCallPush, object: nil, userInfo: info)
        case "chat":
            guard let threadId = note.threadId else { return }
            var info: [AnyHashable: Any] = ["threadId": threadId]
            if let mid = note.messageId { info["messageId"] = mid }
            NotificationCenter.default.post(name: .ttOpenHumanChat, object: nil, userInfo: info)
        default:
            break
        }
    }

    // MARK: Helpers

    private func prependOrAppend(_ incoming: [AppNotificationDTO], prepend: Bool) {
        var seen = Set(items.map(\.id))
        let fresh = incoming.filter { seen.insert($0.id).inserted }
        if prepend {
            items.insert(contentsOf: fresh, at: 0)
        } else {
            items.append(contentsOf: fresh)
        }
        rememberDedupeKeys(from: fresh)
    }

    private func rememberDedupeKeys(from list: [AppNotificationDTO]) {
        for note in list {
            if let mid = note.messageId { seenMessageIds.insert(mid) }
            if let sid = note.sessionId { seenSessionIds.insert(sid) }
        }
    }

    private func syncAppBadge() {
        UNUserNotificationCenter.current().setBadgeCount(unreadCount) { _ in }
    }

    private func mirrorPreferencesToAppStorage() {
        let d = UserDefaults.standard
        d.set(preferences.push, forKey: "notifications.push")
        d.set(preferences.aiCoach, forKey: "notifications.aiCoach")
        d.set(preferences.metrics, forKey: "notifications.metrics")
        d.set(preferences.vibrations, forKey: "notifications.vibrations")
        d.set(preferences.sound, forKey: "notifications.sound")
        d.set(preferences.appUpdate, forKey: "notifications.appUpdate")
        d.set(preferences.resources, forKey: "notifications.resources")
        d.set(preferences.chatMessages, forKey: "notifications.chatMessages")
        d.set(preferences.chatCalls, forKey: "notifications.chatCalls")
    }

    static func flatten(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        func put(_ key: String, _ value: Any?) {
            guard let value else { return }
            if let s = value as? String { out[key] = s; return }
            if let n = value as? NSNumber { out[key] = n.stringValue; return }
        }
        for (k, v) in userInfo {
            let key = String(describing: k)
            if let nested = v as? [AnyHashable: Any] {
                for (nk, nv) in nested {
                    put(String(describing: nk), nv)
                }
            } else {
                put(key, v)
            }
        }
        // APS custom data often under `data`
        if let data = userInfo["data"] as? [AnyHashable: Any] {
            for (k, v) in data { put(String(describing: k), v) }
        }
        return out
    }
}

extension Notification.Name {
    /// Open human chat for `threadId` (and optional `messageId`).
    static let ttOpenHumanChat = Notification.Name("ttOpenHumanChat")
}
