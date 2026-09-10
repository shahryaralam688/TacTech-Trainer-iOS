import Foundation

struct AppNotificationDTO: Identifiable, Decodable, Equatable, Hashable {
    var id: String
    var type: String
    var title: String
    var body: String
    var data: [String: String]
    var readAt: Date?
    var createdAt: Date

    var isUnread: Bool { readAt == nil }

    var threadId: String? { data["threadId"] }
    var messageId: String? { data["messageId"] }
    var sessionId: String? { data["sessionId"] }
    var fromUserId: String? { data["fromUserId"] }
    var fromName: String? { data["fromName"] }
    var signalingPath: String? { data["signalingPath"] }

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, data, readAt, createdAt
    }

    init(
        id: String,
        type: String,
        title: String,
        body: String,
        data: [String: String] = [:],
        readAt: Date? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.data = data
        self.readAt = readAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if let dict = try? c.decode([String: String].self, forKey: .data) {
            data = dict
        } else if let raw = try? c.decode([String: FlexibleJSONScalar].self, forKey: .data) {
            data = raw.compactMapValues(\.stringValue)
        } else {
            data = [:]
        }
        // Some backends nest type inside data only — keep top-level type authoritative.
        if data["type"] == nil {
            var merged = data
            merged["type"] = type
            data = merged
        }
    }
}

struct AppNotificationPage: Decodable {
    var items: [AppNotificationDTO]
    var nextCursor: String?
    var unreadCount: Int?
}

struct NotificationUnreadCountOut: Decodable {
    var unreadCount: Int
}

struct NotificationReadRequest: Encodable {
    var notificationId: String?
}

struct NotificationPreferencesDTO: Codable, Equatable {
    var push: Bool = true
    var aiCoach: Bool = false
    var metrics: Bool = true
    var vibrations: Bool = false
    var sound: Bool = true
    var appUpdate: Bool = true
    var resources: Bool = false
    var offersDevice: Bool = false
    var chatMessages: Bool = true
    var chatCalls: Bool = true
}

struct PushTokenRegisterRequest: Encodable {
    var token: String
    var platform: String = "ios"
    var deviceName: String?
    var appVersion: String?
}

struct PushTokenDeleteRequest: Encodable {
    var token: String
}

struct PushTokenOut: Decodable {
    var id: String
    var platform: String
    var deviceName: String?
    var appVersion: String?
    var createdAt: Date
    var updatedAt: Date
}

/// Loose JSON scalar for notification `data` maps.
enum FlexibleJSONScalar: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return nil
        }
    }
}
