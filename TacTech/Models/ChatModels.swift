import Foundation

// MARK: - API DTOs (camelCase from backend)

struct ChatThreadDTO: Codable, Identifiable, Hashable {
    let id: String
    var peerUserId: String
    var peerName: String?
    var peerAvatarUrl: String?
    var lastMessagePreview: String?
    var lastMessageAt: Date?
    var unreadCount: Int?
    var peerRole: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct ChatThreadsResponse: Decodable {
    var items: [ChatThreadDTO]
}

struct ChatMessageDTO: Codable, Identifiable, Hashable {
    let id: String
    var threadId: String
    var senderUserId: String
    var senderRole: String?
    var kind: String?
    var text: String?
    var attachmentUrl: String?
    var attachmentType: String?
    var durationSeconds: Double?
    var callOutcome: String?
    var clientId: String?
    var createdAt: Date
    var readAt: Date?
}

struct ChatMessagesResponse: Decodable {
    var items: [ChatMessageDTO]
    var nextCursor: String?
}

struct ChatCreateThreadRequest: Encodable {
    var peerUserId: String?
    var peerTraineeProfileId: String?
    var peerTrainerProfileId: String?
}

struct ChatSendTextRequest: Encodable {
    var text: String
    var clientId: String
}

struct ChatCallEventRequest: Encodable {
    var kind: String = "call_event"
    var callOutcome: String
    var clientId: String
}

struct ChatReadRequest: Encodable {
    var upToMessageId: String
}

struct ChatReadResponse: Decodable {
    var threadId: String?
    var upToMessageId: String?
    var unreadCount: Int?
}

struct ChatRtcSessionDTO: Decodable {
    var id: String
    var threadId: String?
    var signalingPath: String
    var iceServers: [ChatRtcIceServer]?
    var createdAt: Date?
}

struct ChatIncomingCallDTO: Codable, Identifiable, Hashable {
    var id: String { sessionId }
    var threadId: String
    var sessionId: String
    var fromUserId: String
    var fromName: String
    var signalingPath: String
    var createdAt: Date
}

struct ChatIncomingCallsResponse: Decodable {
    var items: [ChatIncomingCallDTO]
}

struct ChatRtcIceServer: Codable, Hashable {
    var urls: [String]?
    var url: String?
    var username: String?
    var credential: String?
}

struct ChatCreateRtcRequest: Encodable {
    var threadId: String
}

// MARK: - Display mapping

extension HumanChatMessage {
    static func from(api: ChatMessageDTO, currentUserId: String, peerUserId: String) -> HumanChatMessage {
        let isOutgoing = api.senderUserId == currentUserId
        let kind = mappedKind(api)
        let attachment = mappedAttachment(api.attachmentType)
        return HumanChatMessage(
            id: api.id,
            peerId: peerUserId,
            isOutgoing: isOutgoing,
            kind: kind,
            text: api.text ?? "",
            sentAt: api.createdAt,
            isRead: api.readAt != nil || isOutgoing,
            localMediaPath: nil,
            remoteMediaUrl: api.attachmentUrl,
            attachmentKind: attachment,
            durationSeconds: api.durationSeconds,
            callOutcome: api.callOutcome,
            clientId: api.clientId,
            threadId: api.threadId
        )
    }

    private static func mappedKind(_ api: ChatMessageDTO) -> HumanChatMessageKind {
        let kind = (api.kind ?? "").lowercased()
        if kind == "call_event" || kind == "callevent" { return .callEvent }
        switch (api.attachmentType ?? "").lowercased() {
        case "image": return .image
        case "video": return .video
        case "voice": return .voice
        case "file": return .image // show as generic attachment thumb via URL if needed
        default:
            if kind == "attachment" { return .image }
            return .text
        }
    }

    private static func mappedAttachment(_ raw: String?) -> HumanChatAttachmentKind? {
        switch (raw ?? "").lowercased() {
        case "image": return .image
        case "video": return .video
        case "voice": return .voice
        case "file": return .file
        default: return nil
        }
    }
}

extension HumanChatPeer {
    init(from thread: ChatThreadDTO) {
        let role: HumanChatAudience = (thread.peerRole ?? "").lowercased() == "trainer" ? .trainer : .trainee
        self.init(
            id: thread.peerUserId,
            name: thread.peerName ?? "Chat",
            role: role,
            avatarUrl: thread.peerAvatarUrl,
            profileId: nil,
            threadId: thread.id,
            lastPreview: thread.lastMessagePreview,
            lastAt: thread.lastMessageAt,
            unreadCount: thread.unreadCount ?? 0
        )
    }
}
