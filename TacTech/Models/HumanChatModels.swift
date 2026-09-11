import Foundation

/// Trainer ↔ trainee messaging (WhatsApp-like modalities, AI chat chrome).
enum HumanChatAudience: String, Codable, Hashable {
    case trainer
    case trainee
}

enum HumanChatAttachmentKind: String, Codable, Hashable {
    case image
    case video
    case voice
    case file
}

enum HumanChatMessageKind: String, Codable, Hashable {
    case text
    case image
    case video
    case voice
    case callEvent
}

/// Outgoing delivery lifecycle (WhatsApp-style ticks). Delivered reserved until backend emits ACK.
enum HumanChatDeliveryStatus: String, Codable, Hashable {
    case pending
    case sent
    case delivered
    case read
    case failed
}

struct HumanChatPeer: Identifiable, Hashable, Codable {
    /// Canonical = backend `peerUserId` (`User.id`).
    let id: String
    var name: String
    var role: HumanChatAudience
    var avatarUrl: String?
    /// Local roster profile id (TraineeProfile.id / TrainerProfile.id) — optional resolve helper.
    var profileId: String?
    var threadId: String?
    var lastPreview: String?
    var lastAt: Date?
    var unreadCount: Int = 0
}

struct HumanChatReplyDraft: Hashable, Equatable {
    var messageId: String
    var senderName: String
    var snippet: String
}

struct HumanChatMessage: Identifiable, Hashable, Codable {
    let id: String
    /// Peer user id for this thread (not always sender).
    let peerId: String
    var isOutgoing: Bool
    var kind: HumanChatMessageKind
    var text: String
    var sentAt: Date
    var isRead: Bool
    var localMediaPath: String?
    var remoteMediaUrl: String?
    var attachmentKind: HumanChatAttachmentKind?
    var durationSeconds: Double?
    var callOutcome: String?
    var clientId: String?
    var threadId: String?

    /// Local / derived delivery ticks for outgoing messages.
    var deliveryStatus: HumanChatDeliveryStatus = .sent
    /// Reply quote (local UI; sent as plain text context until backend adds replyTo).
    var replyToId: String?
    var replyToText: String?
    var replyToName: String?
    /// Local-only reaction emojis on this bubble.
    var reactions: [String] = []

    var previewText: String {
        switch kind {
        case .text:
            return text.isEmpty ? "Message" : text
        case .image:
            return text.isEmpty ? "📷 Photo" : "📷 \(text)"
        case .video:
            return text.isEmpty ? "🎬 Video" : "🎬 \(text)"
        case .voice:
            let secs = Int((durationSeconds ?? 0).rounded())
            return "🎤 Voice note\(secs > 0 ? " · \(secs)s" : "")"
        case .callEvent:
            if let outcome = callOutcome, CallInviteCodec.parse(outcome: outcome) != nil {
                return "📞 Video call"
            }
            if let outcome = callOutcome, CallInviteCodec.isEndMarker(outcome) {
                return "📞 Call ended"
            }
            return callOutcome ?? "📞 Call"
        }
    }

    var resolvedDelivery: HumanChatDeliveryStatus {
        if !isOutgoing { return .read }
        if deliveryStatus == .failed { return .failed }
        if isRead || deliveryStatus == .read { return .read }
        if id.hasPrefix("local-") { return .pending }
        return deliveryStatus
    }
}

// MARK: - Thread layout helpers (grouping + dates)

enum HumanChatClusterRole: Equatable {
    case isolated
    case start
    case middle
    case end
}

enum HumanChatThreadItem: Identifiable, Equatable {
    case date(id: String, label: String)
    case typing(id: String)
    case message(HumanChatMessage, cluster: HumanChatClusterRole, showAvatar: Bool)

    var id: String {
        switch self {
        case .date(let id, _): return "date-\(id)"
        case .typing(let id): return "typing-\(id)"
        case .message(let m, _, _): return m.id
        }
    }
}

enum HumanChatThreadBuilder {
    static let groupWindow: TimeInterval = 60

    static func items(
        messages: [HumanChatMessage],
        peerTyping: Bool,
        calendar: Calendar = .current
    ) -> [HumanChatThreadItem] {
        var result: [HumanChatThreadItem] = []
        var lastDay: DateComponents?

        for (index, message) in messages.enumerated() {
            let day = calendar.dateComponents([.year, .month, .day], from: message.sentAt)
            if day != lastDay {
                let label = dateLabel(for: message.sentAt, calendar: calendar)
                let key = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
                result.append(.date(id: key, label: label))
                lastDay = day
            }

            let prev = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let cluster = clusterRole(message: message, previous: prev, next: next)
            let showAvatar = !message.isOutgoing && (cluster == .isolated || cluster == .end)
            result.append(.message(message, cluster: cluster, showAvatar: showAvatar))
        }

        if peerTyping {
            result.append(.typing(id: "live"))
        }
        return result
    }

    static func clusterRole(
        message: HumanChatMessage,
        previous: HumanChatMessage?,
        next: HumanChatMessage?
    ) -> HumanChatClusterRole {
        let withPrev = sameCluster(message, previous)
        let withNext = sameCluster(message, next)
        switch (withPrev, withNext) {
        case (false, false): return .isolated
        case (false, true): return .start
        case (true, true): return .middle
        case (true, false): return .end
        }
    }

    private static func sameCluster(_ a: HumanChatMessage, _ b: HumanChatMessage?) -> Bool {
        guard let b else { return false }
        guard a.isOutgoing == b.isOutgoing else { return false }
        guard a.kind != .callEvent, b.kind != .callEvent else { return false }
        return abs(a.sentAt.timeIntervalSince(b.sentAt)) <= groupWindow
    }

    static func dateLabel(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func spacing(before item: HumanChatThreadItem, previous: HumanChatThreadItem?) -> CGFloat {
        guard let previous else { return 8 }
        switch (previous, item) {
        case (.message(_, let prevCluster, _), .message(_, let cluster, _)):
            if prevCluster == .start || prevCluster == .middle,
               cluster == .middle || cluster == .end {
                return 2
            }
            return 9
        case (.date, _):
            return 10
        default:
            return 8
        }
    }
}
