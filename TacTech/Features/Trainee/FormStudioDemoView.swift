import SwiftUI

/// Full-screen Form Studio 3D Mixamo demo for a resolved backend/local session.
struct FormStudioDemoView: View {
    let session: FormStudioExerciseMap.DemoSession
    var onFatalError: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .preparing
    @State private var cachedAnimationURL: String?
    @State private var guideJSON: String?
    @State private var cuesJSON: String?

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    private enum Phase {
        case preparing
        case ready
        case failed(String)
    }

    var body: some View {
        ZStack(alignment: .top) {
            switch phase {
            case .preparing:
                preparingView
            case .ready:
                FormStudioWebView(
                    formStudioExerciseId: session.clipId,
                    animationURL: cachedAnimationURL,
                    guideJSON: guideJSON,
                    cuesJSON: cuesJSON,
                    title: session.exerciseName,
                    onClose: { dismiss() },
                    onLoadError: { message in
                        phase = .failed(message)
                        onFatalError?(message)
                    }
                )
                .ignoresSafeArea()
            case .failed(let message):
                failedView(message)
            }

            topBar
        }
        .background(charcoal.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .statusBarHidden(false)
        .task { await prepare() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("3D Form Demo")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(session.exerciseName)
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close 3D form demonstration")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [charcoal.opacity(0.92), charcoal.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var preparingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text(
                session.remoteAnimationURL != nil
                    ? "Loading 3D coach…"
                    : "Opening 3D coach…"
            )
            .font(TTFont.workSans(15, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(TTColor.actionOrange)
            Text("Couldn't load 3D demo")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Close") { dismiss() }
                .font(TTFont.workSans(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func prepare() async {
        guideJSON = encodeGuide(session.guide)
        cuesJSON = encodeCues(session.cues)

        guard let remote = session.remoteAnimationURL else {
            cachedAnimationURL = nil
            phase = .ready
            return
        }

        do {
            let file = try await FormStudioClipCache.cachedFile(
                clipId: session.clipId,
                animationUrl: remote
            )
            if let appURL = FormStudioClipCache.appContentURL(forLocalFile: file) {
                cachedAnimationURL = appURL.absoluteString
            } else {
                // Fallback: let WKWebView fetch CDN directly.
                cachedAnimationURL = remote.absoluteString
            }
            phase = .ready
        } catch {
            let message = error.localizedDescription
            phase = .failed(message)
            onFatalError?(message)
        }
    }

    private func encodeGuide(_ guide: [Form3DGuideStep]?) -> String? {
        guard let guide, !guide.isEmpty else { return nil }
        let payload = guide.map { step -> [String: Any] in
            var dict: [String: Any] = [:]
            if let focus = step.focus { dict["focus"] = focus }
            if let title = step.title { dict["title"] = title }
            if let detail = step.detail { dict["detail"] = detail }
            if let t = step.t { dict["t"] = t }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private func encodeCues(_ cues: [String]?) -> String? {
        guard let cues, !cues.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: cues),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}

#Preview("Form Studio Demo") {
    FormStudioDemoView(
        session: .init(
            clipId: "push_up",
            exerciseName: "Push-Ups",
            remoteAnimationURL: nil,
            guide: nil,
            cues: nil,
            subtitle: nil
        )
    )
}
