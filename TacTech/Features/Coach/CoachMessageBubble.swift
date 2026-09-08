import SwiftUI

struct CoachMessageBubble: View {
    let message: CoachDisplayMessage
    var onRetry: (() -> Void)? = nil
    var onPlayAudio: (() -> Void)? = nil
    var onCitations: (() -> Void)? = nil
    var onFullscreenImage: ((UIImage) -> Void)? = nil

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 40)
            } else {
                aiAvatar(size: 26)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                imageBlock
                textBlock
                statusRow
            }

            if !isUser {
                Spacer(minLength: 40)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var imageBlock: some View {
        if let ui = message.localImage {
            Button {
                onFullscreenImage?(ui)
            } label: {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 210, maxHeight: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .overlay(alignment: .bottom) {
                        if case .analyzing = message.status {
                            analyzingChip
                        }
                    }
            }
            .buttonStyle(.plain)
        } else if let urlString = message.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 210, maxHeight: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .failure:
                    placeholderThumb
                case .empty:
                    placeholderThumb.overlay(ProgressView().tint(orange))
                @unknown default:
                    placeholderThumb
                }
            }
        }
    }

    private var analyzingChip: some View {
        Text("Analyzing photo…")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .padding(10)
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.06))
            .frame(width: 160, height: 120)
    }

    @ViewBuilder
    private var textBlock: some View {
        let showText = !message.content.isEmpty || message.status == .streaming
        if showText {
            HStack(alignment: .top, spacing: 6) {
                if message.modality == .voice {
                    TTIcon(icon: .waveSine, size: 12)
                        .foregroundStyle(isUser ? Color.white.opacity(0.85) : orange)
                        .padding(.top, 3)
                }
                Text(message.content.isEmpty && message.status == .streaming ? "…" : message.content)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isUser ? Color.white : ink)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(isUser ? Color.black : Color.white.opacity(0.92))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: isUser ? 18 : 5,
                    bottomTrailingRadius: isUser ? 5 : 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isUser ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isUser ? 0.12 : 0.04), radius: 8, y: 3)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            if case .failed(let reason) = message.status {
                Text(reason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .lineLimit(2)
                if onRetry != nil {
                    Button("Retry") { onRetry?() }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(orange)
                }
            }

            if !isUser, message.audioUrl != nil {
                Button { onPlayAudio?() } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(orange)
                }
                .buttonStyle(.plain)
            }

            if !isUser, let citations = message.citations, !citations.isEmpty {
                Button { onCitations?() } label: {
                    Text("Sources \(citations.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func aiAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(orange.opacity(0.14))
            TTIcon(icon: .robotFace1, filled: true, size: size * 0.48)
                .foregroundStyle(orange)
        }
        .frame(width: size, height: size)
    }
}
