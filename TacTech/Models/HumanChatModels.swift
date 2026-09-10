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
            return callOutcome ?? "📞 Call"
        }
    }
}
