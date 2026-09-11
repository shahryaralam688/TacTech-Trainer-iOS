import SwiftUI
import UIKit

/// WhatsApp-style bubble: grouping corners, inline time/ticks, quote, reactions, read-more.
struct HumanChatBubble: View {
    let message: HumanChatMessage
    var peerName: String
    var cluster: HumanChatClusterRole = .isolated
    var showAvatar: Bool = true
    var image: UIImage?
    var mediaURL: URL?
    var highlight: Bool = false
    var onPlayVoice: (() -> Void)?
    var onFullscreenImage: ((UIImage) -> Void)?
    var onPlayVideo: ((URL) -> Void)?
    var onReply: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDelete: (() -> Void)?
    var onReact: ((String) -> Void)?
    var onCopy: (() -> Void)?
    var onQuoteTap: (() -> Void)?

    @State private var expanded = false
    @State private var dragOffset: CGFloat = 0

    private let orange = TTColor.actionOrange
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let readBlue = Color(red: 53 / 255, green: 152 / 255, blue: 219 / 255)
    private let baseRadius: CGFloat = 18
    private let tightRadius: CGFloat = 5

    private var isOutgoing: Bool { message.isOutgoing }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOutgoing {
                Spacer(minLength: 36)
            } else if showAvatar {
                TTAvatar(name: peerName, size: 26)
            } else {
                Color.clear.frame(width: 26, height: 26)
            }

            bubbleStack
                .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: isOutgoing ? .trailing : .leading)
                .offset(x: dragOffset)
                .background(alignment: isOutgoing ? .leading : .trailing) {
                    Image(systemName: "arrowshape.turn.up.left.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(orange.opacity(min(1, Double(abs(dragOffset) / 36))))
                        .scaleEffect(abs(dragOffset) > 28 ? 1 : 0.4)
                        .opacity(abs(dragOffset) > 8 ? 1 : 0)
                        .offset(x: isOutgoing ? -28 : 28)
                }
                .gesture(swipeReplyGesture)
                .contextMenu { contextMenu }
                .overlay(alignment: .bottomLeading) {
                    if !message.reactions.isEmpty {
                        reactionPills
                            .offset(y: 10)
                    }
                }

            if !isOutgoing {
                Spacer(minLength: 36)
            }
        }
        .padding(.bottom, message.reactions.isEmpty ? 0 : 8)
        .accessibilityElement(children: .combine)
    }

    private var bubbleStack: some View {
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlight ? orange.opacity(0.18) : Color.clear)
                .padding(-4)
        )
        .animation(.easeOut(duration: 0.35), value: highlight)
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .image:
            mediaChrome { imageBlock }
            if !message.text.isEmpty { textBubble(message.text) }
        case .video:
            mediaChrome { videoBlock }
            if !message.text.isEmpty { textBubble(message.text) }
        case .voice:
            voiceBlock
        case .callEvent:
            callEventChip
        case .text:
            textBubble(message.text)
        }
    }

    private func mediaChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .clipShape(bubbleShape)
            .overlay(
                bubbleShape.stroke(isOutgoing ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
            )
    }

    // MARK: - Text + inline meta

    private func textBubble(_ text: String) -> some View {
        let body = displayText(text)
        return VStack(alignment: .leading, spacing: 6) {
            quoteBlock
            Text(whatsAppAttributed(body))
                .font(TTFont.workSans(15, weight: .regular))
                .foregroundStyle(isOutgoing ? Color.white : ink)
                .tint(isOutgoing ? Color.white.opacity(0.9) : orange)
                .multilineTextAlignment(.leading)

            if shouldOfferReadMore(text) {
                Button(expanded ? "Show less" : "Read more") {
                    withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                }
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.85) : orange)
            }

            HStack {
                Spacer(minLength: 0)
                inlineMeta
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 7)
        .background(isOutgoing ? Color.black : Color.white.opacity(0.95))
        .clipShape(bubbleShape)
        .overlay(
            bubbleShape.stroke(isOutgoing ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isOutgoing ? 0.10 : 0.04), radius: 6, y: 2)
    }

    private var inlineMeta: some View {
        HStack(spacing: 3) {
            Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                .font(TTFont.workSans(10, weight: .regular))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.7) : Color(white: 0.5))
            if isOutgoing {
                deliveryTicks
            }
            if message.resolvedDelivery == .failed {
                Button { onRetry?() } label: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var deliveryTicks: some View {
        switch message.resolvedDelivery {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.7))
        case .delivered:
            HStack(spacing: -5) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.75))
        case .read:
            HStack(spacing: -5) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(readBlue)
        case .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var quoteBlock: some View {
        if let name = message.replyToName, let snippet = message.replyToText {
            Button {
                onQuoteTap?()
            } label: {
                HStack(spacing: 8) {
                    Capsule().fill(orange).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(isOutgoing ? Color.white.opacity(0.9) : orange)
                        Text(snippet)
                            .font(TTFont.workSans(12, weight: .regular))
                            .foregroundStyle(isOutgoing ? Color.white.opacity(0.7) : muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background((isOutgoing ? Color.white.opacity(0.12) : Color.black.opacity(0.05)))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Media / voice / call

    @ViewBuilder
    private var imageBlock: some View {
        if let image {
            Button { onFullscreenImage?(image) } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 210, maxHeight: 210)
            }
            .buttonStyle(.plain)
        } else if let mediaURL, !mediaURL.isFileURL {
            AsyncImage(url: mediaURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill().frame(maxWidth: 210, maxHeight: 210)
                default:
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
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var voiceBlock: some View {
        Button { onPlayVoice?() } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(isOutgoing ? Color.white.opacity(0.85) : orange.opacity(0.7))
                            .frame(width: 2.5, height: CGFloat(8 + (i % 5) * 3))
                    }
                }
                Text(Self.formatDuration(message.durationSeconds ?? 0))
                    .font(TTFont.workSans(13, weight: .medium))
                Spacer(minLength: 4)
                inlineMeta
            }
            .foregroundStyle(isOutgoing ? Color.white : ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isOutgoing ? Color.black : Color.white.opacity(0.95))
            .clipShape(bubbleShape)
            .overlay(
                bubbleShape.stroke(isOutgoing ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
            )
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
                .font(TTFont.workSans(12, weight: .medium))
        }
        .foregroundStyle(muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }

    private var reactionPills: some View {
        HStack(spacing: 4) {
            ForEach(message.reactions, id: \.self) { emoji in
                Text(emoji)
                    .font(.system(size: 14))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, isOutgoing ? 0 : 34)
    }

    // MARK: - Shape / gestures / menu

    private var bubbleShape: UnevenRoundedRectangle {
        let out = isOutgoing
        switch cluster {
        case .isolated:
            return UnevenRoundedRectangle(
                topLeadingRadius: baseRadius,
                bottomLeadingRadius: out ? baseRadius : tightRadius,
                bottomTrailingRadius: out ? tightRadius : baseRadius,
                topTrailingRadius: baseRadius,
                style: .continuous
            )
        case .start:
            return UnevenRoundedRectangle(
                topLeadingRadius: baseRadius,
                bottomLeadingRadius: out ? baseRadius : tightRadius,
                bottomTrailingRadius: out ? tightRadius : baseRadius,
                topTrailingRadius: baseRadius,
                style: .continuous
            )
        case .middle:
            return UnevenRoundedRectangle(
                topLeadingRadius: out ? baseRadius : tightRadius,
                bottomLeadingRadius: out ? baseRadius : tightRadius,
                bottomTrailingRadius: out ? tightRadius : baseRadius,
                topTrailingRadius: out ? tightRadius : baseRadius,
                style: .continuous
            )
        case .end:
            return UnevenRoundedRectangle(
                topLeadingRadius: out ? baseRadius : tightRadius,
                bottomLeadingRadius: out ? baseRadius : tightRadius,
                bottomTrailingRadius: out ? tightRadius : baseRadius,
                topTrailingRadius: out ? tightRadius : baseRadius,
                style: .continuous
            )
        }
    }

    private var swipeReplyGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dx = value.translation.width
                if isOutgoing {
                    dragOffset = max(-48, min(0, dx))
                } else {
                    dragOffset = min(48, max(0, dx))
                }
            }
            .onEnded { _ in
                let fired = abs(dragOffset) >= 36
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    dragOffset = 0
                }
                if fired {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onReply?()
                }
            }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button { onReply?() } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        Button {
            UIPasteboard.general.string = message.text
            onCopy?()
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        Menu("React") {
            ForEach(["👍", "❤️", "😂", "😮", "😢", "🙏"], id: \.self) { emoji in
                Button(emoji) { onReact?(emoji) }
            }
        }
        if message.resolvedDelivery == .failed {
            Button { onRetry?() } label: { Label("Retry sending", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { onDelete?() } label: { Label("Delete", systemImage: "trash") }
        } else if isOutgoing {
            Button(role: .destructive) { onDelete?() } label: { Label("Delete for me", systemImage: "trash") }
        }
    }

    // MARK: - Text helpers

    private func shouldOfferReadMore(_ text: String) -> Bool {
        text.count > 4096 || text.components(separatedBy: "\n").count > 5
    }

    private func displayText(_ text: String) -> String {
        guard shouldOfferReadMore(text), !expanded else { return text }
        if text.count > 4096 { return String(text.prefix(4096)) }
        let lines = text.components(separatedBy: "\n")
        return lines.prefix(5).joined(separator: "\n")
    }

    /// WhatsApp-ish inline markers → markdown-ish AttributedString.
    private func whatsAppAttributed(_ text: String) -> AttributedString {
        var md = text
        md = md.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "**$1**", options: .regularExpression)
        md = md.replacingOccurrences(of: #"_([^_]+)_"#, with: "*$1*", options: .regularExpression)
        md = md.replacingOccurrences(of: #"~([^~]+)~"#, with: "~~$1~~", options: .regularExpression)
        if let parsed = try? AttributedString(
            markdown: md,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return parsed
        }
        return AttributedString(text)
    }

    private func placeholderThumb(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.06))
            .frame(width: 160, height: 120)
            .overlay(Image(systemName: systemName).foregroundStyle(muted))
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct HumanChatDatePill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(TTFont.workSans(11, weight: .medium))
            .foregroundStyle(Color(white: 0.35))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.06))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
    }
}

struct HumanChatTypingBubble: View {
    @State private var bounce = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(white: 0.55))
                        .frame(width: 6, height: 6)
                        .offset(y: bounce ? -3 : 0)
                        .animation(
                            .easeInOut(duration: 0.35)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.12),
                            value: bounce
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            Spacer()
        }
        .onAppear { bounce = true }
    }
}
