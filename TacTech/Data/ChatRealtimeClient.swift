import Foundation

/// Socket.IO client for TacTech chat + call events.
/// Connects Engine.IO, then auth on default `/` and namespace `/chat`
/// (backend places the user in personal room `user:{userId}` — call events do not require a thread join).
@MainActor
final class ChatRealtimeClient {
    enum Event {
        case message(ChatMessageDTO)
        case threadUpdated(ChatThreadDTO)
        case read(threadId: String, upToMessageId: String, readerUserId: String)
        case typing(threadId: String, userId: String, isTyping: Bool)
        case callIncoming(threadId: String, sessionId: String, fromUserId: String, fromName: String?, signalingPath: String?)
        case callEnded(threadId: String, sessionId: String, reason: String?)
    }

    var onEvent: ((Event) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private(set) var isConnected = false
    private var task: URLSessionWebSocketTask?
    private var receiveLoopRunning = false
    private var joinedThreadId: String?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var shouldRun = false
    private var defaultReady = false
    private var chatReady = false
    private var authToken: String?

    func connect() {
        shouldRun = true
        reconnectTask?.cancel()
        disconnectSocketOnly()
        guard let token = TokenStore.accessToken() else { return }
        authToken = token
        openSocket(token: token)
    }

    func disconnect() {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil
        disconnectSocketOnly()
    }

    func join(threadId: String) {
        joinedThreadId = threadId
        emitChat(event: "chat.join", payload: ["threadId": threadId])
    }

    func leave(threadId: String) {
        emitChat(event: "chat.leave", payload: ["threadId": threadId])
        if joinedThreadId == threadId { joinedThreadId = nil }
    }

    func setTyping(threadId: String, isTyping: Bool) {
        emitChat(event: "chat.typing", payload: ["threadId": threadId, "isTyping": isTyping])
    }

    // MARK: - Socket

    private func openSocket(token: String) {
        var components = URLComponents()
        components.scheme = APIConfig.baseURL.scheme == "https" ? "wss" : "ws"
        components.host = APIConfig.baseURL.host
        components.port = APIConfig.baseURL.port
        components.path = "/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
            URLQueryItem(name: "token", value: token)
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ws = URLSession.shared.webSocketTask(with: request)
        task = ws
        defaultReady = false
        chatReady = false
        receiveLoopRunning = true
        ws.resume()
        Task { await receiveLoop() }
    }

    private func disconnectSocketOnly() {
        receiveLoopRunning = false
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        defaultReady = false
        chatReady = false
        setConnected(false)
    }

    private func connectNamespaces() {
        guard let token = authToken ?? TokenStore.accessToken() else { return }
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let authJSON = "{\"token\":\"\(escaped)\",\"auth\":{\"token\":\"\(escaped)\"}}"
        // Default `/` — personal room `user:{id}` for call ringing without thread join.
        sendRaw("40" + authJSON)
        // Also join `/chat` for messaging + same call events if backend emits there.
        sendRaw("40/chat," + authJSON)
    }

    private func emitChat(event: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: [event, payload]),
              let json = String(data: data, encoding: .utf8) else { return }
        if chatReady {
            sendRaw("42/chat," + json)
        } else if defaultReady {
            sendRaw("42," + json)
        }
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
                setConnected(false)
                scheduleReconnect()
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
            connectNamespaces()
            return
        }
        // Default namespace connected
        if text == "40" || (text.hasPrefix("40{") || text.hasPrefix("40,")) && !text.hasPrefix("40/") {
            defaultReady = true
            refreshConnected()
            return
        }
        // /chat namespace connected
        if text == "40/chat" || text.hasPrefix("40/chat,") || text.hasPrefix("40/chat{") {
            chatReady = true
            refreshConnected()
            if let joinedThreadId {
                emitChat(event: "chat.join", payload: ["threadId": joinedThreadId])
            }
            return
        }
        if text.hasPrefix("44") || text.hasPrefix("41") {
            // One namespace failed — keep the other if ready.
            if !defaultReady && !chatReady {
                setConnected(false)
                scheduleReconnect()
            }
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
                if let invite = CallInviteCodec.parse(fromMessage: dto) {
                    onEvent?(.callIncoming(
                        threadId: invite.threadId,
                        sessionId: invite.sessionId,
                        fromUserId: dto.senderUserId,
                        fromName: invite.fromName,
                        signalingPath: invite.signalingPath
                    ))
                }
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
            if let dict = body as? [String: Any] {
                let threadId = (dict["threadId"] as? String) ?? ""
                let sessionId = (dict["sessionId"] as? String) ?? (dict["id"] as? String) ?? ""
                let from = (dict["fromUserId"] as? String) ?? (dict["callerUserId"] as? String) ?? ""
                guard !threadId.isEmpty, !sessionId.isEmpty, !from.isEmpty else { return }
                onEvent?(.callIncoming(
                    threadId: threadId,
                    sessionId: sessionId,
                    fromUserId: from,
                    fromName: dict["fromName"] as? String,
                    signalingPath: dict["signalingPath"] as? String
                ))
            }
        case "chat.call.ended":
            if let dict = body as? [String: Any],
               let threadId = dict["threadId"] as? String,
               let sessionId = (dict["sessionId"] as? String) ?? (dict["id"] as? String) {
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

    private func scheduleReconnect() {
        guard shouldRun else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.shouldRun else { return }
            self.connect()
        }
    }

    private func refreshConnected() {
        setConnected(defaultReady || chatReady)
    }

    private func setConnected(_ value: Bool) {
        guard isConnected != value else { return }
        isConnected = value
        onConnectionChange?(value)
    }
}

// MARK: - Call invite codec (legacy REST message fallback)

enum CallInviteCodec {
    static let prefix = "__tactech_call_invite__"

    struct Invite {
        let sessionId: String
        let threadId: String
        let fromName: String?
        let signalingPath: String?
    }

    static func encode(sessionId: String, threadId: String, fromName: String, signalingPath: String) -> String {
        let safeName = fromName.replacingOccurrences(of: "|", with: "/")
        return "\(prefix)|\(sessionId)|\(threadId)|\(safeName)|\(signalingPath)"
    }

    static func parse(outcome: String) -> Invite? {
        guard outcome.hasPrefix(prefix) else { return nil }
        let parts = outcome.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let sessionId = parts[1]
        let threadId = parts[2]
        let name = parts.count > 3 ? parts[3] : nil
        let path = parts.count > 4 ? parts[4...].joined(separator: "|") : nil
        guard !sessionId.isEmpty, !threadId.isEmpty else { return nil }
        return Invite(sessionId: sessionId, threadId: threadId, fromName: name, signalingPath: path)
    }

    static func parse(fromMessage dto: ChatMessageDTO) -> Invite? {
        let kind = (dto.kind ?? "").lowercased()
        guard kind == "call_event" || kind == "callevent" || dto.callOutcome != nil else { return nil }
        guard let outcome = dto.callOutcome, let invite = parse(outcome: outcome) else { return nil }
        if Date().timeIntervalSince(dto.createdAt) > 60 { return nil }
        return invite
    }

    static func endMarker(sessionId: String) -> String {
        "__tactech_call_ended__|\(sessionId)"
    }

    static func isEndMarker(_ outcome: String) -> Bool {
        outcome.hasPrefix("__tactech_call_ended__")
    }
}
