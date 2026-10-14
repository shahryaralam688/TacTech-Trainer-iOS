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
    /// Keepalive socket so home badge updates even when chat/call UI is closed.
    /// (HumanCallStore monitoring is gated by `HumanCallFeatures.isEnabled`.)
    private let realtime = ChatRealtimeClient()
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
        startRealtimeKeepalive()
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
        realtime.disconnect()
        items = []
        unreadCount = 0
        nextCursor = nil
        seenMessageIds.removeAll()
        seenSessionIds.removeAll()
    }

    private func startRealtimeKeepalive() {
        realtime.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .notificationCreated(let note):
                self.handleCreated(note)
                if note.type == "chat_call" {
                    var info: [AnyHashable: Any] = ["type": "chat_call"]
                    for (k, v) in note.data { info[k] = v }
                    _ = self.handleUserInfo(info, fromUserTap: false)
                }
                let type = note.type.lowercased()
                if type.hasPrefix("join_request") {
                    NotificationCenter.default.post(
                        name: .ttJoinRequestRealtime,
                        object: nil,
                        userInfo: ["type": note.type]
                    )
                }
                if type == "relationship_ended" {
                    Self.postRelationshipChanged(
                        action: "unlinked",
                        reason: note.data["reason"],
                        trainerUserId: note.data["trainerUserId"] ?? note.data["trainer_user_id"],
                        traineeUserId: note.data["traineeUserId"] ?? note.data["trainee_user_id"],
                        traineeProfileId: note.data["traineeProfileId"]
                            ?? note.data["trainee_profile_id"]
                            ?? note.data["traineeId"]
                    )
                }
                if type == "plan_assigned" || type == "plan_unassigned" || type == "plan_updated" {
                    Self.postPlanAssignmentChanged(
                        action: type,
                        planId: note.data["planId"] ?? note.data["plan_id"],
                        planTitle: note.data["planTitle"] ?? note.data["plan_title"] ?? note.data["title"]
                    )
                }
            case let .relationshipChanged(action, reason, trainerUserId, traineeUserId, traineeProfileId):
                Self.postRelationshipChanged(
                    action: action,
                    reason: reason,
                    trainerUserId: trainerUserId,
                    traineeUserId: traineeUserId,
                    traineeProfileId: traineeProfileId
                )
            case let .planAssignmentChanged(action, planId, planTitle, _, _, _):
                Self.postPlanAssignmentChanged(
                    action: action,
                    planId: planId,
                    planTitle: planTitle
                )
            default:
                break
            }
        }
        realtime.connect()
    }

    static func postRelationshipChanged(
        action: String,
        reason: String?,
        trainerUserId: String?,
        traineeUserId: String?,
        traineeProfileId: String?
    ) {
        var info: [AnyHashable: Any] = ["action": action]
        if let reason, !reason.isEmpty { info["reason"] = reason }
        if let trainerUserId, !trainerUserId.isEmpty { info["trainerUserId"] = trainerUserId }
        if let traineeUserId, !traineeUserId.isEmpty { info["traineeUserId"] = traineeUserId }
        if let traineeProfileId, !traineeProfileId.isEmpty { info["traineeProfileId"] = traineeProfileId }
        NotificationCenter.default.post(name: .ttRelationshipChanged, object: nil, userInfo: info)
    }

    static func postPlanAssignmentChanged(
        action: String,
        planId: String?,
        planTitle: String?
    ) {
        var info: [AnyHashable: Any] = ["action": action]
        if let planId, !planId.isEmpty { info["planId"] = planId }
        if let planTitle, !planTitle.isEmpty { info["planTitle"] = planTitle }
        NotificationCenter.default.post(name: .ttPlanAssignmentChanged, object: nil, userInfo: info)
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

    func delete(_ notification: AppNotificationDTO) async {
        await deleteMany([notification.id])
    }

    /// Bulk delete by id. Keeps local removal even if the server call soft-fails
    /// (except unauthorized), so inbox UX stays responsive for trainer + trainee.
    func deleteMany(_ ids: [String]) async {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return }

        let idSet = Set(unique)
        let removed = items.filter { idSet.contains($0.id) }
        guard !removed.isEmpty else { return }

        let unreadRemoved = removed.filter(\.isUnread).count
        items.removeAll { idSet.contains($0.id) }
        unreadCount = max(0, unreadCount - unreadRemoved)
        syncAppBadge()

        var firstError: String?
        var mustRestore = false
        for note in removed {
            do {
                let count = try await api.deleteNotifications(notificationId: note.id)
                unreadCount = count
            } catch {
                if Self.shouldRestoreInbox(after: error) {
                    mustRestore = true
                    firstError = Self.deleteFailureMessage(error)
                    break
                }
                if firstError == nil {
                    firstError = error.localizedDescription
                }
            }
        }
        if mustRestore {
            items = (removed + items).sorted { $0.createdAt > $1.createdAt }
            unreadCount += unreadRemoved
        }
        syncAppBadge()
        lastError = firstError
    }

    func clearAll() async {
        let snapshot = items
        let previousUnread = unreadCount
        items = []
        nextCursor = nil
        unreadCount = 0
        syncAppBadge()
        do {
            unreadCount = try await api.deleteNotifications(notificationId: nil)
            syncAppBadge()
            lastError = nil
        } catch {
            if Self.shouldRestoreInbox(after: error) {
                items = snapshot
                unreadCount = previousUnread
                syncAppBadge()
            }
            lastError = Self.deleteFailureMessage(error)
        }
    }

    /// 404 means the delete route is missing on the server — restore local inbox.
    private static func shouldRestoreInbox(after error: Error) -> Bool {
        if let appError = error as? AppError {
            switch appError {
            case .unauthorized, .notFound:
                return true
            case .api(let message):
                return message.localizedCaseInsensitiveContains("not found")
            default:
                return false
            }
        }
        return false
    }

    private static func deleteFailureMessage(_ error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .notFound, .api:
                let text = appError.localizedDescription
                if text.localizedCaseInsensitiveContains("not found") {
                    return "Server delete API missing (404). Backend needs POST /me/notifications/delete."
                }
                return text
            default:
                break
            }
        }
        return error.localizedDescription
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

        // Remote APNs only when Push capability / remote-notification background mode is present.
        // Foreground inbox still updates via socket keepalive (above).
        guard Self.isRemotePushRegistrationEnabled else { return }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Safe default: off until Push entitlement / `remote-notification` background mode exists.
    /// Override for QA: `UserDefaults.standard.set(true, forKey: "tt.forceRemotePushRegistration")`.
    private static var isRemotePushRegistrationEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "tt.forceRemotePushRegistration") {
            return true
        }
        #endif
        if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
           modes.contains("remote-notification") {
            return true
        }
        // Explicit opt-in for paid-team builds that added Push but not yet UIBackgroundModes.
        return UserDefaults.standard.bool(forKey: "tt.enableRemotePushRegistration")
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

        if type == "relationship_ended" {
            if fromUserTap {
                NotificationCenter.default.post(name: .ttOpenRelationshipEnded, object: nil)
            }
            Self.postRelationshipChanged(
                action: "unlinked",
                reason: flat["reason"],
                trainerUserId: flat["trainerUserId"] ?? flat["trainer_user_id"],
                traineeUserId: flat["traineeUserId"] ?? flat["trainee_user_id"],
                traineeProfileId: flat["traineeProfileId"] ?? flat["trainee_profile_id"] ?? flat["traineeId"]
            )
            return true
        }

        if type == "plan_assigned" || type == "plan_unassigned" || type == "plan_updated" {
            if fromUserTap {
                NotificationCenter.default.post(name: .ttOpenWorkoutHub, object: nil)
            }
            Self.postPlanAssignmentChanged(
                action: type ?? "plan_updated",
                planId: flat["planId"] ?? flat["plan_id"],
                planTitle: flat["planTitle"] ?? flat["plan_title"] ?? flat["title"]
            )
            return true
        }

        return false
    }

    func openNotification(_ note: AppNotificationDTO) {
        Task { await markRead(note) }
        switch note.type.lowercased() {
        case "chat_call":
            var info: [AnyHashable: Any] = ["type": "chat_call"]
            for (k, v) in note.data { info[k] = v }
            NotificationCenter.default.post(name: .ttIncomingCallPush, object: nil, userInfo: info)
        case "chat":
            guard let threadId = note.threadId else { return }
            var info: [AnyHashable: Any] = ["threadId": threadId]
            if let mid = note.messageId { info["messageId"] = mid }
            NotificationCenter.default.post(name: .ttOpenHumanChat, object: nil, userInfo: info)
        case "join_request":
            NotificationCenter.default.post(name: .ttOpenJoinRequests, object: nil)
        case "join_request_accepted":
            NotificationCenter.default.post(name: .ttOpenTraineeProfile, object: nil)
        case "join_request_rejected":
            NotificationCenter.default.post(name: .ttOpenTraineeProfileJoin, object: nil)
        case "relationship_ended":
            // Trainer → My Trainees; Trainee → Profile join card (Roots filter by role).
            NotificationCenter.default.post(name: .ttOpenRelationshipEnded, object: nil)
            Self.postRelationshipChanged(
                action: "unlinked",
                reason: note.data["reason"],
                trainerUserId: note.data["trainerUserId"] ?? note.data["trainer_user_id"],
                traineeUserId: note.data["traineeUserId"] ?? note.data["trainee_user_id"],
                traineeProfileId: note.data["traineeProfileId"]
                    ?? note.data["trainee_profile_id"]
                    ?? note.data["traineeId"]
            )
        case "plan_assigned", "plan_unassigned", "plan_updated":
            NotificationCenter.default.post(name: .ttOpenWorkoutHub, object: nil)
            Self.postPlanAssignmentChanged(
                action: note.type,
                planId: note.data["planId"] ?? note.data["plan_id"],
                planTitle: note.data["planTitle"] ?? note.data["plan_title"] ?? note.data["title"]
            )
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
    /// Trainer: open Join Requests list.
    static let ttOpenJoinRequests = Notification.Name("ttOpenJoinRequests")
    /// Trainee: open Profile (My Trainer after accept).
    static let ttOpenTraineeProfile = Notification.Name("ttOpenTraineeProfile")
    /// Trainee: open Profile join card (after reject).
    static let ttOpenTraineeProfileJoin = Notification.Name("ttOpenTraineeProfileJoin")
    /// Socket / inbox: `join_request*` — refresh join lists / My Trainer.
    static let ttJoinRequestRealtime = Notification.Name("ttJoinRequestRealtime")
    /// Socket `relationship.changed` / inbox `relationship_ended` — roster & My Trainer sync.
    static let ttRelationshipChanged = Notification.Name("ttRelationshipChanged")
    /// Tap: Trainer → My Trainees; Trainee → Profile.
    static let ttOpenRelationshipEnded = Notification.Name("ttOpenRelationshipEnded")
    /// Socket `plan.assignment.changed` / inbox `plan_*` — live assigned-plan sync.
    static let ttPlanAssignmentChanged = Notification.Name("ttPlanAssignmentChanged")
    /// Trainee: open Workout tab / hub.
    static let ttOpenWorkoutHub = Notification.Name("ttOpenWorkoutHub")
    /// Boost checkout finished successfully (confirm + refresh done).
    static let ttBoostCheckoutSucceeded = Notification.Name("ttBoostCheckoutSucceeded")
    /// Boost checkout canceled by user / cancel deep link.
    static let ttBoostCheckoutCanceled = Notification.Name("ttBoostCheckoutCanceled")
    /// Boost confirm failed after deep link — `userInfo["detail"]`.
    static let ttBoostCheckoutFailed = Notification.Name("ttBoostCheckoutFailed")
    /// Coach generate hit 402 — present AI paywall (trainee).
    static let ttPresentAIPaywall = Notification.Name("ttPresentAIPaywall")
    /// Paywall purchase/restore unlocked AI — coach may retry pending send.
    static let ttAIPaywallUnlocked = Notification.Name("ttAIPaywallUnlocked")
    /// StoreKit `Transaction.updates` verified — refresh UI.
    static let ttAIEntitlementDidChange = Notification.Name("ttAIEntitlementDidChange")
    /// Workout logged / Boost confirmed — Profile Sandow chart should reload.
    static let ttSandowScoreShouldRefresh = Notification.Name("ttSandowScoreShouldRefresh")
}
