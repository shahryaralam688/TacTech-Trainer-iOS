import SwiftUI

/// Hold-to-talk AI call shell. Uses `/coach/voice/turn` for replies; WS for signaling join/hangup.
struct CoachVoiceCallView: View {
    @Bindable var store: CoachStore
    @Binding var isPresented: Bool

    @State private var session: CoachRtcSession?
    @State private var wsTask: URLSessionWebSocketTask?
    @State private var joined = false
    @State private var holding = false
    @State private var hint: String?
    @State private var errorText: String?
    @State private var pulse = false

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { hangup() }

            VStack(spacing: 20) {
                Capsule()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                ZStack {
                    Circle()
                        .fill(orange.opacity(holding ? 0.28 : 0.14))
                        .frame(width: pulse ? 140 : 120)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [orange, orange.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .shadow(color: orange.opacity(0.35), radius: 16, y: 6)
                    TTIcon(icon: .robotFace1, filled: true, size: 36)
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text("TacTech AI Call")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ink)
                    Text(statusLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.center)
                }

                if let hint {
                    Text(hint)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 16)
                        .multilineTextAlignment(.center)
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                holdButton
                    .padding(.top, 8)

                Button("End call", action: hangup)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(muted)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: 360)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(orange.opacity(0.35), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 28, y: 14)
            .padding(.horizontal, 24)
        }
        .task { await bootstrap() }
        .onDisappear { teardownWS() }
        .onAppear { pulse = true }
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.8), trigger: holding)
    }

    private var statusLabel: String {
        if store.isSending { return "Coach is thinking…" }
        if holding { return "Recording — release to send" }
        if joined { return "Connected · hold to talk" }
        if session != nil { return "Joining signaling…" }
        return "Starting session…"
    }

    private var holdButton: some View {
        Text(holding ? "Release" : "Hold to talk")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(holding ? Color.black : orange)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !holding, store.canSend else { return }
                        holding = true
                        store.startRecording()
                    }
                    .onEnded { _ in
                        guard holding else { return }
                        holding = false
                        store.stopAndSendVoice()
                        sendVoiceHint()
                    }
            )
            .disabled(store.isBusy && !holding)
    }

    private func bootstrap() async {
        do {
            let created = try await store.createCallSession()
            session = created
            connectWS(created)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func connectWS(_ session: CoachRtcSession) {
        guard var components = URLComponents(string: session.signalingPath) else { return }
        var items = components.queryItems ?? []
        if let token = TokenStore.accessToken() {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        let task = URLSession.shared.webSocketTask(with: request)
        wsTask = task
        task.resume()
        receiveLoop(task)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { result in
            switch result {
            case .success(let message):
                if case let .string(text) = message,
                   let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String {
                    Task { @MainActor in
                        switch type {
                        case "joined":
                            joined = true
                        case "voice_hint":
                            hint = json["text"] as? String
                        case "hangup":
                            hangup()
                        default:
                            break
                        }
                    }
                }
                receiveLoop(task)
            case .failure:
                break
            }
        }
    }

    private func sendVoiceHint() {
        guard let task = wsTask else { return }
        let payload: [String: Any] = ["type": "voice_hint", "text": "User finished a push-to-talk turn"]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        task.send(.string(string)) { _ in }
    }

    private func hangup() {
        if let task = wsTask {
            let payload = #"{"type":"hangup"}"#
            task.send(.string(payload)) { _ in
                task.cancel(with: .goingAway, reason: nil)
            }
        }
        teardownWS()
        store.cancelRecording()
        isPresented = false
    }

    private func teardownWS() {
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
    }
}
