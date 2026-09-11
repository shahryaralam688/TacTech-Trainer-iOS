import PhotosUI
import SwiftUI
import UIKit

/// WhatsApp-style composer: reply dock, mic↔send morph, hold-to-record with slide-to-cancel.
struct HumanChatComposerBar: View {
    @Binding var draft: String
    @Binding var pendingImage: UIImage?
    @Binding var pendingVideoURL: URL?
    @Binding var isFocused: Bool
    var peerName: String
    var isRecording: Bool
    var recordingSecondsLeft: Int
    var recordingElapsed: TimeInterval
    var replyDraft: HumanChatReplyDraft?
    var onClearReply: () -> Void
    var onDraftChange: (String) -> Void
    var onSendText: () -> Void
    var onSendImage: (String?) -> Void
    var onSendVideo: (String?) -> Void
    var onPickMedia: () -> Void
    var onCall: () -> Void
    var onStartVoice: () -> Void
    var onStopVoice: () -> Void
    var onCancelVoice: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var micDrag: CGSize = .zero
    @State private var micArmed = false
    @State private var recordingLocked = false

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
            if let replyDraft {
                replyBanner(replyDraft)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isRecording {
                if recordingLocked {
                    lockedVoicePanel
                } else {
                    holdVoicePanel
                }
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
        .animation(soft, value: recordingLocked)
        .animation(soft, value: pendingImage != nil)
        .animation(soft, value: pendingVideoURL != nil)
        .animation(soft, value: replyDraft?.messageId)
        .animation(.easeInOut(duration: 0.15), value: canSend)
        .onChange(of: fieldFocused) { _, focused in
            guard isFocused != focused else { return }
            DispatchQueue.main.async { isFocused = focused }
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused, fieldFocused else { return }
            DispatchQueue.main.async { fieldFocused = false }
        }
        .onChange(of: draft) { _, value in
            onDraftChange(value)
        }
        .onChange(of: isRecording) { _, recording in
            if !recording {
                micDrag = .zero
                micArmed = false
                recordingLocked = false
            }
        }
    }

    private func replyBanner(_ draft: HumanChatReplyDraft) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(orange).frame(width: 3, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.senderName)
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(orange)
                Text(draft.snippet)
                    .font(TTFont.workSans(12, weight: .regular))
                    .foregroundStyle(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClearReply) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
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
                    .lineLimit(1...6)
                    .focused($fieldFocused)
                    .tint(orange)
                    .submitLabel(.send)
                    .onSubmit(sendKeepingFocus)

                trailingAction
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .frame(minHeight: 40)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(fieldFocused ? orange : Color.clear, lineWidth: 1.5)
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var trailingAction: some View {
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
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            .accessibilityLabel("Send")
        } else {
            micButton
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.black))
            .scaleEffect(micArmed ? 1.35 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !micArmed {
                            micArmed = true
                            fieldFocused = false
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onStartVoice()
                        }
                        micDrag = value.translation
                        if value.translation.height < -100 {
                            recordingLocked = true
                        }
                    }
                    .onEnded { value in
                        defer {
                            micArmed = false
                            micDrag = .zero
                        }
                        if recordingLocked { return }
                        if value.translation.width < -80 {
                            onCancelVoice()
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        } else {
                            onStopVoice()
                        }
                    }
            )
            .accessibilityLabel("Hold to record voice note")
    }

    private var holdVoicePanel: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(0.4 + 0.6 * abs(sin(recordingElapsed * 4)))
            Text(formatElapsed(recordingElapsed))
                .font(TTFont.workSans(15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ink)
            Spacer()
            Text(micDrag.width < -40 ? "Release to cancel" : "← Slide to cancel · ↑ Lock")
                .font(TTFont.workSans(12, weight: .medium))
                .foregroundStyle(micDrag.width < -40 ? Color.red : muted)
                .animation(.easeOut(duration: 0.15), value: micDrag.width < -40)
            Spacer()
            Text("\(recordingSecondsLeft)s")
                .font(TTFont.workSans(12, weight: .medium))
                .foregroundStyle(muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .offset(x: min(0, micDrag.width * 0.35))
    }

    private var lockedVoicePanel: some View {
        VStack(spacing: 12) {
            HStack {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("Recording locked · \(formatElapsed(recordingElapsed))")
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { i in
                    Capsule()
                        .fill(orange.opacity(0.55 + 0.35 * Double((i + Int(recordingElapsed * 8)) % 5) / 5))
                        .frame(width: 3, height: CGFloat(8 + (i % 6) * 4))
                }
            }
            .frame(height: 36)

            HStack(spacing: 16) {
                Button(action: onCancelVoice) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(width: 44, height: 44)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onStopVoice) {
                    Text("Send")
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(AssessmentCardPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 12)
    }

    private var placeholder: String {
        if pendingImage != nil || pendingVideoURL != nil { return "Caption (optional)…" }
        return "Message \(peerName)…"
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

    private func formatElapsed(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        return String(format: "%d:%02d", total / 60, total % 60)
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
