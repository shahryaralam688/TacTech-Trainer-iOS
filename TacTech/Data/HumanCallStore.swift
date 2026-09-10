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
    private var connectedAt: Date?
    private var monitoring = false

    // MARK: Lifecycle (keep alive while logged in — even if chat UI closed)

    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        realtime.onEvent = { [weak self] event in
            self?.handleRealtime(event)
        }
        realtime.connect()
    }

    func stopMonitoring() {
        monitoring = false
        hangupLocal(outcome: nil, notifyPeer: false)
        realtime.disconnect()
    }

    // MARK: Outgoing

    func startOutgoing(
        peerUserId: String,
        peerName: String,
        threadId: String
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
        HumanChatStore.shared.recordCallEvent(peerId: invite.peerUserId, outcome: "Declined call")
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
        HumanChatStore.shared.recordCallEvent(peerId: invite.peerUserId, outcome: outcome)
        hangupLocal(outcome: nil, notifyPeer: false)
    }

    // MARK: Realtime

    private func handleRealtime(_ event: ChatRealtimeClient.Event) {
        switch event {
        case let .callIncoming(threadId, sessionId, fromUserId, fromName, signalingPath):
            // Ignore if we are the one who just started this session.
            if let active = activeInvite, active.sessionId == sessionId { return }
            if phase != .idle { return }
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
            // Soft refresh chat inbox so thread exists.
            Task { await HumanChatStore.shared.refreshInbox() }

        case let .callEnded(_, sessionId, _):
            if activeInvite?.sessionId == sessionId {
                hangupLocal(outcome: nil, notifyPeer: false)
            }

        default:
            break
        }
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
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
