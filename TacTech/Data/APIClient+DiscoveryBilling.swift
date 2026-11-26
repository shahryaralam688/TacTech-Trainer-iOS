import Foundation

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
    var avatarUrl: String? = nil
    var avatarAsset: String? = nil

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
    var avatarUrl: String? = nil
    var avatarAsset: String? = nil

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

struct LinkTrainerBody: Encodable {
    var inviteCode: String
}

// MARK: - Join requests (invite → pending → accept/reject)

struct JoinRequestTrainerSummary: Codable, Hashable {
    let id: String
    let name: String
    let avatarUrl: String?
}

struct JoinRequestTraineeSummary: Codable, Hashable {
    let id: String
    let name: String
    let avatarUrl: String?
    let email: String?
}

struct JoinRequestDTO: Codable, Identifiable, Hashable {
    let id: String
    let status: String // pending | accepted | rejected | cancelled
    let inviteCode: String
    let message: String?
    let createdAt: String
    let updatedAt: String?
    let trainer: JoinRequestTrainerSummary?
    let trainee: JoinRequestTraineeSummary?

    var isPending: Bool { status.lowercased() == "pending" }
}

struct ActiveTrainerLinkDTO: Codable, Hashable {
    let trainerId: String
    let trainer: JoinRequestTrainerSummary
    let linkedAt: String?
}

struct TraineeJoinStateDTO: Codable {
    let activeLink: ActiveTrainerLinkDTO?
    let pendingRequest: JoinRequestDTO?
}

struct CreateJoinRequestBody: Encodable {
    let inviteCode: String
    let message: String?
}

struct RejectJoinRequestBody: Encodable {
    let reason: String?
}

extension APIClient {

    func trainerTrainees() async throws -> [TraineeListItem] {
        try await sendArray("/trainer/trainees")
    }

    func trainerTrainee(id: String) async throws -> TraineeListItem {
        try await send(path: "/trainer/trainees/\(id)", method: .get)
    }

    func linkTrainer(inviteCode: String) async throws {
        try await sendVoid(path: "/trainee/link", method: .post, body: LinkTrainerBody(inviteCode: inviteCode))
    }

    /// Trainee creates a join request (pending until trainer accepts). Prefer over instant `/trainee/link`.
    func createJoinRequest(_ body: CreateJoinRequestBody) async throws -> JoinRequestDTO {
        try await send(path: "/trainee/join-requests", method: .post, body: body)
    }

    func traineeJoinState() async throws -> TraineeJoinStateDTO {
        try await send(path: "/trainee/join-requests/mine", method: .get)
    }

    func cancelJoinRequest(id: String) async throws -> JoinRequestDTO {
        try await send(path: "/trainee/join-requests/\(id)/cancel", method: .post, body: EmptyBody())
    }

    func trainerJoinRequests(status: String = "pending") async throws -> [JoinRequestDTO] {
        let encoded = status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status
        return try await sendArray("/trainer/join-requests?status=\(encoded)")
    }

    func acceptJoinRequest(id: String) async throws {
        try await sendVoid(path: "/trainer/join-requests/\(id)/accept", method: .post, body: EmptyBody())
    }

    func rejectJoinRequest(id: String, reason: String? = nil) async throws {
        try await sendVoid(
            path: "/trainer/join-requests/\(id)/reject",
            method: .post,
            body: RejectJoinRequestBody(reason: reason)
        )
    }

    /// Trainee leaves their linked trainer (relationship ends; assigned plan cleared server-side).
    func unlinkTrainer() async throws {
        do {
            try await sendVoid(path: "/trainee/unlink", method: .post, body: EmptyBody())
        } catch {
            #if DEBUG
            Self.logRelationshipFailure(path: "POST /trainee/unlink", error: error)
            #endif
            throw error
        }
    }

    /// Trainer removes a trainee from their roster (relationship ends; assigned plan cleared server-side).
    func removeTrainee(traineeId: String) async throws {
        do {
            try await sendVoid(
                path: "/trainer/trainees/\(traineeId)/remove",
                method: .post,
                body: EmptyBody()
            )
        } catch {
            #if DEBUG
            Self.logRelationshipFailure(path: "POST /trainer/trainees/\(traineeId)/remove", error: error)
            #endif
            throw error
        }
    }

    #if DEBUG
    private static func logRelationshipFailure(path: String, error: Error) {
        if let app = error as? AppError {
            let kind: String
            switch app {
            case .notFound: kind = "404 notFound"
            case .conflict: kind = "409 conflict"
            case .unauthorized: kind = "401 unauthorized"
            case .validation: kind = "400 validation"
            case .api: kind = "api"
            default: kind = "other"
            }
            print("[TacTech] \(path) failed — \(kind): \(app.errorDescription ?? String(describing: app))")
        } else {
            print("[TacTech] \(path) failed: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Discovery / entitlements (Phase 1)

    func entitlements() async throws -> EntitlementsDTO {
        try await send(path: "/me/entitlements", method: .get)
    }

    func getMyCoachProfile() async throws -> CoachProfileDTO {
        try await send(path: "/me/coach-profile", method: .get)
    }

    func updateMyCoachProfile(_ body: CoachProfileUpdateBody) async throws -> CoachProfileDTO {
        try await send(path: "/me/coach-profile", method: .put, body: body)
    }

    func listCoaches(
        q: String? = nil,
        city: String? = nil,
        specialty: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> CoachListPage {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 50))")
        ]
        if let q = q?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            items.append(URLQueryItem(name: "q", value: q))
        }
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            items.append(URLQueryItem(name: "city", value: city))
        }
        if let specialty = specialty?.trimmingCharacters(in: .whitespacesAndNewlines), !specialty.isEmpty {
            items.append(URLQueryItem(name: "specialty", value: specialty))
        }
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await send(path: "/coaches\(query)", method: .get)
    }

    func coachDetail(id: String) async throws -> CoachProfileDTO {
        try await send(path: "/coaches/\(id)", method: .get)
    }

    func contactCoach(id: String, message: String?) async throws -> CoachContactResponse {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = CoachContactBody(message: (trimmed?.isEmpty == false) ? trimmed : nil)
        return try await send(path: "/coaches/\(id)/contact", method: .post, body: body)
    }

    // MARK: - Coach reviews (Phase 5)

    func createCoachReview(coachProfileId: String, stars: Int, body: String?) async throws -> CoachReview {
        try await send(
            path: "/coaches/\(coachProfileId)/reviews",
            method: .post,
            body: CoachReviewBody(stars: stars, body: Self.optionalReviewBody(body))
        )
    }

    func updateMyCoachReview(coachProfileId: String, stars: Int, body: String?) async throws -> CoachReview {
        try await send(
            path: "/coaches/\(coachProfileId)/reviews/me",
            method: .put,
            body: CoachReviewBody(stars: stars, body: Self.optionalReviewBody(body))
        )
    }

    func deleteMyCoachReview(coachProfileId: String) async throws {
        try await sendVoid(path: "/coaches/\(coachProfileId)/reviews/me", method: .delete, body: EmptyBody())
    }

    func listCoachReviews(
        coachProfileId: String,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> CoachReviewPage {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 50))")
        ]
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await send(path: "/coaches/\(coachProfileId)/reviews\(query)", method: .get)
    }

    func myCoachReview(coachProfileId: String) async throws -> MyCoachReviewResponse {
        try await send(path: "/coaches/\(coachProfileId)/reviews/me", method: .get)
    }

    func reportCoachReview(reviewId: String, reason: String) async throws -> ReviewReportResponse {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await send(
            path: "/coaches/reviews/\(reviewId)/report",
            method: .post,
            body: ReviewReportBody(reason: trimmed)
        )
    }

    private static func optionalReviewBody(_ body: String?) -> String? {
        let trimmed = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(1000))
    }

    // MARK: - Discovery analytics (Phase 6)

    func fetchCoachAnalytics(periodDays: Int = 30) async throws -> CoachAnalyticsResponse {
        let days = Self.clampedAnalyticsPeriod(periodDays)
        return try await send(path: "/me/coach-analytics?periodDays=\(days)", method: .get)
    }

    func fetchCoachAnalyticsSummary(periodDays: Int = 7) async throws -> CoachAnalyticsResponse {
        let days = Self.clampedAnalyticsPeriod(periodDays)
        return try await send(path: "/me/coach-analytics/summary?periodDays=\(days)", method: .get)
    }

    func postCoachImpressions(
        coachProfileIds: [String],
        source: String = "discover_list"
    ) async throws -> ImpressionsResponse {
        var seen = Set<String>()
        let ids = coachProfileIds.compactMap { id -> String? in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
        guard !ids.isEmpty else {
            return ImpressionsResponse(recorded: 0)
        }
        return try await send(
            path: "/coaches/events/impressions",
            method: .post,
            body: ImpressionsBody(
                coachProfileIds: Array(ids.prefix(50)),
                source: source
            )
        )
    }

    private static func clampedAnalyticsPeriod(_ periodDays: Int) -> Int {
        switch periodDays {
        case 7, 30, 90: return periodDays
        default: return 30
        }
    }

    // MARK: - Coach verification (Phase 7)

    func getCoachVerification() async throws -> MeCoachVerification {
        try await send(path: "/me/coach-verification", method: .get)
    }

    func createVerifyUpload(
        docType: String,
        contentType: String,
        fileName: String
    ) async throws -> VerifyUploadSlot {
        try await send(
            path: "/me/coach-verification/uploads",
            method: .post,
            body: VerifyUploadSlotRequest(
                docType: docType,
                contentType: contentType,
                fileName: fileName
            )
        )
    }

    /// Raw PUT of file bytes to the presigned/local upload URL (Bearer auth, not JSON).
    func putVerifyUpload(
        uploadUrl: String,
        data: Data,
        contentType: String
    ) async throws -> VerifyUploadPutResponse {
        try await AuthTokenRefresher.shared.refreshIfExpiring()
        guard let url = Self.resolveURL(uploadUrl) else {
            throw AppError.api("Invalid upload URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.put.rawValue
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        guard let token = TokenStore.accessToken() else { throw AppError.unauthorized }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        request.timeoutInterval = 120

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Invalid response from server.")
        }
        if http.statusCode == 401 {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        if !(200...299).contains(http.statusCode) {
            let detail = Self.detail(from: responseData)
            if http.statusCode == 404 {
                throw AppError.notFound(detail ?? "Not found.")
            }
            if http.statusCode == 400 {
                throw AppError.validation(detail ?? "Invalid upload.")
            }
            throw AppError.api(detail ?? "Upload failed (\(http.statusCode)).")
        }
        if responseData.isEmpty {
            return VerifyUploadPutResponse(ok: true)
        }
        return try decode(VerifyUploadPutResponse.self, from: responseData)
    }

    func submitCoachVerification(_ body: VerificationSubmitBody) async throws -> VerificationApplication {
        try await send(path: "/me/coach-verification/applications", method: .post, body: body)
    }

    func cancelCoachVerification() async throws {
        let _: VerificationCancelResponse = try await send(
            path: "/me/coach-verification/cancel",
            method: .post,
            body: EmptyBody()
        )
    }

    private static func resolveURL(_ string: String) -> URL? {
        if let absolute = URL(string: string), absolute.scheme != nil {
            return absolute
        }
        return URL(string: string, relativeTo: APIConfig.baseURL)?.absoluteURL
    }

    // MARK: - Coach packages (Phase 8)

    func myCoachPackages() async throws -> CoachPackagePage {
        try await send(path: "/me/coach-packages", method: .get)
    }

    func createCoachPackage(_ body: CoachPackageBody) async throws -> CoachPackage {
        try await send(path: "/me/coach-packages", method: .post, body: body)
    }

    func updateCoachPackage(id: String, _ body: CoachPackageBody) async throws -> CoachPackage {
        try await send(path: "/me/coach-packages/\(id)", method: .put, body: body)
    }

    func archiveCoachPackage(id: String) async throws -> CoachPackage {
        try await send(path: "/me/coach-packages/\(id)/archive", method: .post, body: EmptyBody())
    }

    func listCoachPackages(coachProfileId: String) async throws -> CoachPackagePage {
        try await send(path: "/coaches/\(coachProfileId)/packages", method: .get)
    }

    func coachPackageDetail(coachProfileId: String, packageId: String) async throws -> CoachPackage {
        try await send(path: "/coaches/\(coachProfileId)/packages/\(packageId)", method: .get)
    }

    func inquireCoachPackage(
        coachProfileId: String,
        packageId: String,
        message: String?
    ) async throws -> PackageInquireResponse {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await send(
            path: "/coaches/\(coachProfileId)/packages/\(packageId)/inquire",
            method: .post,
            body: PackageInquireBody(message: (trimmed?.isEmpty == false) ? trimmed : nil)
        )
    }

    // MARK: - Billing / Boost (Phase 2 + 4)

    func billingProducts(type: String = "boost", currency: String? = nil) async throws -> BillingProductPage {
        var items: [URLQueryItem] = [URLQueryItem(name: "type", value: type)]
        if let currency, !currency.isEmpty {
            items.append(URLQueryItem(name: "currency", value: currency.lowercased()))
        }
        var components = URLComponents()
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await send(path: "/billing/products\(query)", method: .get)
    }

    func createBoostCheckout(
        productId: String,
        provider: String? = nil,
        successUrl: String? = nil,
        cancelUrl: String? = nil
    ) async throws -> BoostCheckoutResponse {
        try await send(
            path: "/billing/boost/checkout",
            method: .post,
            body: BoostCheckoutBody(
                productId: productId,
                provider: provider,
                successUrl: successUrl,
                cancelUrl: cancelUrl
            )
        )
    }

    func confirmBoostCheckout(
        checkoutSessionId: String? = nil,
        attemptId: String? = nil,
        provider: String? = nil
    ) async throws -> MeBoostDTO {
        try await send(
            path: "/billing/boost/confirm",
            method: .post,
            body: BoostConfirmBody(
                checkoutSessionId: checkoutSessionId,
                attemptId: attemptId,
                provider: provider
            )
        )
    }

    func myBoost() async throws -> MeBoostDTO {
        try await send(path: "/me/boost", method: .get)
    }

    // MARK: - Sandow Score (Profile)

    /// Live profile chart — `period` = `week` | `month`.
    func sandowScore(period: String = "week") async throws -> SandowScoreResponse {
        let value = period.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? period
        return try await send(path: "/me/sandow-score?period=\(value)", method: .get)
    }

    // MARK: - AI Gateway / freemium

    func aiCapabilities() async throws -> AICapabilitiesDTO {
        try await send(path: "/coach/ai/capabilities", method: .get)
    }

    func generateAIProgram(
        horizonDays: Int = 7,
        notes: String? = nil,
        assessment: AssessmentBody? = nil
    ) async throws -> WorkoutPlan {
        try await send(
            path: "/coach/programs/generate",
            method: .post,
            body: AIGenerateProgramBody(horizonDays: horizonDays, notes: notes, assessment: assessment)
        )
    }

    /// Trainee-owned AI plan only — `PATCH /trainee/ai-plans/{id}` (403 `PLAN_LOCKED` if trainer plan).
    func updateTraineeAIPlan(id: String, _ body: PlanBody) async throws -> WorkoutPlan? {
        try await sendOptional(path: "/trainee/ai-plans/\(id)", method: .patch, body: body)
    }

    /// Trainee-owned AI plan only — `DELETE /trainee/ai-plans/{id}` clears assignment server-side.
    func deleteTraineeAIPlan(id: String) async throws {
        try await sendVoid(path: "/trainee/ai-plans/\(id)", method: .delete, body: EmptyBody())
    }

    // MARK: - AI billing (Phase 3)

    func myAI() async throws -> MeAIResponse {
        try await send(path: "/me/ai", method: .get)
    }

    func verifyAppleAI(signedTransaction: String, signedRenewalInfo: String? = nil) async throws -> MeAIResponse {
        try await send(
            path: "/billing/ai/apple/verify",
            method: .post,
            body: AppleVerifyBody(
                signedTransaction: signedTransaction,
                signedRenewalInfo: signedRenewalInfo,
                transactionId: nil,
                originalTransactionId: nil
            )
        )
    }

    func verifyAppleAI(transactionId: String, originalTransactionId: String?) async throws -> MeAIResponse {
        try await send(
            path: "/billing/ai/apple/verify",
            method: .post,
            body: AppleVerifyBody(
                signedTransaction: nil,
                signedRenewalInfo: nil,
                transactionId: transactionId,
                originalTransactionId: originalTransactionId
            )
        )
    }

    func restoreAppleAI(transactions: [AppleVerifyBody]) async throws -> MeAIResponse {
        try await send(
            path: "/billing/ai/apple/restore",
            method: .post,
            body: AppleRestoreBody(transactions: transactions)
        )
    }

    func traineeTrainer() async throws -> TrainerWithUser {
        try await send(path: "/trainee/trainer", method: .get)
    }
}
