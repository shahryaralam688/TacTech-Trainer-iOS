import AVKit
import SwiftUI

struct HumanChatBubble: View {
    let message: HumanChatMessage
    var peerName: String
    var image: UIImage?
    var mediaURL: URL?
    var onPlayVoice: (() -> Void)?
    var onFullscreenImage: ((UIImage) -> Void)?
    var onPlayVideo: ((URL) -> Void)?

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)

    private var isOutgoing: Bool { message.isOutgoing }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOutgoing {
                Spacer(minLength: 40)
            } else {
                TTAvatar(name: peerName, size: 26)
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
                content
                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(TTFont.workSans(10, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.horizontal, 4)
            }

            if !isOutgoing {
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .image:
            imageBlock
            if !message.text.isEmpty { textBubble(message.text) }
        case .video:
            videoBlock
            if !message.text.isEmpty { textBubble(message.text) }
        case .voice:
            voiceBlock
        case .callEvent:
            callEventChip
        case .text:
            textBubble(message.text)
        }
    }

    @ViewBuilder
    private var imageBlock: some View {
        if let image {
            Button { onFullscreenImage?(image) } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 210, maxHeight: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        } else if let mediaURL, !mediaURL.isFileURL {
            AsyncImage(url: mediaURL) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 210, maxHeight: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .failure:
                    placeholderThumb(systemName: "photo")
                case .empty:
                    placeholderThumb(systemName: "photo")
                        .overlay(ProgressView().tint(orange))
                @unknown default:
                    placeholderThumb(systemName: "photo")
                }
            }
        } else {
            placeholderThumb(systemName: "photo")
        }
    }

    @ViewBuilder
    private var videoBlock: some View {
        Button {
            if let mediaURL { onPlayVideo?(mediaURL) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 210, height: 140)
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                    if let secs = message.durationSeconds, secs > 0 {
                        Text(Self.formatDuration(secs))
                            .font(TTFont.workSans(12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var voiceBlock: some View {
        Button { onPlayVoice?() } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                TTIcon(icon: .waveSine, size: 14)
                Text(Self.formatDuration(message.durationSeconds ?? 0))
                    .font(TTFont.workSans(13, weight: .semibold))
            }
            .foregroundStyle(isOutgoing ? Color.white : ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isOutgoing ? Color.black : Color.white.opacity(0.92))
            .clipShape(bubbleShape)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOutgoing ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isOutgoing ? 0.12 : 0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var callEventChip: some View {
        let label: String = {
            if let outcome = message.callOutcome, CallInviteCodec.parse(outcome: outcome) != nil {
                return "Video call"
            }
            if let outcome = message.callOutcome, CallInviteCodec.isEndMarker(outcome) {
                return "Call ended"
            }
            return message.callOutcome ?? "Call"
        }()
        return HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(TTFont.workSans(12, weight: .semibold))
        }
        .foregroundStyle(muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }

    private func textBubble(_ text: String) -> some View {
        Text(text)
            .font(TTFont.workSans(15, weight: .medium))
            .foregroundStyle(isOutgoing ? Color.white : ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(isOutgoing ? Color.black : Color.white.opacity(0.92))
            .clipShape(bubbleShape)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOutgoing ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isOutgoing ? 0.12 : 0.04), radius: 8, y: 3)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: isOutgoing ? 18 : 5,
            bottomTrailingRadius: isOutgoing ? 5 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    private func placeholderThumb(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.06))
            .frame(width: 160, height: 120)
            .overlay(
                Image(systemName: systemName)
                    .foregroundStyle(muted)
            )
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
