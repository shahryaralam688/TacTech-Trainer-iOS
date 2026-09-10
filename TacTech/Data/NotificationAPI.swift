import Foundation
import UIKit

/// REST client for `/me/notifications`, `/me/push-tokens`, notification prefs.
actor NotificationAPI {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder.tactech
        encoder = JSONEncoder.tactech
    }

    // MARK: Inbox

    func listNotifications(cursor: String? = nil, limit: Int = 50) async throws -> AppNotificationPage {
        var path = "/me/notifications?limit=\(limit)"
        if let cursor, !cursor.isEmpty {
            let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
            path += "&cursor=\(encoded)"
        }
        let data = try await raw(path: path, method: .get, body: Optional<EmptyBody>.none, authorized: true)
        if let page = try? decoder.decode(AppNotificationPage.self, from: data) {
            return page
        }
        if let items = try? decoder.decode([AppNotificationDTO].self, from: data) {
            return AppNotificationPage(items: items, nextCursor: nil, unreadCount: items.filter(\.isUnread).count)
        }
        throw AppError.api("Could not decode notifications.")
    }

    func unreadCount() async throws -> Int {
        let out: NotificationUnreadCountOut = try await send(
            path: "/me/notifications/unread-count",
            method: .get,
            body: Optional<EmptyBody>.none
        )
        return out.unreadCount
    }

    /// Mark one notification read, or all when `notificationId` is nil.
    @discardableResult
    func markRead(notificationId: String? = nil) async throws -> Int {
        let out: NotificationUnreadCountOut = try await send(
            path: "/me/notifications/read",
            method: .post,
            body: NotificationReadRequest(notificationId: notificationId)
        )
        return out.unreadCount
    }

    // MARK: Preferences

    func getPreferences() async throws -> NotificationPreferencesDTO {
        try await send(path: "/me/preferences/notifications", method: .get, body: Optional<EmptyBody>.none)
    }

    func putPreferences(_ prefs: NotificationPreferencesDTO) async throws -> NotificationPreferencesDTO {
        try await send(path: "/me/preferences/notifications", method: .put, body: prefs)
    }

    // MARK: Push tokens

    @discardableResult
    func registerPushToken(
        token: String,
        deviceName: String? = UIDevice.current.name,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    ) async throws -> PushTokenOut {
        try await send(
            path: "/me/push-tokens",
            method: .post,
            body: PushTokenRegisterRequest(
                token: token,
                platform: "ios",
                deviceName: deviceName,
                appVersion: appVersion
            )
        )
    }

    func deletePushToken(_ token: String) async throws {
        _ = try await raw(
            path: "/me/push-tokens",
            method: .delete,
            body: PushTokenDeleteRequest(token: token),
            authorized: true
        )
    }

    // MARK: - Internals

    private struct EmptyBody: Encodable {}

    private func send<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B?) async throws -> T {
        let data = try await raw(path: path, method: method, body: body, authorized: true)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.api(Self.detail(from: data) ?? error.localizedDescription)
        }
    }

    private func raw<B: Encodable>(
        path: String,
        method: HTTPMethod,
        body: B?,
        authorized: Bool,
        allowRetry: Bool = true
    ) async throws -> Data {
        var request = try makeRequest(path: path, method: method, authorized: authorized)
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Invalid response from server.")
        }
        if http.statusCode == 401, allowRetry, authorized {
            try await refreshTokens()
            return try await raw(path: path, method: method, body: body, authorized: authorized, allowRetry: false)
        }
        try Self.throwMappedFailure(status: http.statusCode, data: data)
        return data
    }

    private func makeRequest(path: String, method: HTTPMethod, authorized: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        if method == .post || method == .put || method == .patch || method == .delete {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let token = TokenStore.accessToken() else { throw AppError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func refreshTokens() async throws {
        guard let refresh = TokenStore.refreshToken() else {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        struct RefreshBody: Encodable { var refreshToken: String }
        var request = try makeRequest(path: "/auth/refresh", method: .post, authorized: false)
        request.httpBody = try encoder.encode(RefreshBody(refreshToken: refresh))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        if let tokens = try? decoder.decode(TokenResponse.self, from: data) {
            TokenStore.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken ?? refresh)
            return
        }
        if let auth = try? decoder.decode(AuthResponse.self, from: data) {
            TokenStore.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken)
            return
        }
        TokenStore.clear()
        throw AppError.unauthorized
    }

    private static func throwMappedFailure(status: Int, data: Data) throws {
        if (200...299).contains(status) { return }
        let detail = detail(from: data)
        if status == 401 {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        throw AppError.api(detail ?? "Request failed (\(status)).")
    }

    private static func detail(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty { return detail }
            if let message = object["message"] as? String, !message.isEmpty { return message }
        }
        return nil
    }
}
