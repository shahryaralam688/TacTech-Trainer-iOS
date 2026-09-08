import PhotosUI
import SwiftUI

struct CoachComposerBar: View {
    @Binding var draft: String
    @Binding var pendingImage: UIImage?
    var isBusy: Bool
    var isRecording: Bool
    var recordingSecondsLeft: Int = 30
    var showImageChips: Bool
    var onSendText: () -> Void
    var onSendImage: (String?) -> Void
    var onPickPhoto: () -> Void
    var onMic: () -> Void
    var onCall: () -> Void
    var onStopVoice: () -> Void
    var onCancelVoice: () -> Void

    @FocusState private var focused: Bool

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let soft = Animation.spring(response: 0.38, dampingFraction: 0.86)

    private var canSend: Bool {
        !isBusy && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil)
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
                if showImageChips, pendingImage != nil {
                    chipRow
                }
                composerRow
            }
        }
        .background(Color.white.opacity(0.55))
        .animation(soft, value: isRecording)
        .animation(soft, value: pendingImage != nil)
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                Text("Add a caption or pick a quick chip")
                    .font(.system(size: 12, weight: .medium))
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

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoachImageCaptionChip.allCases) { chip in
                    Button {
                        draft = chip.rawValue
                        onSendImage(chip.rawValue)
                    } label: {
                        Text(chip.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(orange.opacity(0.4), lineWidth: 1.1))
                    }
                    .buttonStyle(AssessmentCardPressStyle())
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var composerRow: some View {
        HStack(spacing: 8) {
            Button(action: onPickPhoto) {
                iconCircle(icon: .plus, filled: false)
            }
            .buttonStyle(AssessmentCardPressStyle())
            .disabled(isBusy)
            .accessibilityLabel("Share photo")

            Button(action: onMic) {
                iconCircle(icon: .microphone, filled: true)
            }
            .buttonStyle(AssessmentCardPressStyle())
            .disabled(isBusy)
            .accessibilityLabel("Talk to AI")

            Button(action: onCall) {
                iconCircle(systemName: "phone.fill")
            }
            .buttonStyle(AssessmentCardPressStyle())
            .disabled(isBusy)
            .accessibilityLabel("AI Coach call")

            HStack(spacing: 8) {
                TextField(
                    pendingImage == nil ? "Message TacTech AI…" : "Caption (optional)…",
                    text: $draft,
                    axis: .vertical
                )
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink)
                .lineLimit(1...4)
                .focused($focused)
                .tint(orange)
                .submitLabel(.send)
                .onSubmit(send)
                .disabled(isBusy)

                if canSend {
                    Button(action: send) {
                        ZStack {
                            Circle().fill(orange).frame(width: 32, height: 32)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
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
                    .strokeBorder(focused ? orange : Color.clear, lineWidth: 1.5)
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(soft, value: canSend)
    }

    private var voicePanel: some View {
        VStack(spacing: 12) {
            Text("Listening… \(recordingSecondsLeft)s left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: recordingSecondsLeft)
            Text("Max 30 seconds · release or tap Send")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted)
            HStack(spacing: 16) {
                Button("Cancel", action: onCancelVoice)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(muted)
                Button(action: onStopVoice) {
                    Text("Send voice")
                        .font(.system(size: 15, weight: .bold))
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

    private func send() {
        if pendingImage != nil {
            onSendImage(draft.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
        } else {
            onSendText()
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
