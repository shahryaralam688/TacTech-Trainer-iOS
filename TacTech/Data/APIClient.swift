import Foundation
import Security

struct APIUser: Codable, Hashable {
    var id: String
    var name: String
    var email: String
    var role: UserRole
    var createdAt: Date

    func asUser() -> User {
        User(id: id, name: name, email: email, password: "", role: role, createdAt: createdAt)
    }
}

struct AuthResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String?
    var expiresIn: Int?
    var user: APIUser
    var trainer: TrainerProfile?
    var trainee: TraineeProfile?
}

struct MeResponse: Decodable {
    var user: APIUser?
    var trainer: TrainerProfile?
    var trainee: TraineeProfile?
    var accessToken: String?
    var refreshToken: String?
    var id: String?
    var name: String?
    var email: String?
    var role: UserRole?
    var createdAt: Date?

    var resolvedUser: APIUser? {
        if let user { return user }
        guard let id, let name, let email, let role, let createdAt else { return nil }
        return APIUser(id: id, name: name, email: email, role: role, createdAt: createdAt)
    }
}

struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String?
    var expiresIn: Int?
}

struct TraineeListItem: Decodable {
    var trainee: TraineeProfile?
    var user: APIUser?
    var assignedPlan: WorkoutPlan?
    var id: String?
    var userId: String?
    var trainerId: String?
    var goal: String?
    var heightCm: Int?
    var weightKg: Double?
    var dailyCalorieTarget: Int?
    var name: String?
    var email: String?

    var profile: TraineeProfile? {
        if let trainee { return trainee }
        guard let id, let userId else { return nil }
        return TraineeProfile(
            id: id,
            userId: userId,
            trainerId: trainerId,
            goal: goal ?? "",
            heightCm: heightCm ?? 0,
            weightKg: weightKg ?? 0,
            dailyCalorieTarget: dailyCalorieTarget ?? 0
        )
    }
}

struct TrainerWithUser: Decodable {
    var trainer: TrainerProfile?
    var user: APIUser?
    var id: String?
    var userId: String?
    var inviteCode: String?
    var specialty: String?
    var yearsExperience: Int?
    var bio: String?
    var name: String?
    var email: String?

    var profile: TrainerProfile? {
        if let trainer { return trainer }
        guard let id, let userId, let inviteCode else { return nil }
        return TrainerProfile(
            id: id,
            userId: userId,
            inviteCode: inviteCode,
            specialty: specialty ?? "",
            yearsExperience: yearsExperience ?? 0,
            bio: bio ?? ""
        )
    }
}

struct FoodLookupDTO: Codable {
    var name: String
    var keywords: [String]?
    var per100g: MacroEstimate

    func asFood() -> FoodKnowledge {
        FoodKnowledge(name: name, keywords: keywords ?? [], per100g: per100g)
    }
}

struct SignupBody: Encodable {
    var name: String
    var email: String
    var password: String
    var role: String
    var inviteCode: String?
}

struct LoginBody: Encodable {
    var email: String
    var password: String
}

struct ForgotPasswordBody: Encodable {
    var email: String
}

struct RefreshBody: Encodable {
    var refreshToken: String
}

struct LinkTrainerBody: Encodable {
    var inviteCode: String
}

struct AssignPlanBody: Encodable {
    var planId: String
    var traineeId: String
}

struct FeedbackBody: Encodable {
    var traineeId: String
    var message: String
    var relatedExerciseId: String?
}

struct MealBody: Encodable {
    var name: String
    var eatenAt: Date?
    var portionGrams: Double
    var macros: MacroEstimate
    var source: String
    var isEstimate: Bool
}

struct WorkoutSetBody: Encodable {
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double
}

struct WorkoutLogBody: Encodable {
    var planId: String
    var completedAt: Date?
    var durationMinutes: Int
    var sets: [WorkoutSetBody]
}

struct FormReportBody: Encodable {
    var exerciseId: String
    var score: Int
    var cues: [String]
    var repCount: Int
    var createdAt: Date?
}

struct PrescribedSetBody: Encodable {
    var setNumber: Int
    var reps: Int
    var weightKg: Double?
    var rpe: Double?
}

struct PlanExerciseBody: Encodable {
    var exerciseId: String
    var sets: Int
    var reps: Int
    var restSeconds: Int
    var recommendedWeightKg: Double?
    var tempo: String?
    var rpe: Double?
    var notes: String?
    var side: String?
    var prescribedSets: [PrescribedSetBody]
}

struct PlanDayBody: Encodable {
    var weekday: String
    var startTime: String?
    var title: String
    var focus: String
    var durationMinutes: Int
    var location: String?
    var warmup: String?
    var cooldown: String?
    var coachNotes: String?
    var exercises: [PlanExerciseBody]
}

struct PlanBody: Encodable {
    var title: String
    var focus: String
    var durationMinutes: Int
    var level: String
    var daysPerWeek: Int
    var notes: String?
    var exercises: [PlanExerciseBody]
    var days: [PlanDayBody]

    init(plan: WorkoutPlan) {
        title = plan.title
        focus = plan.focus
        durationMinutes = plan.durationMinutes
        level = plan.level
        daysPerWeek = plan.daysPerWeek
        notes = plan.notes
        exercises = (plan.exercises.isEmpty ? plan.allExercises : plan.exercises).map(PlanExerciseBody.init)
        days = plan.days.map(PlanDayBody.init)
    }
}

extension PlanExerciseBody {
    init(_ exercise: WorkoutExercise) {
        exerciseId = exercise.exerciseId
        sets = exercise.sets
        reps = exercise.reps
        restSeconds = exercise.restSeconds
        recommendedWeightKg = exercise.recommendedWeightKg
        tempo = exercise.tempo
        rpe = exercise.rpe
        notes = exercise.notes
        side = exercise.side
        prescribedSets = exercise.workingSets.map {
            PrescribedSetBody(setNumber: $0.setNumber, reps: $0.reps, weightKg: $0.weightKg, rpe: $0.rpe)
        }
    }
}

extension PlanDayBody {
    init(_ day: PlanDay) {
        weekday = day.weekday.rawValue
        startTime = day.startTime
        title = day.title
        focus = day.focus
        durationMinutes = day.durationMinutes
        location = day.location
        warmup = day.warmup
        cooldown = day.cooldown
        coachNotes = day.coachNotes
        exercises = day.exercises.map(PlanExerciseBody.init)
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
}

actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var refreshTask: Task<Void, Error>?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder.tactech
        encoder = JSONEncoder.tactech
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await sendUnauthenticated(
            path: "/auth/login",
            method: .post,
            body: LoginBody(email: email, password: password)
        )
    }

    func signup(_ body: SignupBody) async throws -> AuthResponse {
        try await sendUnauthenticated(path: "/auth/signup", method: .post, body: body)
    }

    func requestPasswordReset(email: String) async throws {
        _ = try await raw(
            path: "/auth/forgot-password",
            method: .post,
            body: ForgotPasswordBody(email: email),
            authorized: false
        )
    }

    func me() async throws -> MeResponse {
        try await send(path: "/me", method: .get)
    }

    func logout(refreshToken: String) async {
        _ = try? await sendUnauthenticated(
            path: "/auth/logout",
            method: .post,
            body: RefreshBody(refreshToken: refreshToken)
        ) as EmptyResponse?
    }

    func exercises() async throws -> [Exercise] {
        try await sendArray("/exercises")
    }

    func trainerPlans() async throws -> [WorkoutPlan] {
        try await sendArray("/trainer/plans")
    }

    func createPlan(_ body: PlanBody) async throws -> WorkoutPlan? {
        try await sendOptional(path: "/trainer/plans", method: .post, body: body)
    }

    func assignPlan(planId: String, traineeId: String) async throws {
        try await sendVoid(
            path: "/trainer/assignments",
            method: .post,
            body: AssignPlanBody(planId: planId, traineeId: traineeId)
        )
    }

    func trainerTrainees() async throws -> [TraineeListItem] {
        try await sendArray("/trainer/trainees")
    }

    func trainerTrainee(id: String) async throws -> TraineeListItem {
        try await send(path: "/trainer/trainees/\(id)", method: .get)
    }

    func trainerMeals(traineeId: String, on date: Date) async throws -> [Meal] {
        try await sendArray("/trainer/trainees/\(traineeId)/meals?on=\(APIConfig.dateQuery(date))")
    }

    func trainerMacros(traineeId: String, on date: Date) async throws -> MacroEstimate {
        try await send(path: "/trainer/trainees/\(traineeId)/macros?on=\(APIConfig.dateQuery(date))", method: .get)
    }

    func trainerLogs(traineeId: String) async throws -> [WorkoutLog] {
        try await sendArray("/trainer/trainees/\(traineeId)/logs")
    }

    func trainerFormReports(traineeId: String) async throws -> [FormReport] {
        try await sendArray("/trainer/trainees/\(traineeId)/form-reports")
    }

    func trainerFeedback(traineeId: String) async throws -> [TrainerFeedback] {
        try await sendArray("/trainer/trainees/\(traineeId)/feedback")
    }

    func sendFeedback(_ body: FeedbackBody) async throws -> TrainerFeedback? {
        try await sendOptional(path: "/trainer/feedback", method: .post, body: body)
    }

    func linkTrainer(inviteCode: String) async throws {
        try await sendVoid(path: "/trainee/link", method: .post, body: LinkTrainerBody(inviteCode: inviteCode))
    }

    func traineeTrainer() async throws -> TrainerWithUser {
        try await send(path: "/trainee/trainer", method: .get)
    }

    func assignedPlan() async throws -> WorkoutPlan? {
        do {
            let data = try await raw(path: "/trainee/assigned-plan", method: .get, body: Optional<EmptyBody>.none, authorized: true)
            if data.isEmpty { return nil }
            if let plan = try? decoder.decode(WorkoutPlan.self, from: data) { return plan }
            return nil
        } catch let error as AppError where error.isNotFound {
            return nil
        }
    }

    func traineeLogs() async throws -> [WorkoutLog] {
        try await sendArray("/trainee/logs")
    }

    func createWorkoutLog(_ body: WorkoutLogBody) async throws -> WorkoutLog? {
        try await sendOptional(path: "/trainee/logs", method: .post, body: body)
    }

    func traineeMeals(on date: Date) async throws -> [Meal] {
        try await sendArray("/trainee/meals?on=\(APIConfig.dateQuery(date))")
    }

    func createMeal(_ body: MealBody) async throws -> Meal? {
        try await sendOptional(path: "/trainee/meals", method: .post, body: body)
    }

    func traineeMacros(on date: Date) async throws -> MacroEstimate {
        try await send(path: "/trainee/macros?on=\(APIConfig.dateQuery(date))", method: .get)
    }

    func traineeFeedback() async throws -> [TrainerFeedback] {
        try await sendArray("/trainee/feedback")
    }

    func traineeFormReports() async throws -> [FormReport] {
        try await sendArray("/trainee/form-reports")
    }

    func createFormReport(_ body: FormReportBody) async throws -> FormReport? {
        try await sendOptional(path: "/trainee/form-reports", method: .post, body: body)
    }

    func lookupFood(query: String) async throws -> FoodKnowledge? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let path = "/food/lookup?q=\(encoded)"
        if let one = try? await send(path: path, method: .get) as FoodLookupDTO {
            return one.asFood()
        }
        let many: [FoodLookupDTO] = (try? await sendArray(path)) ?? []
        return many.first?.asFood()
    }

    private func sendArray<T: Decodable>(_ path: String) async throws -> [T] {
        let data = try await raw(path: path, method: .get, body: Optional<EmptyBody>.none, authorized: true)
        if data.isEmpty { return [] }
        if let items = try? decoder.decode([T].self, from: data) { return items }
        if let wrapped = try? decoder.decode(ListEnvelope<T>.self, from: data) {
            return wrapped.values
        }
        throw AppError.api("Could not decode \(T.self) list.")
    }

    private func send<T: Decodable>(path: String, method: HTTPMethod) async throws -> T {
        let data = try await raw(path: path, method: method, body: Optional<EmptyBody>.none, authorized: true)
        return try decode(T.self, from: data)
    }

    private func sendVoid<B: Encodable>(path: String, method: HTTPMethod, body: B) async throws {
        _ = try await raw(path: path, method: method, body: body, authorized: true)
    }

    private func sendOptional<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B) async throws -> T? {
        let data = try await raw(path: path, method: method, body: body, authorized: true)
        if data.isEmpty { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func send<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B) async throws -> T {
        let data = try await raw(path: path, method: method, body: body, authorized: true)
        if data.isEmpty, T.self == EmptyResponse.self || T.self == Optional<EmptyResponse>.self {
            return EmptyResponse() as! T
        }
        if T.self == Optional<EmptyResponse>.self {
            return Optional<EmptyResponse>.none as! T
        }
        return try decode(T.self, from: data)
    }

    private func sendUnauthenticated<T: Decodable, B: Encodable>(path: String, method: HTTPMethod, body: B) async throws -> T {
        let data = try await raw(path: path, method: method, body: body, authorized: false)
        return try decode(T.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if data.isEmpty, type == Optional<EmptyResponse>.self {
            return Optional<EmptyResponse>.none as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.api(Self.detail(from: data) ?? error.localizedDescription)
        }
    }

    private func raw<B: Encodable>(path: String, method: HTTPMethod, body: B?, authorized: Bool, allowRetry: Bool = true) async throws -> Data {
        if let refreshTask {
            _ = try? await refreshTask.value
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
            try await refreshTokens()
            return try await raw(path: path, method: method, body: body, authorized: authorized, allowRetry: false)
        }

        if (200...299).contains(http.statusCode) {
            return data
        }

        if http.statusCode == 401 {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        if http.statusCode == 404 {
            throw AppError.notFound(Self.detail(from: data) ?? "Not found.")
        }
        throw AppError.api(Self.detail(from: data) ?? "Request failed (\(http.statusCode)).")
    }

    private func refreshTokens() async throws {
        if let refreshTask {
            try await refreshTask.value
            return
        }
        let task = Task<Void, Error> {
            guard let refresh = TokenStore.refreshToken() else {
                TokenStore.clear()
                throw AppError.unauthorized
            }
            var request = try makeRequest(path: "/auth/refresh", method: .post, authorized: false)
            request.httpBody = try encoder.encode(RefreshBody(refreshToken: refresh))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                TokenStore.clear()
                throw AppError.unauthorized
            }
            if let tokens = try? decoder.decode(TokenResponse.self, from: data) {
                TokenStore.save(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken ?? refresh)
                return
            }
            if let auth = try? decoder.decode(AuthResponse.self, from: data) {
                TokenStore.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken)
                return
            }
            TokenStore.clear()
            throw AppError.unauthorized
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func makeRequest(path: String, method: HTTPMethod, authorized: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        if method == .post || method == .patch {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let token = TokenStore.accessToken() else { throw AppError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static func detail(from data: Data) -> String? {
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
    static var tactech: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Date.tactech(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(value)")
        }
        return decoder
    }
}

extension Date {
    static func tactech(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ] {
            formatter.dateFormat = format
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
}
