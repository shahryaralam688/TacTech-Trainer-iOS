import Foundation
import UIKit

// MARK: - Roles / modalities

enum CoachMessageRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

enum CoachModality: String, Codable, Hashable {
    case text
    case voice
    case image
}

enum CoachMessageStatus: Hashable {
    case sent
    case sending
    case analyzing
    case streaming
    case failed(String)
}

// MARK: - API DTOs (camelCase)

struct CoachProviderStatus: Codable, Hashable {
    var provider: String
    var chatConfigured: Bool
    var usingMockFallback: Bool?
    var ttsProvider: String
    var embedding: String
    var chatModel: String
    var visionModel: String?
    var supportsImages: Bool?
}

struct CoachConversation: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var role: String
    var createdAt: Date
    var updatedAt: Date
}

struct CoachCitation: Codable, Hashable, Identifiable {
    var id: String
    var sourceType: String
    var sourceId: String?
    var content: String
    var score: Double

    enum CodingKeys: String, CodingKey {
        case id, sourceType, sourceId, content, score
    }

    init(id: String = UUID().uuidString, sourceType: String, sourceId: String?, content: String, score: Double) {
        self.id = id
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.content = content
        self.score = score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        sourceType = (try? c.decode(String.self, forKey: .sourceType)) ?? "memory"
        sourceId = try? c.decodeIfPresent(String.self, forKey: .sourceId)
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        score = (try? c.decode(Double.self, forKey: .score)) ?? 0
    }
}

struct CoachMessage: Codable, Identifiable, Hashable {
    var id: String
    var conversationId: String
    var role: CoachMessageRole
    var content: String
    var modality: CoachModality
    var audioUrl: String?
    var imageUrl: String?
    var citations: [CoachCitation]?
    var createdAt: Date
}

struct CoachChatRequest: Encodable {
    var message: String
    var conversationId: String?
    var stream: Bool
}

struct CoachChatResponse: Decodable {
    var conversation: CoachConversation
    var userMessage: CoachMessage
    var assistantMessage: CoachMessage
}

struct CoachImageChatResponse: Decodable {
    var conversation: CoachConversation
    var userMessage: CoachMessage
    var assistantMessage: CoachMessage
    var imageAnalysis: String?
}

struct CoachMemorySyncResult: Decodable {
    var chunkCount: Int
    var userId: String
}

struct CoachVoiceTurnResponse: Decodable {
    var conversation: CoachConversation
    var transcript: String
    var userMessage: CoachMessage
    var assistantMessage: CoachMessage
    var audioUrl: String?
}

struct CoachRtcIceServer: Codable, Hashable {
    var urls: [String]
}

struct CoachRtcSession: Decodable, Identifiable, Hashable {
    var id: String
    var conversationId: String?
    var status: String
    var iceServers: [CoachRtcIceServer]
    var signalingPath: String
    var createdAt: Date
}

// MARK: - SSE events

enum CoachStreamEvent {
    case user(conversationId: String, message: CoachMessage)
    case delta(String)
    case done(message: CoachMessage, citations: [CoachCitation]?)
    case unknown
}

struct CoachStreamEventDTO: Decodable {
    var event: String
    var conversationId: String?
    var text: String?
    var message: CoachMessage?
    var citations: [CoachCitation]?
}

// MARK: - Display message (optimistic UI)

struct CoachDisplayMessage: Identifiable, Hashable {
    let id: String
    var serverId: String?
    var role: CoachMessageRole
    var content: String
    var modality: CoachModality
    var audioUrl: String?
    var imageUrl: String?
    /// Local JPEG preview before server URL arrives (not hashed for Equatable via identity).
    var localImageData: Data?
    var citations: [CoachCitation]?
    var createdAt: Date
    var status: CoachMessageStatus
    /// JPEG payload for retry after failed image upload.
    var retryJPEG: Data?
    var retryCaption: String?

    var localImage: UIImage? {
        guard let localImageData else { return nil }
        return UIImage(data: localImageData)
    }

    static func fromServer(_ message: CoachMessage) -> CoachDisplayMessage {
        CoachDisplayMessage(
            id: message.id,
            serverId: message.id,
            role: message.role,
            content: message.content,
            modality: message.modality,
            audioUrl: message.audioUrl,
            imageUrl: message.imageUrl,
            localImageData: nil,
            citations: message.citations,
            createdAt: message.createdAt,
            status: .sent,
            retryJPEG: nil,
            retryCaption: nil
        )
    }
}

enum CoachImageCaptionChip: String, CaseIterable, Identifiable {
    case form = "Check my form"
    case meal = "Analyze this meal"
    case progress = "Progress photo feedback"
    case see = "What do you see?"

    var id: String { rawValue }
}
