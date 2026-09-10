import AVFoundation
import SwiftUI

/// Trainer↔trainee call UI — outgoing ring, incoming Accept/Decline + ringtone, in-call controls.
struct HumanCallView: View {
    @Bindable private var callStore = HumanCallStore.shared

    private let orange = TTColor.actionOrange

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if callStore.phase == .inCall || callStore.phase == .connecting {
                inCallBackground
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerBlock
                Spacer()
                bottomControls
                    .padding(.bottom, 48)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var peerName: String {
        callStore.activeInvite?.peerName ?? "Call"
    }

    private var topBar: some View {
        HStack {
            if callStore.phase == .inCall {
                Button {
                    callStore.endCall()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var centerBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(orange.opacity(callStore.phase == .incomingRinging || callStore.phase == .outgoingRinging ? 0.85 : 0.35), lineWidth: 2.5)
                    .frame(width: 96, height: 96)
                    .scaleEffect(callStore.phase == .incomingRinging || callStore.phase == .outgoingRinging ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: callStore.phase)
                TTAvatar(name: peerName, size: 72)
            }
            Text(peerName)
                .font(TTFont.workSans(24, weight: .bold))
                .foregroundStyle(.white)
            Text(statusText)
                .font(TTFont.workSans(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
            if let err = callStore.lastError {
                Text(err)
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    private var statusText: String {
        switch callStore.phase {
        case .idle: return ""
        case .outgoingRinging: return "Calling…"
        case .incomingRinging: return "Incoming video call"
        case .connecting: return "Connecting…"
        case .inCall: return "Video call · \(callStore.elapsedLabel)"
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        switch callStore.phase {
        case .incomingRinging:
            HStack(spacing: 48) {
                callControl(systemName: "phone.down.fill", label: "Decline", tint: .white, fill: Color.red) {
                    callStore.declineIncoming()
                }
                callControl(systemName: "phone.fill", label: "Accept", tint: .white, fill: Color.green) {
                    callStore.acceptIncoming()
                }
            }
        case .outgoingRinging, .connecting:
            callControl(systemName: "phone.down.fill", label: "Cancel", tint: .white, fill: Color.red) {
                callStore.endCall()
            }
        case .inCall:
            HStack(spacing: 28) {
                callControl(
                    systemName: callStore.muted ? "mic.slash.fill" : "mic.fill",
                    label: callStore.muted ? "Unmute" : "Mute",
                    tint: callStore.muted ? orange : .white
                ) {
                    callStore.muted.toggle()
                }
                callControl(
                    systemName: callStore.cameraOff ? "video.slash.fill" : "video.fill",
                    label: callStore.cameraOff ? "Camera" : "Hide",
                    tint: callStore.cameraOff ? orange : .white
                ) {
                    callStore.cameraOff.toggle()
                }
                callControl(systemName: "phone.down.fill", label: "End", tint: .white, fill: Color.red) {
                    callStore.endCall()
                }
            }
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var inCallBackground: some View {
        if callStore.cameraOff {
            Color(white: 0.08).ignoresSafeArea()
        } else {
            HumanCallCameraPreview()
                .ignoresSafeArea()
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.55), .clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
        }
    }

    private func callControl(
        systemName: String,
        label: String,
        tint: Color,
        fill: Color = Color.white.opacity(0.16),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 62, height: 62)
                    .background(fill)
                    .clipShape(Circle())
                Text(label)
                    .font(TTFont.workSans(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }
}

/// Presents call UI globally whenever `HumanCallStore` is not idle.
struct HumanCallOverlayHost: ViewModifier {
    @Bindable private var callStore = HumanCallStore.shared

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(
                get: { callStore.phase != .idle },
                set: { presented in
                    if !presented, callStore.phase != .idle {
                        callStore.endCall()
                    }
                }
            )) {
                HumanCallView()
            }
    }
}

extension View {
    func humanCallOverlay() -> some View {
        modifier(HumanCallOverlayHost())
    }
}

// MARK: - Local camera preview

private struct HumanCallCameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.start()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.stop()
    }

    final class PreviewView: UIView {
        private let session = AVCaptureSession()

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            if let preview = layer as? AVCaptureVideoPreviewLayer {
                preview.session = session
                preview.videoGravity = .resizeAspectFill
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func start() {
            guard session.inputs.isEmpty else {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .high
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            session.commitConfiguration()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        func stop() {
            session.stopRunning()
        }
    }
}
