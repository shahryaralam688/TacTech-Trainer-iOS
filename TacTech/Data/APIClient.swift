import Foundation
import Security

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

actor APIClient {
    /// One shared, non-fail-fast client for screens and services (the launch / sign-in flavour keeps its own instance).
    static let shared = APIClient()

    private let failFast: Bool
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    /// `failFast`: the launch / sign-in flavour (no waiting for connectivity, `TTNetworkTiming` limits, 5xx → `LaunchServerError`).
    init(failFast: Bool = false) {
        self.failFast = failFast
        let configuration: URLSessionConfiguration
        if failFast {
            configuration = TTNetworkTiming.failFastConfiguration()
        } else {
            configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.waitsForConnectivity = true
        }
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder.tactech
        encoder = JSONEncoder.tactech
    }

    var encodedTZ: String {
        TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "UTC"
    }

    func sendArray<T: Decodable>(_ path: String) async throws -> [T] {
        let data = try await raw(path: path, method: .get, body: Optional<EmptyBody>.none, authorized: true)
        if data.isEmpty { return [] }
        if let items = try? decoder.decode([T].self, from: data) { return items }
        if let wrapped = try? decoder.decode(ListEnvelope<T>.self, from: data) {
            return wrapped.values
        }
        throw AppError.api("Could not decode \(T.self) list.")
    }

    func send<T: Decodable>(path: String, method: HTTPMethod) async throws -> T {
        let data = try await raw(path: path, method: method, body: Optional<EmptyBody>.none, authorized: true)
        return try decode(T.self, from: data)
    }

    func sendVoid<B: Encodable>(path: String, method: HTTPMethod, body: B) async throws {
        _ = try await raw(path: path, method: method, body: body, authorized: true)
    }

    enum MultipartFormField {
        case text(name: String, value: String)
        case file(name: String, filename: String, mimeType: String, data: Data)
    }

    func sendMultipart<T: Decodable>(
        path: String,
        fields: [MultipartFormField],
        allowRetry: Bool = true
    ) async throws -> T {
        try await AuthTokenRefresher.shared.refreshIfExpiring()
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard let token = TokenStore.accessToken() else { throw AppError.unauthorized }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = buildMultipartBody(fields: fields, boundary: boundary)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Invalid response from server.")
        }
        if http.statusCode == 401, allowRetry {
            try await AuthTokenRefresher.shared.refresh()
            return try await sendMultipart(path: path, fields: fields, allowRetry: false)
        }
        if !(200...299).contains(http.statusCode) {
            if http.statusCode == 401 {
                TokenStore.clear()
                throw AppError.unauthorized
            }
            if http.statusCode == 404 {
                throw AppError.notFound(Self.detail(from: data) ?? "Not found.")
            }
            throw AppError.api(Self.detail(from: data) ?? "Request failed (\(http.statusCode)).")
        }
        return try decode(T.self, from: data)
    }

    private func buildMultipartBody(fields: [MultipartFormField], boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        for field in fields {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            switch field {
            case let .text(name, value):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
                body.append("\(value)\(crlf)".data(using: .utf8)!)
            case let .file(name, filename, mimeType, data):
                body.append(
                    "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!
                )
                body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
                body.append(data)
                body.append(crlf.data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    func sendOptional<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B) async throws -> T? {
        let data = try await raw(path: path, method: method, body: body, authorized: true)
        if data.isEmpty { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func send<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B) async throws -> T {
        let data = try await raw(path: path, method: method, body: body, authorized: true)
        if data.isEmpty, T.self == EmptyResponse.self || T.self == Optional<EmptyResponse>.self {
            guard let empty = EmptyResponse() as? T else { throw AppError.api("Unexpected empty response.") }
            return empty
        }
        if T.self == Optional<EmptyResponse>.self {
            let none: Any = Optional<EmptyResponse>.none as Any
            guard let value = none as? T else { throw AppError.api("Unexpected empty response.") }
            return value
        }
        return try decode(T.self, from: data)
    }

    func sendUnauthenticated<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B) async throws -> T {
        let data = try await raw(path: path, method: method, body: body, authorized: false)
        return try decode(T.self, from: data)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if data.isEmpty, type == Optional<EmptyResponse>.self {
            let none: Any = Optional<EmptyResponse>.none as Any
            guard let value = none as? T else { throw AppError.api("Unexpected empty response.") }
            return value
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.api(Self.detail(from: data) ?? error.localizedDescription)
        }
    }

    func raw<B: Encodable>(path: String, method: HTTPMethod, body: B?, authorized: Bool, allowRetry: Bool = true) async throws -> Data {
        if authorized {
            try await AuthTokenRefresher.shared.refreshIfExpiring()
        }

        var request = try makeRequest(path: path, method: method, authorized: authorized)
        if let body, method != .get {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Invalid response from server.")
        }

        if http.statusCode == 401, authorized, allowRetry {
            try await AuthTokenRefresher.shared.refresh()
            return try await raw(path: path, method: method, body: body, authorized: authorized, allowRetry: false)
        }

        if (200...299).contains(http.statusCode) {
            return data
        }

        if http.statusCode == 401 {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        if failFast, http.statusCode >= 500 { throw LaunchServerError(status: http.statusCode) }
        let detail = Self.detail(from: data)
        let code = Self.code(from: data)
        if http.statusCode == 402 || code == "AI_REQUIRED" || code == "AI_QUOTA_EXCEEDED" {
            throw AppError.aiRequired(detail ?? "AI Coach Pro is required.")
        }
        if http.statusCode == 501 || http.statusCode == 503 || code == "AI_CAPABILITY_UNAVAILABLE" {
            throw AppError.aiUnavailable(detail ?? "This AI feature is coming soon.")
        }
        if code == "AI_PROVIDER_NOT_CONFIGURED" {
            throw AppError.aiUnavailable(detail ?? "AI is not configured yet. Coming soon.")
        }
        if http.statusCode == 409 || code == "CONFLICT" || code == "HAS_TRAINER" {
            throw AppError.conflict(
                detail
                    ?? (code == "HAS_TRAINER"
                        ? "You already have a trainer. Use their assigned plan."
                        : "This Apple subscription is already linked to another TacTech account. Sign in with that account or contact support.")
            )
        }
        if http.statusCode == 502 || code == "PROVIDER_ERROR" {
            throw AppError.providerError(detail ?? "Payment provider error — try again")
        }
        if http.statusCode == 400 || code == "VALIDATION" || code == "VALIDATION_ERROR" {
            throw AppError.validation(detail ?? "Invalid request.")
        }
        if http.statusCode == 403 {
            if code == "PLAN_LOCKED" {
                throw AppError.forbidden(
                    detail ?? "This plan was assigned by your trainer and can’t be edited."
                )
            }
            throw AppError.forbidden(detail ?? "Not allowed.")
        }
        if http.statusCode == 404 {
            throw AppError.notFound(detail ?? "Not found.")
        }
        throw AppError.api(detail ?? "Request failed (\(http.statusCode)).")
    }

    private func makeRequest(path: String, method: HTTPMethod, authorized: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        if method == .post || method == .put || method == .patch || method == .delete {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let token = TokenStore.accessToken() else { throw AppError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func detail(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = object["detail"] as? String { return detail }
            if let detail = object["detail"] as? [[String: Any]] {
                let messages = detail.compactMap { $0["msg"] as? String }
                if !messages.isEmpty { return messages.joined(separator: " ") }
            }
            if let message = object["message"] as? String { return message }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func code(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["code"] as? String
    }
}

struct EmptyBody: Encodable {}
struct EmptyResponse: Decodable {}

struct ListEnvelope<T: Decodable>: Decodable {
    var items: [T]?
    var data: [T]?
    var results: [T]?

    var values: [T] { items ?? data ?? results ?? [] }
}

enum TokenStore {
    private static let service = "com.tactech.trainer"
    private static let accessAccount = "accessToken"
    private static let refreshAccount = "refreshToken"

    static func save(accessToken: String, refreshToken: String) {
        write(account: accessAccount, value: accessToken)
        write(account: refreshAccount, value: refreshToken)
    }

    static func accessToken() -> String? { read(account: accessAccount) }
    static func refreshToken() -> String? { read(account: refreshAccount) }

    static func clear() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
        clearExpiry()
    }

    private static func write(account: String, value: String) {
        delete(account: account)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension JSONDecoder {
    private static let sharedTactechDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Date.tactech(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(value)")
        }
        return decoder
    }()

    static var tactech: JSONDecoder { sharedTactechDecoder }
}

extension Date {
    private static let tactechDateLock = NSLock()

    private static let tactechISOFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let tactechISOStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let tactechFallbackFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd"
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    static func tactech(from value: String) -> Date? {
        tactechDateLock.lock()
        defer { tactechDateLock.unlock() }
        if let date = tactechISOFractional.date(from: value) { return date }
        if let date = tactechISOStandard.date(from: value) { return date }
        for formatter in tactechFallbackFormatters {
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

extension JSONEncoder {
    static var tactech: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension AppError {
    var isNotFound: Bool {
        if case .notFound = self { return true }
        return false
    }

    var isForbidden: Bool {
        if case .forbidden = self { return true }
        return false
    }
}
