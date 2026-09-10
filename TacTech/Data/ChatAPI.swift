import Foundation
import UIKit

/// Trainer↔trainee human chat networking — REST `/chat/*` (not `/coach/*`).
actor ChatAPI {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder.tactech
        encoder = JSONEncoder.tactech
    }

    // MARK: Threads

    func listThreads() async throws -> [ChatThreadDTO] {
        let data = try await raw(path: "/chat/threads", method: .get, body: Optional<EmptyBody>.none, authorized: true)
        if data.isEmpty { return [] }
        if let wrapped = try? decoder.decode(ChatThreadsResponse.self, from: data) {
            return wrapped.items
        }
        if let items = try? decoder.decode([ChatThreadDTO].self, from: data) {
            return items
        }
        if let wrapped = try? decoder.decode(ListEnvelope<ChatThreadDTO>.self, from: data) {
            return wrapped.values
        }
        throw AppError.api("Could not decode chat threads.")
    }

    func createOrGetThread(
        peerUserId: String?,
        peerTraineeProfileId: String? = nil,
        peerTrainerProfileId: String? = nil
    ) async throws -> ChatThreadDTO {
        try await send(
            path: "/chat/threads",
            method: .post,
            body: ChatCreateThreadRequest(
                peerUserId: peerUserId,
                peerTraineeProfileId: peerTraineeProfileId,
                peerTrainerProfileId: peerTrainerProfileId
            )
        )
    }

    // MARK: Messages

    func listMessages(threadId: String, cursor: String? = nil, limit: Int = 50) async throws -> ChatMessagesResponse {
        var path = "/chat/threads/\(threadId)/messages?limit=\(limit)"
        if let cursor, !cursor.isEmpty {
            let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
            path += "&cursor=\(encoded)"
        }
        let data = try await raw(path: path, method: .get, body: Optional<EmptyBody>.none, authorized: true)
        if let page = try? decoder.decode(ChatMessagesResponse.self, from: data) {
            return page
        }
        if let items = try? decoder.decode([ChatMessageDTO].self, from: data) {
            return ChatMessagesResponse(items: items, nextCursor: nil)
        }
        throw AppError.api("Could not decode chat messages.")
    }

    func sendText(threadId: String, text: String, clientId: String) async throws -> ChatMessageDTO {
        try await send(
            path: "/chat/threads/\(threadId)/messages",
            method: .post,
            body: ChatSendTextRequest(text: text, clientId: clientId)
        )
    }

    func sendCallEvent(threadId: String, outcome: String, clientId: String) async throws -> ChatMessageDTO {
        try await send(
            path: "/chat/threads/\(threadId)/messages",
            method: .post,
            body: ChatCallEventRequest(callOutcome: outcome, clientId: clientId)
        )
    }

    func sendMedia(
        threadId: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        attachmentType: String,
        caption: String?,
        durationSeconds: Double?,
        clientId: String
    ) async throws -> ChatMessageDTO {
        var fields: [MultipartFormField] = [
            .file(name: "file", filename: filename, mimeType: mimeType, data: fileData),
            .text(name: "attachmentType", value: attachmentType),
            .text(name: "clientId", value: clientId)
        ]
        if let caption, !caption.isEmpty {
            fields.append(.text(name: "text", value: caption))
        }
        if let durationSeconds {
            fields.append(.text(name: "durationSeconds", value: String(durationSeconds)))
        }
        return try await sendMultipart(path: "/chat/threads/\(threadId)/messages", fields: fields)
    }

    func markRead(threadId: String, upToMessageId: String) async throws -> ChatReadResponse {
        try await send(
            path: "/chat/threads/\(threadId)/read",
            method: .post,
            body: ChatReadRequest(upToMessageId: upToMessageId)
        )
    }

    // MARK: RTC (human call — separate from /coach/rtc)

    func createRtcSession(threadId: String) async throws -> ChatRtcSessionDTO {
        try await send(path: "/chat/rtc/sessions", method: .post, body: ChatCreateRtcRequest(threadId: threadId))
    }

    /// Active ringing sessions for the current user (works even outside chat UI).
    func listIncomingCalls() async throws -> [ChatIncomingCallDTO] {
        let data = try await raw(path: "/chat/rtc/incoming", method: .get, body: Optional<EmptyBody>.none, authorized: true)
        if data.isEmpty { return [] }
        if let wrapped = try? decoder.decode(ChatIncomingCallsResponse.self, from: data) {
            return wrapped.items
        }
        if let items = try? decoder.decode([ChatIncomingCallDTO].self, from: data) {
            return items
        }
        return []
    }

    // MARK: - Internals

    private enum MultipartFormField {
        case text(name: String, value: String)
        case file(name: String, filename: String, mimeType: String, data: Data)
    }

    private func sendMultipart<T: Decodable>(path: String, fields: [MultipartFormField], allowRetry: Bool = true) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(path: path, method: .post, authorized: true, jsonContentType: false)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(fields: fields, boundary: boundary)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Invalid response from server.")
        }
        if http.statusCode == 401, allowRetry {
            try await refreshTokens()
            return try await sendMultipart(path: path, fields: fields, allowRetry: false)
        }
        try Self.throwMappedFailure(status: http.statusCode, data: data, response: http)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.api(Self.detail(from: data) ?? error.localizedDescription)
        }
    }

    private func buildMultipartBody(fields: [MultipartFormField], boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        for field in fields {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            switch field {
            case let .text(name, value):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
                body.append("\(value)\(crlf)".data(using: .utf8)!)
            case let .file(name, filename, mimeType, data):
                body.append(
                    "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!
                )
                body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
                body.append(data)
                body.append(crlf.data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    private func send<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B) async throws -> T {
        let data = try await raw(path: path, method: method, body: body, authorized: true)
        return try decode(T.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
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
        try Self.throwMappedFailure(status: http.statusCode, data: data, response: http)
        return data
    }

    private func makeRequest(
        path: String,
        method: HTTPMethod,
        authorized: Bool,
        jsonContentType: Bool = true
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        if jsonContentType, method == .post || method == .put || method == .patch || method == .delete {
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

    private static func throwMappedFailure(status: Int, data: Data, response: HTTPURLResponse) throws {
        if (200...299).contains(status) { return }
        let detail = detail(from: data)
        let code = code(from: data)
        if status == 401 {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        if status == 404 {
            throw AppError.notFound(detail ?? "Not found.")
        }
        if status == 429 || code == "RATE_LIMITED" {
            let retryAfter = retryAfterSeconds(from: response) ?? 25
            throw AppError.rateLimited(
                detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "Too many requests. Please wait a moment.",
                retryAfter: retryAfter
            )
        }
        throw AppError.api(
            detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Request failed (\(status))."
        )
    }

    private static func code(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["code"] as? String
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        if let value = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(value) {
            return max(5, min(seconds, 120))
        }
        return nil
    }

    private static func detail(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty { return detail }
            if let detail = object["detail"] as? [String: Any] {
                if let msg = detail["msg"] as? String, !msg.isEmpty { return msg }
                if let message = detail["message"] as? String, !message.isEmpty { return message }
            }
            if let detail = object["detail"] as? [[String: Any]] {
                let messages = detail.compactMap { $0["msg"] as? String }.filter { !$0.isEmpty }
                if !messages.isEmpty { return messages.joined(separator: " ") }
            }
            if let message = object["message"] as? String, !message.isEmpty { return message }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
