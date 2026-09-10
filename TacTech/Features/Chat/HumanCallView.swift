import AVFoundation
import SwiftUI

/// Live video call shell for trainer↔trainee. Local camera preview now; WebRTC peer media later.
struct HumanCallView: View {
    let peerName: String
    @Binding var isPresented: Bool
    var onEnded: (String) -> Void

    @State private var muted = false
    @State private var cameraOff = false
    @State private var connecting = true
    @State private var connectedAt: Date?
    @State private var pulse = false
    @State private var elapsedLabel = "00:00"
    @State private var tickTask: Task<Void, Never>?

    private let orange = TTColor.actionOrange
    private let ink = Color.black

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraOff {
                peerPlaceholder
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

            VStack(spacing: 0) {
                HStack {
                    Button {
                        end(outcome: "Call ended")
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()

                VStack(spacing: 10) {
                    TTAvatar(name: peerName, size: 72)
                        .overlay(
                            Circle()
                                .strokeBorder(orange.opacity(pulse ? 0.9 : 0.35), lineWidth: 2.5)
                                .frame(width: pulse ? 88 : 80, height: pulse ? 88 : 80)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                        )
                    Text(peerName)
                        .font(TTFont.workSans(22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(statusText)
                        .font(TTFont.workSans(14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer()

                HStack(spacing: 28) {
                    callControl(
                        systemName: muted ? "mic.slash.fill" : "mic.fill",
                        label: muted ? "Unmute" : "Mute",
                        tint: muted ? orange : .white
                    ) {
                        muted.toggle()
                    }
                    callControl(
                        systemName: cameraOff ? "video.slash.fill" : "video.fill",
                        label: cameraOff ? "Camera" : "Hide",
                        tint: cameraOff ? orange : .white
                    ) {
                        cameraOff.toggle()
                    }
                    callControl(systemName: "phone.down.fill", label: "End", tint: .white, fill: Color.red) {
                        end(outcome: connectedAt == nil ? "Cancelled call" : "Call · \(elapsedLabel)")
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .task {
            pulse = true
            try? await Task.sleep(for: .milliseconds(900))
            connecting = false
            connectedAt = .now
            startTicker()
        }
        .onDisappear {
            tickTask?.cancel()
        }
    }

    private var statusText: String {
        if connecting { return "Connecting…" }
        return "Video call · \(elapsedLabel)"
    }

    private var peerPlaceholder: some View {
        ZStack {
            Color(white: 0.08)
            VStack(spacing: 12) {
                TTAvatar(name: peerName, size: 96)
                Text("Camera off")
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .ignoresSafeArea()
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

    private func end(outcome: String) {
        tickTask?.cancel()
        onEnded(outcome)
        isPresented = false
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
        private var preview: AVCaptureVideoPreviewLayer?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            if let preview = layer as? AVCaptureVideoPreviewLayer {
                preview.session = session
                preview.videoGravity = .resizeAspectFill
                self.preview = preview
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
