import Foundation

/// Lightweight Socket.IO client for namespace `/chat` (Engine.IO v4 over WebSocket).
/// Store still polls REST if this disconnects.
@MainActor
final class ChatRealtimeClient {
    enum Event {
        case message(ChatMessageDTO)
        case threadUpdated(ChatThreadDTO)
        case read(threadId: String, upToMessageId: String, readerUserId: String)
        case typing(threadId: String, userId: String, isTyping: Bool)
        case callIncoming(threadId: String, sessionId: String, fromUserId: String, fromName: String?)
        case callEnded(threadId: String, sessionId: String, reason: String?)
    }

    var onEvent: ((Event) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveLoopRunning = false
    private var joinedThreadId: String?
    private var pingTask: Task<Void, Never>?

    func connect() {
        disconnect()
        guard let token = TokenStore.accessToken() else { return }

        var components = URLComponents()
        components.scheme = APIConfig.baseURL.scheme == "https" ? "wss" : "ws"
        components.host = APIConfig.baseURL.host
        components.port = APIConfig.baseURL.port
        components.path = "/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket")
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ws = URLSession.shared.webSocketTask(with: request)
        task = ws
        ws.resume()
        receiveLoopRunning = true
        Task { await receiveLoop() }
        // Escape token for JSON string
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        sendRaw("40/chat,{\"token\":\"\(escaped)\"}")
    }

    func disconnect() {
        receiveLoopRunning = false
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        joinedThreadId = nil
    }

    func join(threadId: String) {
        joinedThreadId = threadId
        emit(event: "chat.join", payload: ["threadId": threadId])
    }

    func leave(threadId: String) {
        emit(event: "chat.leave", payload: ["threadId": threadId])
        if joinedThreadId == threadId { joinedThreadId = nil }
    }

    func setTyping(threadId: String, isTyping: Bool) {
        emit(event: "chat.typing", payload: ["threadId": threadId, "isTyping": isTyping])
    }

    private func emit(event: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: [event, payload]),
              let json = String(data: data, encoding: .utf8) else { return }
        sendRaw("42/chat," + json)
    }

    private func sendRaw(_ text: String) {
        task?.send(.string(text)) { _ in }
    }

    private func receiveLoop() async {
        while receiveLoopRunning, let task {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handlePacket(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handlePacket(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                receiveLoopRunning = false
                break
            }
        }
    }

    private func handlePacket(_ text: String) {
        if text == "2" {
            sendRaw("3")
            return
        }
        if text.hasPrefix("0") {
            schedulePing()
            return
        }
        guard let payload = extractEventPayload(text) else { return }
        parseEvent(payload)
    }

    private func extractEventPayload(_ text: String) -> String? {
        if let range = text.range(of: "42/chat,") {
            return String(text[range.upperBound...])
        }
        if let range = text.range(of: "42,") {
            return String(text[range.upperBound...])
        }
        return nil
    }

    private func parseEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let name = array.first as? String else { return }
        let body = array.count > 1 ? array[1] : nil
        let decoder = JSONDecoder.tactech

        switch name {
        case "chat.message":
            if let dict = body as? [String: Any],
               let msgData = try? JSONSerialization.data(withJSONObject: dict),
               let dto = try? decoder.decode(ChatMessageDTO.self, from: msgData) {
                onEvent?(.message(dto))
            }
        case "chat.thread.updated":
            if let dict = body as? [String: Any],
               let msgData = try? JSONSerialization.data(withJSONObject: dict),
               let dto = try? decoder.decode(ChatThreadDTO.self, from: msgData) {
                onEvent?(.threadUpdated(dto))
            }
        case "chat.read":
            if let dict = body as? [String: Any],
               let threadId = dict["threadId"] as? String,
               let upTo = dict["upToMessageId"] as? String,
               let reader = dict["readerUserId"] as? String {
                onEvent?(.read(threadId: threadId, upToMessageId: upTo, readerUserId: reader))
            }
        case "chat.typing":
            if let dict = body as? [String: Any],
               let threadId = dict["threadId"] as? String,
               let userId = dict["userId"] as? String {
                let typing = dict["isTyping"] as? Bool ?? false
                onEvent?(.typing(threadId: threadId, userId: userId, isTyping: typing))
            }
        case "chat.call.incoming":
            if let dict = body as? [String: Any],
               let threadId = dict["threadId"] as? String,
               let sessionId = dict["sessionId"] as? String,
               let from = dict["fromUserId"] as? String {
                onEvent?(.callIncoming(
                    threadId: threadId,
                    sessionId: sessionId,
                    fromUserId: from,
                    fromName: dict["fromName"] as? String
                ))
            }
        case "chat.call.ended":
            if let dict = body as? [String: Any],
               let threadId = dict["threadId"] as? String,
               let sessionId = dict["sessionId"] as? String {
                onEvent?(.callEnded(
                    threadId: threadId,
                    sessionId: sessionId,
                    reason: dict["reason"] as? String
                ))
            }
        default:
            break
        }
    }

    private func schedulePing() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.sendRaw("2")
            }
        }
    }
}
