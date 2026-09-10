import AVFoundation
import AudioToolbox
import Foundation
import UIKit

// MARK: - Ringtone / ringback

@MainActor
final class CallRingtonePlayer {
    enum Mode { case incoming, outgoing }

    private var timer: Timer?
    private var engine: AVAudioEngine?
    private var mode: Mode = .incoming

    func start(_ mode: Mode) {
        stop()
        self.mode = mode
        configureSession()
        playBurst()
        let interval: TimeInterval = mode == .incoming ? 2.4 : 3.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.playBurst() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        engine?.stop()
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
    }

    private func playBurst() {
        // System alert + haptic so it feels like a phone ring even without a bundled asset.
        AudioServicesPlaySystemSound(1_007) // SMS / alert tone (works without custom file)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
        playTonePair()
    }

    /// Two short beeps ≈ classic ring pattern.
    private func playTonePair() {
        engine?.stop()
        let engine = AVAudioEngine()
        self.engine = engine
        let main = engine.mainMixerNode
        let format = main.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        let freq: Double = mode == .incoming ? 440 : 480
        let duration: Double = 0.35
        let gap: Double = 0.18
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * (duration * 2 + gap))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else { return }

        let total = Int(frameCount)
        let beepFrames = Int(sampleRate * duration)
        let gapFrames = Int(sampleRate * gap)
        for frame in 0..<total {
            var sample: Float = 0
            if frame < beepFrames {
                let t = Double(frame) / sampleRate
                let env = Float(min(1, Double(frame) / 800) * min(1, Double(beepFrames - frame) / 800))
                sample = Float(sin(2 * Double.pi * freq * t)) * 0.28 * env
            } else if frame >= beepFrames + gapFrames, frame < beepFrames * 2 + gapFrames {
                let local = frame - beepFrames - gapFrames
                let t = Double(local) / sampleRate
                let env = Float(min(1, Double(local) / 800) * min(1, Double(beepFrames - local) / 800))
                sample = Float(sin(2 * Double.pi * (freq + 40) * t)) * 0.28 * env
            }
            for ch in 0..<Int(format.channelCount) {
                channels[ch][frame] = sample
            }
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: main, format: format)
        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: []) 
            player.play()
        } catch {
            engine.stop()
            self.engine = nil
        }
    }
}

// MARK: - Call models

enum HumanCallPhase: Equatable {
    case idle
    case outgoingRinging
    case incomingRinging
    case connecting
    case inCall
}

struct HumanCallInvite: Identifiable, Equatable {
    var id: String { sessionId }
    let sessionId: String
    let threadId: String
    let peerUserId: String
    let peerName: String
    var signalingPath: String?
    var isOutgoing: Bool
}

// MARK: - Store

@MainActor
@Observable
final class HumanCallStore {
    static let shared = HumanCallStore()

    var phase: HumanCallPhase = .idle
    var activeInvite: HumanCallInvite?
    var lastError: String?
    var elapsedLabel = "00:00"
    var muted = false
    var cameraOff = false

    private let api = ChatAPI()
    private let realtime = ChatRealtimeClient()
    private let ringtone = CallRingtonePlayer()
    private var signalingTask: URLSessionWebSocketTask?
    private var tickTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var connectedAt: Date?
    private var monitoring = false
    private var myUserId: String?

    // MARK: Lifecycle (keep alive while logged in — even if chat UI closed)

    func startMonitoring() {
        if monitoring {
            realtime.connect()
            Task { await pollForIncomingInvites() }
            return
        }
        monitoring = true
        myUserId = Self.jwtUserId()
        realtime.onEvent = { [weak self] event in
            self?.handleRealtime(event)
        }
        realtime.connect()
        startInvitePolling()
    }

    /// Force one `GET /chat/rtc/incoming` (scene active / push wake).
    func refreshIncomingNow() async {
        await pollForIncomingInvites()
    }

    func stopMonitoring() {
        monitoring = false
        pollTask?.cancel()
        pollTask = nil
        hangupLocal(outcome: nil, notifyPeer: false)
        realtime.disconnect()
    }

    // MARK: Outgoing

    func startOutgoing(
        peerUserId: String,
        peerName: String,
        threadId: String,
        fromName: String? = nil
    ) async {
        hangupLocal(outcome: nil, notifyPeer: false)
        do {
            let session = try await api.createRtcSession(threadId: threadId)
            let invite = HumanCallInvite(
                sessionId: session.id,
                threadId: threadId,
                peerUserId: peerUserId,
                peerName: peerName,
                signalingPath: session.signalingPath,
                isOutgoing: true
            )
            activeInvite = invite
            phase = .outgoingRinging
            ringtone.start(.outgoing)
            connectSignaling(path: session.signalingPath, sessionId: session.id)

            // REST fallback: embed invite so peer discovers the call even if Socket.IO fails.
            let callerName = fromName?.nilIfEmpty ?? Self.currentDisplayName()
            let marker = CallInviteCodec.encode(
                sessionId: session.id,
                threadId: threadId,
                fromName: callerName,
                signalingPath: session.signalingPath
            )
            _ = try? await api.sendCallEvent(
                threadId: threadId,
                outcome: marker,
                clientId: "invite-\(session.id)"
            )
            lastError = nil
        } catch {
            lastError = (error as? AppError)?.errorDescription ?? error.localizedDescription
            phase = .idle
            activeInvite = nil
        }
    }

    // MARK: Incoming actions

    func acceptIncoming() {
        guard var invite = activeInvite, !invite.isOutgoing else { return }
        ringtone.stop()
        phase = .connecting
        let path = invite.signalingPath ?? Self.defaultSignalingPath(sessionId: invite.sessionId)
        invite.signalingPath = path
        activeInvite = invite
        connectSignaling(path: path, sessionId: invite.sessionId)
        // Callee joined — treat as in-call once signaling is up.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            enterInCall()
        }
    }

    func declineIncoming() {
        guard let invite = activeInvite else { return }
        sendHangup(reason: "declined")
        Task {
            _ = try? await api.sendCallEvent(
                threadId: invite.threadId,
                outcome: CallInviteCodec.endMarker(sessionId: invite.sessionId),
                clientId: "end-\(invite.sessionId)-\(UUID().uuidString)"
            )
            HumanChatStore.shared.recordCallEvent(peerId: invite.peerUserId, outcome: "Declined call")
        }
        hangupLocal(outcome: nil, notifyPeer: false)
    }

    func endCall() {
        guard let invite = activeInvite else {
            hangupLocal(outcome: nil, notifyPeer: false)
            return
        }
        let outcome: String
        switch phase {
        case .outgoingRinging:
            outcome = "Cancelled call"
        case .incomingRinging:
            outcome = "Declined call"
        case .inCall, .connecting:
            outcome = "Call · \(elapsedLabel)"
        case .idle:
            outcome = "Call ended"
        }
        sendHangup(reason: "ended")
        Task {
            _ = try? await api.sendCallEvent(
                threadId: invite.threadId,
                outcome: CallInviteCodec.endMarker(sessionId: invite.sessionId),
                clientId: "end-\(invite.sessionId)-\(UUID().uuidString)"
            )
            HumanChatStore.shared.recordCallEvent(peerId: invite.peerUserId, outcome: outcome)
        }
        hangupLocal(outcome: nil, notifyPeer: false)
    }

    // MARK: Realtime

    private func handleRealtime(_ event: ChatRealtimeClient.Event) {
        switch event {
        case let .callIncoming(threadId, sessionId, fromUserId, fromName, signalingPath):
            presentIncoming(
                sessionId: sessionId,
                threadId: threadId,
                fromUserId: fromUserId,
                fromName: fromName,
                signalingPath: signalingPath
            )

        case let .callEnded(_, sessionId, _):
            if activeInvite?.sessionId == sessionId {
                hangupLocal(outcome: nil, notifyPeer: false)
            }

        case .message(let dto):
            if let outcome = dto.callOutcome, CallInviteCodec.isEndMarker(outcome) {
                let sid = outcome.split(separator: "|").dropFirst().first.map(String.init)
                if let sid, activeInvite?.sessionId == sid {
                    hangupLocal(outcome: nil, notifyPeer: false)
                }
            }

        case .notificationCreated(let note):
            NotificationStore.shared.handleCreated(note)
            // Call push may arrive as inbox row while Socket call event is delayed.
            if note.type == "chat_call" {
                var info: [AnyHashable: Any] = ["type": "chat_call"]
                for (k, v) in note.data { info[k] = v }
                NotificationStore.shared.handleUserInfo(info, fromUserTap: false)
            }

        default:
            break
        }
    }

    private func presentIncoming(
        sessionId: String,
        threadId: String,
        fromUserId: String,
        fromName: String?,
        signalingPath: String?
    ) {
        if fromUserId == myUserId { return }
        if let active = activeInvite, active.sessionId == sessionId { return }
        guard phase == .idle else { return }
        let invite = HumanCallInvite(
            sessionId: sessionId,
            threadId: threadId,
            peerUserId: fromUserId,
            peerName: fromName?.nilIfEmpty ?? "Incoming call",
            signalingPath: signalingPath ?? Self.defaultSignalingPath(sessionId: sessionId),
            isOutgoing: false
        )
        activeInvite = invite
        phase = .incomingRinging
        ringtone.start(.incoming)
        Task { await HumanChatStore.shared.refreshInbox() }
    }

    /// Poll `GET /chat/rtc/incoming` (primary) + legacy message markers.
    private func startInvitePolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // Immediate cold-start check so relaunch / Home tab still rings.
            await self?.pollForIncomingInvites()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                await self?.pollForIncomingInvites()
            }
        }
    }

    private func pollForIncomingInvites() async {
        guard monitoring else { return }
        // If already in a call UI, still watch for end via empty incoming list.
        do {
            let items = try await api.listIncomingCalls()
            if phase == .idle, let first = items.first {
                presentIncoming(
                    sessionId: first.sessionId,
                    threadId: first.threadId,
                    fromUserId: first.fromUserId,
                    fromName: first.fromName,
                    signalingPath: first.signalingPath
                )
                return
            }
            if let active = activeInvite,
               (phase == .incomingRinging || phase == .outgoingRinging),
               !items.contains(where: { $0.sessionId == active.sessionId }),
               phase == .incomingRinging {
                // Remote cancelled before accept.
                hangupLocal(outcome: nil, notifyPeer: false)
            }
        } catch {
            // Soft fail — keep socket + legacy poll.
        }

        guard phase == .idle else { return }
        // Legacy message-marker fallback (older builds / partial backends).
        do {
            let threads = try await api.listThreads()
            let me = myUserId ?? Self.jwtUserId()
            for thread in threads.prefix(6) {
                if let updated = thread.lastMessageAt,
                   Date().timeIntervalSince(updated) > 90 {
                    continue
                }
                let page = try await api.listMessages(threadId: thread.id, limit: 10)
                for dto in page.items.sorted(by: { $0.createdAt > $1.createdAt }) {
                    guard let invite = CallInviteCodec.parse(fromMessage: dto) else { continue }
                    let ended = page.items.contains {
                        guard let o = $0.callOutcome, CallInviteCodec.isEndMarker(o) else { return false }
                        return o.contains(invite.sessionId) && $0.createdAt >= dto.createdAt
                    }
                    if ended { continue }
                    guard dto.senderUserId != me else { continue }
                    presentIncoming(
                        sessionId: invite.sessionId,
                        threadId: invite.threadId.isEmpty ? thread.id : invite.threadId,
                        fromUserId: dto.senderUserId,
                        fromName: invite.fromName ?? thread.peerName,
                        signalingPath: invite.signalingPath
                    )
                    return
                }
            }
        } catch {
            // Soft fail.
        }
    }

    /// Handle push / cold deep-link payloads: `{ type: chat_call, sessionId, threadId, ... }`.
    func handlePushPayload(_ userInfo: [AnyHashable: Any]) {
        let type = (userInfo["type"] as? String)
            ?? ((userInfo["data"] as? [AnyHashable: Any])?["type"] as? String)
        guard type == "chat_call" else { return }
        let data = (userInfo["data"] as? [AnyHashable: Any]) ?? userInfo
        let sessionId = (data["sessionId"] as? String) ?? ""
        let threadId = (data["threadId"] as? String) ?? ""
        let fromUserId = (data["fromUserId"] as? String) ?? ""
        guard !sessionId.isEmpty, !threadId.isEmpty, !fromUserId.isEmpty else {
            Task { await pollForIncomingInvites() }
            return
        }
        presentIncoming(
            sessionId: sessionId,
            threadId: threadId,
            fromUserId: fromUserId,
            fromName: data["fromName"] as? String,
            signalingPath: data["signalingPath"] as? String
        )
    }

    // MARK: Signaling

    private func connectSignaling(path: String, sessionId: String) {
        signalingTask?.cancel(with: .goingAway, reason: nil)
        guard let token = TokenStore.accessToken() else { return }
        guard let url = Self.absoluteWebSocketURL(path: path, token: token) else { return }
        var request = URLRequest(url: url)
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        let task = URLSession.shared.webSocketTask(with: request)
        signalingTask = task
        task.resume()
        receiveSignaling(task, sessionId: sessionId)
        // Announce presence
        sendSignaling(["type": "joined", "sessionId": sessionId])
    }

    private func receiveSignaling(_ task: URLSessionWebSocketTask, sessionId: String) {
        Task {
            while signalingTask === task {
                do {
                    let message = try await task.receive()
                    let text: String?
                    switch message {
                    case .string(let s): text = s
                    case .data(let d): text = String(data: d, encoding: .utf8)
                    @unknown default: text = nil
                    }
                    guard let text,
                          let data = text.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = obj["type"] as? String else { continue }
                    await MainActor.run {
                        self.handleSignaling(type: type, sessionId: sessionId)
                    }
                } catch {
                    break
                }
            }
        }
    }

    private func handleSignaling(type: String, sessionId: String) {
        guard activeInvite?.sessionId == sessionId else { return }
        switch type {
        case "joined":
            // Peer joined — stop ringing, enter call.
            if phase == .outgoingRinging || phase == .connecting || phase == .incomingRinging {
                enterInCall()
            }
        case "hangup":
            if let peer = activeInvite?.peerUserId {
                let outcome = phase == .inCall ? "Call · \(elapsedLabel)" : "Call ended"
                HumanChatStore.shared.recordCallEvent(peerId: peer, outcome: outcome)
            }
            hangupLocal(outcome: nil, notifyPeer: false)
        case "error":
            lastError = "Call signaling error."
            hangupLocal(outcome: nil, notifyPeer: false)
        default:
            break
        }
    }

    private func sendHangup(reason: String) {
        sendSignaling(["type": "hangup", "reason": reason])
    }

    private func sendSignaling(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        signalingTask?.send(.string(text)) { _ in }
    }

    private func enterInCall() {
        ringtone.stop()
        phase = .inCall
        connectedAt = .now
        startTicker()
    }

    private func hangupLocal(outcome _: String?, notifyPeer: Bool) {
        if notifyPeer { sendHangup(reason: "ended") }
        ringtone.stop()
        tickTask?.cancel()
        tickTask = nil
        signalingTask?.cancel(with: .goingAway, reason: nil)
        signalingTask = nil
        connectedAt = nil
        elapsedLabel = "00:00"
        muted = false
        cameraOff = false
        phase = .idle
        activeInvite = nil
    }

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled {
                if let connectedAt {
                    let secs = Int(Date().timeIntervalSince(connectedAt))
                    elapsedLabel = String(format: "%02d:%02d", secs / 60, secs % 60)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func defaultSignalingPath(sessionId: String) -> String {
        "/chat/rtc/sessions/\(sessionId)/signal"
    }

    private static func absoluteWebSocketURL(path: String, token: String) -> URL? {
        if path.hasPrefix("ws://") || path.hasPrefix("wss://") {
            var components = URLComponents(string: path)
            var items = components?.queryItems ?? []
            if items.contains(where: { $0.name == "token" }) == false {
                items.append(URLQueryItem(name: "token", value: token))
            }
            components?.queryItems = items
            return components?.url
        }
        var components = URLComponents()
        components.scheme = APIConfig.baseURL.scheme == "https" ? "wss" : "ws"
        components.host = APIConfig.baseURL.host
        components.port = APIConfig.baseURL.port
        let cleaned = path.hasPrefix("/") ? path : "/" + path
        components.path = cleaned
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private static func jwtUserId() -> String? {
        guard let token = TokenStore.accessToken() else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = 4 - payload.count % 4
        if pad < 4 { payload += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["userId"] as? String) ?? (obj["sub"] as? String) ?? (obj["id"] as? String)
    }

    private static func currentDisplayName() -> String {
        // Best-effort from JWT name claim; UI already has peer names.
        guard let token = TokenStore.accessToken() else { return "Coach" }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return "Coach" }
        var payload = String(parts[1])
        let pad = 4 - payload.count % 4
        if pad < 4 { payload += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "Coach" }
        return (obj["name"] as? String) ?? (obj["email"] as? String) ?? "Coach"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
