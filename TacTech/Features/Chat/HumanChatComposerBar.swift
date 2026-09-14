import PhotosUI
import SwiftUI
import UIKit

/// WhatsApp-style composer: reply dock, mic↔send morph, tap-to-record studio.
struct HumanChatComposerBar: View {
    @Binding var draft: String
    @Binding var pendingImage: UIImage?
    @Binding var pendingVideoURL: URL?
    @Binding var isFocused: Bool
    var peerName: String
    var isRecording: Bool
    var isRecordingPaused: Bool
    var recordingSecondsLeft: Int
    var recordingElapsed: TimeInterval
    var replyDraft: HumanChatReplyDraft?
    var onClearReply: () -> Void
    var onDraftChange: (String) -> Void
    var onSendText: () -> Void
    var onSendImage: (String?) -> Void
    var onSendVideo: (String?) -> Void
    var onPickMedia: () -> Void
    var onStartVoice: () -> Void
    var onStopVoice: () -> Void
    var onCancelVoice: () -> Void
    var onPauseVoice: () -> Void
    var onResumeVoice: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var viewOnce = false

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
                voiceStudio
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
        .animation(soft, value: isRecordingPaused)
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
            if !recording { viewOnce = false }
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
            Button {
                fieldFocused = false
                onStartVoice()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black))
            }
            .buttonStyle(AssessmentCardPressStyle())
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
            .accessibilityLabel("Record voice note")
        }
    }

    private var voiceStudio: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center, spacing: 10) {
                Text(formatElapsed(recordingElapsed))
                    .font(TTFont.workSans(16, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .frame(minWidth: 42, alignment: .leading)
                    .accessibilityLabel("Recording \(recordingSecondsLeft) seconds left")

                voiceDots
                    .frame(maxWidth: .infinity)

                Button {
                    viewOnce.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    viewOnceGlyph
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View once")
                .accessibilityAddTraits(viewOnce ? .isSelected : [])
            }

            HStack(alignment: .center) {
                Button(action: onCancelVoice) {
                    TTIcon(icon: .trash1, size: 22)
                        .foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete recording")

                Spacer(minLength: 0)

                Button {
                    if isRecordingPaused {
                        onResumeVoice()
                    } else {
                        onPauseVoice()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.red, lineWidth: 2.5)
                            .frame(width: 56, height: 56)
                        TTIcon(
                            icon: isRecordingPaused ? .play : .pause,
                            filled: true,
                            size: 18
                        )
                        .foregroundStyle(Color.red)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRecordingPaused ? "Resume recording" : "Pause recording")

                Spacer(minLength: 0)

                Button(action: onStopVoice) {
                    ZStack {
                        Circle()
                            .fill(orange)
                            .frame(width: 48, height: 48)
                        TTIcon(icon: .paperPlaneVertical, filled: true, size: 18)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(AssessmentCardPressStyle())
                .accessibilityLabel("Send voice note")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var voiceDots: some View {
        TimelineView(.animation(minimumInterval: isRecordingPaused ? 1 : 0.12, paused: isRecordingPaused)) { timeline in
            let tick = isRecordingPaused ? recordingElapsed : timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<18, id: \.self) { i in
                    Circle()
                        .fill(dotColor(index: i, tick: tick))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private func dotColor(index: Int, tick: TimeInterval) -> Color {
        let wave = (sin(tick * 6 + Double(index) * 0.55) + 1) / 2
        let filled = !isRecordingPaused && wave > 0.42
        return filled ? Color(white: 0.28) : Color(white: 0.72)
    }

    private var viewOnceGlyph: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.62)
                .stroke(viewOnce ? orange : ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0.62, to: 1.08)
                .stroke(
                    viewOnce ? orange : ink,
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2.2, 2.4])
                )
                .rotationEffect(.degrees(-90))
            Text("1")
                .font(TTFont.workSans(12, weight: .semibold))
                .foregroundStyle(viewOnce ? orange : ink)
        }
        .frame(width: 26, height: 26)
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
}
