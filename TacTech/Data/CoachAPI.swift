import Foundation
import UIKit

/// AI Coach networking — SSE chat, multipart image/voice, RTC session bootstrap.
actor CoachAPI {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder.tactech
        encoder = JSONEncoder.tactech
    }

    // MARK: Status / memory

    func status() async throws -> CoachProviderStatus {
        try await send(path: "/coach/status", method: .get)
    }

    func syncMemory() async throws -> CoachMemorySyncResult {
        try await send(path: "/coach/memory/sync", method: .post, body: EmptyBody())
    }

    // MARK: Conversations

    func listConversations() async throws -> [CoachConversation] {
        try await sendArray("/coach/conversations")
    }

    func createConversation() async throws -> CoachConversation {
        try await send(path: "/coach/conversations", method: .post, body: EmptyBody())
    }

    func listMessages(conversationId: String) async throws -> [CoachMessage] {
        try await sendArray("/coach/conversations/\(conversationId)/messages")
    }

    // MARK: Text chat (non-stream)

    func chat(message: String, conversationId: String?, stream: Bool = false) async throws -> CoachChatResponse {
        try await send(
            path: "/coach/chat",
            method: .post,
            body: CoachChatRequest(message: message, conversationId: conversationId, stream: false)
        )
    }

    // MARK: Streaming chat (SSE)

    /// Yields parsed SSE events. Cancelling the calling Task cancels the stream.
    func chatStream(
        message: String,
        conversationId: String?
    ) -> AsyncThrowingStream<CoachStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(path: "/coach/chat", method: .post, authorized: true)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try encoder.encode(
                        CoachChatRequest(message: message, conversationId: conversationId, stream: true)
                    )
                    request.timeoutInterval = 180

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AppError.api("Invalid stream response.")
                    }
                    if http.statusCode == 401 {
                        try await refreshTokens()
                        var retry = try makeRequest(path: "/coach/chat", method: .post, authorized: true)
                        retry.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        retry.httpBody = request.httpBody
                        retry.timeoutInterval = 180
                        let (retryBytes, retryResponse) = try await session.bytes(for: retry)
                        guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                            throw AppError.api("Invalid stream response.")
                        }
                        try await throwIfHTTPFailed(status: retryHTTP.statusCode, bytes: retryBytes, response: retryHTTP)
                        try await consumeSSE(bytes: retryBytes, continuation: continuation)
                        continuation.finish()
                        return
                    }
                    try await throwIfHTTPFailed(status: http.statusCode, bytes: bytes, response: http)
                    try await consumeSSE(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads a small error body from a failed streaming response, then throws.
    private func throwIfHTTPFailed(
        status: Int,
        bytes: URLSession.AsyncBytes,
        response: HTTPURLResponse
    ) async throws {
        if (200...299).contains(status) { return }
        var errorData = Data()
        do {
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count >= 8_192 { break }
            }
        } catch {
            // Still map from status / whatever we collected.
        }
        try Self.throwMappedFailure(status: status, data: errorData, response: response)
    }

    private func consumeSSE(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<CoachStreamEvent, Error>.Continuation
    ) async throws {
        var dataBuffer = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload.isEmpty || payload == "[DONE]" { continue }
                dataBuffer = payload
                if let event = parseStreamEvent(dataBuffer) {
                    continuation.yield(event)
                }
                dataBuffer = ""
            } else if line.isEmpty {
                continue
            } else if !line.hasPrefix(":") {
                // Some proxies send bare JSON lines
                if let event = parseStreamEvent(line) {
                    continuation.yield(event)
                }
            }
        }
    }

    private func parseStreamEvent(_ raw: String) -> CoachStreamEvent? {
        guard let data = raw.data(using: .utf8),
              let dto = try? decoder.decode(CoachStreamEventDTO.self, from: data) else {
            return nil
        }
        switch dto.event {
        case "user":
            guard let message = dto.message else { return .unknown }
            return .user(conversationId: dto.conversationId ?? message.conversationId, message: message)
        case "delta":
            return .delta(dto.text ?? "")
        case "done":
            guard let message = dto.message else { return .unknown }
            return .done(message: message, citations: dto.citations)
        default:
            return .unknown
        }
    }

    // MARK: Image chat

    func chatImage(
        imageData: Data,
        filename: String = "coach.jpg",
        mimeType: String = "image/jpeg",
        caption: String?,
        conversationId: String?
    ) async throws -> CoachImageChatResponse {
        var fields: [MultipartFormField] = [
            .file(name: "image", filename: filename, mimeType: mimeType, data: imageData)
        ]
        if let caption, !caption.isEmpty {
            fields.append(.text(name: "message", value: caption))
        }
        if let conversationId, !conversationId.isEmpty {
            fields.append(.text(name: "conversation_id", value: conversationId))
        }
        return try await sendMultipart(path: "/coach/chat/image", fields: fields)
    }

    // MARK: Voice

    func voiceTurn(
        audioData: Data,
        filename: String = "turn.m4a",
        mimeType: String = "audio/m4a",
        conversationId: String?,
        speak: Bool = true
    ) async throws -> CoachVoiceTurnResponse {
        var fields: [MultipartFormField] = [
            .file(name: "audio", filename: filename, mimeType: mimeType, data: audioData),
            .text(name: "speak", value: speak ? "true" : "false")
        ]
        if let conversationId, !conversationId.isEmpty {
            fields.append(.text(name: "conversation_id", value: conversationId))
        }
        return try await sendMultipart(path: "/coach/voice/turn", fields: fields)
    }

    // MARK: WebRTC

    func iceServers() async throws -> [CoachRtcIceServer] {
        try await sendArray("/coach/rtc/ice-servers")
    }

    func createRtcSession(conversationId: String?) async throws -> CoachRtcSession {
        var path = "/coach/rtc/sessions"
        if let conversationId, !conversationId.isEmpty {
            let encoded = conversationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? conversationId
            path += "?conversationId=\(encoded)"
        }
        return try await send(path: path, method: .post, body: EmptyBody())
    }

    // MARK: - Internals

    private enum MultipartFormField {
        case text(name: String, value: String)
        case file(name: String, filename: String, mimeType: String, data: Data)
    }

    private func sendMultipart<T: Decodable>(path: String, fields: [MultipartFormField], allowRetry: Bool = true) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(path: path, method: .post, authorized: true)
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

    private func sendArray<T: Decodable>(_ path: String) async throws -> [T] {
        let data = try await raw(path: path, method: .get, body: Optional<EmptyBody>.none, authorized: true)
        if data.isEmpty { return [] }
        if let items = try? decoder.decode([T].self, from: data) { return items }
        if let wrapped = try? decoder.decode(ListEnvelope<T>.self, from: data) {
            return wrapped.values
        }
        throw AppError.api("Could not decode \(T.self) list.")
    }

    private func send<T: Decodable>(path: String, method: HTTPMethod) async throws -> T {
        let data = try await raw(path: path, method: method, body: Optional<EmptyBody>.none, authorized: true)
        return try decode(T.self, from: data)
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
        if let body, method != .get {
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Invalid response from server.")
        }
        if http.statusCode == 401, authorized, allowRetry {
            try await refreshTokens()
            return try await raw(path: path, method: method, body: body, authorized: authorized, allowRetry: false)
        }
        try Self.throwMappedFailure(status: http.statusCode, data: data, response: http)
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
        if method == .post || method == .patch {
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

    /// Maps HTTP failures to `AppError`, preferring server `detail` and handling 429 / RATE_LIMITED.
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
            let message = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Too many AI requests. Please wait a moment."
            throw AppError.rateLimited(message, retryAfter: retryAfter)
        }
        throw AppError.api(detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                           ?? "Request failed (\(status)).")
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

// MARK: - JPEG encoding (HEIC / Live Photos → JPEG)

enum CoachImageEncoder {
    /// Compress to JPEG, longest side ≤ `maxSide`, quality 0.7–0.85. Caps ~5MB.
    static func jpegData(
        from image: UIImage,
        maxSide: CGFloat = 1600,
        quality: CGFloat = 0.78
    ) -> Data? {
        let resized = resize(image, maxSide: maxSide)
        var q = quality
        var data = resized.jpegData(compressionQuality: q)
        let maxBytes = 5 * 1024 * 1024
        while let current = data, current.count > maxBytes, q > 0.45 {
            q -= 0.08
            data = resized.jpegData(compressionQuality: q)
        }
        return data
    }

    static func jpegData(from pickerData: Data) -> Data? {
        guard let image = UIImage(data: pickerData) else { return nil }
        return jpegData(from: image)
    }

    private static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
