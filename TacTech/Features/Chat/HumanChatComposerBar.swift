import PhotosUI
import SwiftUI

/// AI-chrome composer for trainer↔trainee chat: photo, video, voice, video call, text.
struct HumanChatComposerBar: View {
    @Binding var draft: String
    @Binding var pendingImage: UIImage?
    @Binding var pendingVideoURL: URL?
    @Binding var isFocused: Bool
    var peerName: String
    var isRecording: Bool
    var recordingSecondsLeft: Int
    var onSendText: () -> Void
    var onSendImage: (String?) -> Void
    var onSendVideo: (String?) -> Void
    var onPickMedia: () -> Void
    var onMic: () -> Void
    var onCall: () -> Void
    var onStopVoice: () -> Void
    var onCancelVoice: () -> Void

    @FocusState private var fieldFocused: Bool

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pendingImage != nil
            || pendingVideoURL != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if isRecording {
                voicePanel
                    .transition(.opacity)
            } else {
                if let pendingImage {
                    pendingPhotoRow(pendingImage)
                }
                if pendingVideoURL != nil {
                    pendingVideoRow
                }
                composerRow
            }
        }
        .background(Color.white.opacity(0.55))
        .animation(soft, value: isRecording)
        .animation(soft, value: pendingImage != nil)
        .animation(soft, value: pendingVideoURL != nil)
        .onChange(of: fieldFocused) { _, focused in
            guard isFocused != focused else { return }
            DispatchQueue.main.async { isFocused = focused }
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused, fieldFocused else { return }
            DispatchQueue.main.async { fieldFocused = false }
        }
    }

    private func pendingPhotoRow(_ image: UIImage) -> some View {
        HStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo ready")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(ink)
                Text("Add a caption or send")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(muted)
            }
            Spacer()
            Button {
                withAnimation(soft) { pendingImage = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    private var pendingVideoRow: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: "video.fill")
                    .foregroundStyle(ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Video ready")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(ink)
                Text("Add a caption or send")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(muted)
            }
            Spacer()
            Button {
                withAnimation(soft) { pendingVideoURL = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    private var composerRow: some View {
        HStack(spacing: 8) {
            Button(action: onPickMedia) {
                iconCircle(icon: .plus, filled: false)
            }
            .buttonStyle(AssessmentCardPressStyle())
            .accessibilityLabel("Share photo or video")

            Button {
                fieldFocused = false
                onMic()
            } label: {
                iconCircle(icon: .microphone, filled: true)
            }
            .buttonStyle(AssessmentCardPressStyle())
            .accessibilityLabel("Voice note")

            Button {
                fieldFocused = false
                onCall()
            } label: {
                iconCircle(systemName: "video.fill")
            }
            .buttonStyle(AssessmentCardPressStyle())
            .accessibilityLabel("Video call")

            HStack(spacing: 8) {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .font(TTFont.workSans(15, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1...4)
                    .focused($fieldFocused)
                    .tint(orange)
                    .submitLabel(.send)
                    .onSubmit(sendKeepingFocus)

                if canSend {
                    Button(action: sendKeepingFocus) {
                        ZStack {
                            Circle().fill(orange).frame(width: 32, height: 32)
                            Image(systemName: "arrow.up")
                                .font(TTFont.workSans(13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(fieldFocused ? orange : Color.clear, lineWidth: 1.5)
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(soft, value: canSend)
    }

    private var placeholder: String {
        if pendingImage != nil || pendingVideoURL != nil { return "Caption (optional)…" }
        return "Message \(peerName)…"
    }

    private var voicePanel: some View {
        VStack(spacing: 12) {
            Text("Recording… \(recordingSecondsLeft)s left")
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: recordingSecondsLeft)
            Text("Max 60 seconds · tap Send when ready")
                .font(TTFont.workSans(12, weight: .medium))
                .foregroundStyle(muted)
            HStack(spacing: 16) {
                Button("Cancel", action: onCancelVoice)
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(muted)
                Button(action: onStopVoice) {
                    Text("Send voice")
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(AssessmentCardPressStyle())
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func sendKeepingFocus() {
        let caption = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingImage != nil {
            onSendImage(caption.isEmpty ? nil : caption)
            restoreFocus()
        } else if pendingVideoURL != nil {
            onSendVideo(caption.isEmpty ? nil : caption)
            restoreFocus()
        } else {
            onSendText()
            restoreFocus()
        }
    }

    private func restoreFocus() {
        fieldFocused = true
        if !isFocused { isFocused = true }
        DispatchQueue.main.async {
            if !fieldFocused { fieldFocused = true }
        }
    }

    private func iconCircle(icon: SandowIcon, filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 40, height: 40)
            TTIcon(icon: icon, filled: filled, size: 17)
                .foregroundStyle(ink)
        }
    }

    private func iconCircle(systemName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 40, height: 40)
            Image(systemName: systemName)
                .font(TTFont.workSans(15, weight: .semibold))
                .foregroundStyle(ink)
        }
    }
}
