import Foundation
import UIKit

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
    let id: String
    var name: String
    var role: HumanChatAudience
    var avatarUrl: String?
}

struct HumanChatMessage: Identifiable, Hashable, Codable {
    let id: String
    let peerId: String
    /// True when the current user sent it.
    var isOutgoing: Bool
    var kind: HumanChatMessageKind
    var text: String
    var sentAt: Date
    var isRead: Bool
    /// Relative path under chat media directory, or absolute file URL string for local drafts.
    var localMediaPath: String?
    var remoteMediaUrl: String?
    var attachmentKind: HumanChatAttachmentKind?
    var durationSeconds: Double?
    var callOutcome: String?

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

extension HumanChatMessage {
    static func text(peerId: String, outgoing: Bool, body: String) -> HumanChatMessage {
        HumanChatMessage(
            id: UUID().uuidString,
            peerId: peerId,
            isOutgoing: outgoing,
            kind: .text,
            text: body,
            sentAt: .now,
            isRead: outgoing
        )
    }
}
