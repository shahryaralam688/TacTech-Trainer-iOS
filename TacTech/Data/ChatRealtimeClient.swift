import Foundation
import Network
import UIKit

extension Notification.Name {
    /// Connectivity came back after being lost (posted on the main queue).
    static let ttNetworkBecameReachable = Notification.Name("ttNetworkBecameReachable")
}

/// One shared path monitor for all realtime clients.
enum TTNetworkMonitor {
    private final class State { var wasSatisfied = true } // touched only on the monitor queue
    private static let state = State()
    private static let monitor = NWPathMonitor()
    private static let queue = DispatchQueue(label: "tt.network.monitor")
    private static var started = false
    private static let pathLock = NSLock()
    private static var pathSatisfied = true

    /// The device currently has a usable network path (true until the first path update says otherwise).
    static var isOnline: Bool {
        pathLock.lock(); defer { pathLock.unlock() }
        return pathSatisfied
    }

    @MainActor static func startIfNeeded() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            pathLock.lock(); pathSatisfied = satisfied; pathLock.unlock()
            if satisfied, !state.wasSatisfied {
                DispatchQueue.main.async { NotificationCenter.default.post(name: .ttNetworkBecameReachable, object: nil) }
            }
            state.wasSatisfied = satisfied
        }
        monitor.start(queue: queue)
    }
}

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
        case notificationCreated(AppNotificationDTO)
        /// Domain: coaching link created/removed. Prefer over inbox for live roster sync.
        case relationshipChanged(
            action: String,
            reason: String?,
            trainerUserId: String?,
            traineeUserId: String?,
            traineeProfileId: String?
        )
        /// Domain: a trainee's live workout session started / logged a set / completed / was discarded.
        /// IDs and status only — refetch `GET /trainer/trainees/{id}/sessions/active` for details.
        case workoutSessionChanged(traineeId: String, sessionId: String, status: String, action: String, occurredAt: String)
        /// Domain: a trainee logged a meal (sent to their trainer). Refetch the trainee's meals for details.
        case mealLogged(traineeId: String, mealId: String, mealName: String?, occurredAt: String)
        /// Domain: assigned plan assign / unassign / update. Prefer over inbox for live Workout sync.
        case planAssignmentChanged(
            action: String,
            planId: String?,
            planTitle: String?,
            trainerUserId: String?,
            traineeUserId: String?,
            traineeProfileId: String?
        )
    }

    var onEvent: ((Event) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private(set) var isConnected = false
    private var task: URLSessionWebSocketTask?
    private var receiveLoopRunning = false
    private var joinedThreadId: String?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    /// Retries so far since the last good connection; picks the next delay (see `nextReconnectDelay`).
    private var reconnectAttempt = 0
    private var reconnectPending = false
    /// Fixed per client, so the three realtime clients don't all retry at the same instant.
    private let retryStagger = Double.random(in: 0...1.5)
    private var lastImmediateRetry: Date?
    nonisolated(unsafe) private var notificationTokens: [NSObjectProtocol] = []

    init() {
        TTNetworkMonitor.startIfNeeded()
        // Back in the foreground, or the network is back: skip the waiting and try right now.
        for name in [UIApplication.didBecomeActiveNotification, Notification.Name.ttNetworkBecameReachable] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.retryNowIfNeeded() }
            }
            notificationTokens.append(token)
        }
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Resets the backoff and reconnects immediately — only if this client wants a connection and has none.
    private func retryNowIfNeeded() {
        guard shouldRun, PerfTemp.raw(.realtime), !isConnected else { return }
        if let last = lastImmediateRetry, Date().timeIntervalSince(last) < 1 { return }
        lastImmediateRetry = Date()
        reconnectAttempt = 0
        reconnectPending = false
        reconnectTask?.cancel()
        connect()
    }
    private static let backoffSeconds: [Double] = [2, 4, 8, 16, 30]
    private var shouldRun = false
    private var defaultReady = false
    private var chatReady = false
    private var authToken: String?

    func connect() {
        guard PerfTemp.raw(.realtime) else { return } // PERF-TEMP: "Realtime clients" OFF = never connect
        shouldRun = true
        reconnectTask?.cancel()
        reconnectPending = false
        disconnectSocketOnly()
        guard let token = TokenStore.accessToken() else { return }
        authToken = token
        openSocket(token: token)
    }

    func disconnect() {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectPending = false
        reconnectAttempt = 0
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
            URLQueryItem(name: "transport", value: "websocket")
        ]
        // PERF-TEMP: with "Compact network error logs" ON the token stays out of the URL (it is still sent in the
        // Authorization header and the Socket.IO auth payload), so system logs of a failed upgrade carry no token.
        if !PerfTemp.raw(.compactNetLogs) {
            components.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
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
                #if DEBUG
                // Status code only — never the URL or the token.
                let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
                print("[TacTech] realtime connection failed (http \(status)); retrying with backoff")
                #endif
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
        case "notification.created":
            if let dict = body as? [String: Any],
               let msgData = try? JSONSerialization.data(withJSONObject: dict),
               let dto = try? decoder.decode(AppNotificationDTO.self, from: msgData) {
                onEvent?(.notificationCreated(dto))
            }
        case "relationship.changed":
            if let dict = Self.unwrapEventDict(body),
               let action = Self.stringField(dict, "action"), !action.isEmpty {
                onEvent?(.relationshipChanged(
                    action: action,
                    reason: Self.stringField(dict, "reason"),
                    trainerUserId: Self.stringField(dict, "trainerUserId", "trainer_user_id"),
                    traineeUserId: Self.stringField(dict, "traineeUserId", "trainee_user_id"),
                    traineeProfileId: Self.stringField(dict, "traineeProfileId", "trainee_profile_id", "traineeId")
                ))
            }
        case "workout.session.changed":
            if let dict = Self.unwrapEventDict(body),
               let traineeId = Self.stringField(dict, "traineeId", "trainee_id"),
               let sessionId = Self.stringField(dict, "sessionId", "session_id"),
               let action = Self.stringField(dict, "action") {
                onEvent?(.workoutSessionChanged(
                    traineeId: traineeId,
                    sessionId: sessionId,
                    status: Self.stringField(dict, "status") ?? "",
                    action: action,
                    occurredAt: Self.stringField(dict, "occurredAt", "occurred_at") ?? ""
                ))
            }
        case "meal.logged":
            if let dict = Self.unwrapEventDict(body),
               let traineeId = Self.stringField(dict, "traineeId", "trainee_id"),
               let mealId = Self.stringField(dict, "mealId", "meal_id") {
                onEvent?(.mealLogged(
                    traineeId: traineeId,
                    mealId: mealId,
                    mealName: Self.stringField(dict, "mealName", "meal_name"),
                    occurredAt: Self.stringField(dict, "occurredAt", "occurred_at") ?? ""
                ))
            }
        case "plan.assignment.changed":
            if let dict = Self.unwrapEventDict(body),
               let action = Self.stringField(dict, "action"), !action.isEmpty {
                onEvent?(.planAssignmentChanged(
                    action: action,
                    planId: Self.stringField(dict, "planId", "plan_id"),
                    planTitle: Self.stringField(dict, "planTitle", "plan_title", "title"),
                    trainerUserId: Self.stringField(dict, "trainerUserId", "trainer_user_id"),
                    traineeUserId: Self.stringField(dict, "traineeUserId", "trainee_user_id"),
                    traineeProfileId: Self.stringField(dict, "traineeProfileId", "trainee_profile_id", "traineeId")
                ))
            }
        default:
            break
        }
    }

    /// Tolerate `{ …fields }` or `{ data: { …fields } }` / nested wrappers.
    private static func unwrapEventDict(_ body: Any?) -> [String: Any]? {
        guard let dict = body as? [String: Any] else { return nil }
        if let nested = dict["data"] as? [String: Any] {
            var merged = dict
            for (k, v) in nested { merged[k] = v }
            return merged
        }
        if let nested = dict["payload"] as? [String: Any] {
            var merged = dict
            for (k, v) in nested { merged[k] = v }
            return merged
        }
        return dict
    }

    private static func stringField(_ dict: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let s = dict[key] as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let n = dict[key] as? NSNumber {
                return n.stringValue
            }
        }
        return nil
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

    /// 2, 4, 8, 16, 30 s, then every 60 s — with ±15% jitter and this client's fixed stagger.
    private func nextReconnectDelay() -> Double {
        let base = reconnectAttempt < Self.backoffSeconds.count ? Self.backoffSeconds[reconnectAttempt] : 60
        reconnectAttempt += 1
        return base * Double.random(in: 0.85...1.15) + retryStagger
    }

    private func scheduleReconnect() {
        // One retry in flight at a time: a failure can be reported by both the receive loop and a packet.
        guard shouldRun, !reconnectPending else { return }
        reconnectPending = true
        let delay = nextReconnectDelay()
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.shouldRun, !Task.isCancelled else { return }
            self.reconnectPending = false
            self.connect()
        }
    }

    private func refreshConnected() {
        setConnected(defaultReady || chatReady)
    }

    private func setConnected(_ value: Bool) {
        if value { reconnectAttempt = 0 } // a good connection resets the backoff
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
