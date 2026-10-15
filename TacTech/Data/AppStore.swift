import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppStore {
    private let api = APIClient()
    private let coachAPI = CoachAPI()
    private var coachMemorySyncTask: Task<Void, Never>?

    var session: Session?
    var users: [User] = []
    var trainers: [TrainerProfile] = []
    var trainees: [TraineeProfile] = []
    var exercises: [Exercise] = []
    var plans: [WorkoutPlan] = []
    var assignments: [PlanAssignment] = []
    var workoutLogs: [WorkoutLog] = []
    var meals: [Meal] = []
    var feedback: [TrainerFeedback] = []
    var formReports: [FormReport] = []
    var foodCatalog: [FoodKnowledge] = SeedData.foodCatalog
    var isRestoringSession = true
    var assessmentCompleted = false
    var profileSetupCompleted = false
    /// Interactive login/signup in flight — keep auth UI until gates + workspace resolve (no splash replay).
    var isBootstrappingSession = false
    /// Trainer-saved exercise prescriptions (local).
    var exerciseTemplates: [ExerciseTemplate] = []
    /// Trainee: pending join request (invite awaiting trainer approval).
    var pendingJoinRequest: JoinRequestDTO?
    /// Trainer: pending join requests for the Requests inbox.
    var trainerJoinRequests: [JoinRequestDTO] = []
    /// Soft banner for peer leave/remove / accept / plan changes (shown from Root — any tab).
    var softToast: TTToastMessage?
    /// Non-blocking chip while Live Form / exercise detail / Form Studio is open.
    var planChangeNotice: String?
    /// True while coalescing accept/link sync — keeps pending UI sticky (no join-form flash).
    var isSyncingCoachLink = false
    /// Depth of trainee “in-session” UI (Live Form, exercise detail, Form Studio).
    private(set) var traineeSessionUIDepth = 0
    var isTraineeSessionUIActive: Bool { traineeSessionUIDepth > 0 }
    /// Live analytics keyed by traineeId (`GET …/analytics`).
    var traineeAnalyticsById: [String: TraineeAnalytics] = [:]
    /// Marketplace entitlements — Phase 1 cache only; do **not** gate AI chat on launch.
    var entitlements: EntitlementsDTO?
    /// AI Coach Pro status (`GET /me/ai`).
    var aiEntitlement: MeAIResponse?
    /// Cached `GET /coach/ai/capabilities` — which AI surfaces are live.
    var aiCapabilities: AICapabilitiesDTO = .fallback
    /// Soft banner for solo generate / HAS_TRAINER (cleared by UI).
    var aiSoftNotice: String?
    /// Trainer Boost status (`GET /me/boost`). Nil for trainees / before first load.
    var myBoost: MeBoostDTO?
    /// Live Sandow Score chart (`GET /me/sandow-score` or local compose fallback).
    var sandowScore: SandowScoreResponse?
    var sandowPeriod: SandowScorePeriod = .week
    var isLoadingSandowScore = false
    /// Pending Boost checkout (Stripe session and/or local wallet attempt).
    var pendingBoostCheckout: PendingBoostCheckout? {
        didSet { Self.persistPendingBoost(pendingBoostCheckout) }
    }

    /// Backward-compatible accessor used by older call sites.
    var pendingBoostCheckoutSessionId: String? {
        get { pendingBoostCheckout?.checkoutSessionId }
        set {
            var pending = pendingBoostCheckout ?? PendingBoostCheckout()
            pending.checkoutSessionId = newValue
            if pending.hasIdentity {
                pendingBoostCheckout = pending
            } else {
                pendingBoostCheckout = nil
            }
        }
    }
    /// Global AI paywall sheet (trainee). Prevents re-entrant present loops.
    var showAIPaywall = false
    private var macrosByKey: [String: MacroEstimate] = [:]
    /// Last values from `GET /me` or login/signup — nil means backend omitted the field.
    private var serverAssessmentCompleted: Bool?
    private var serverOnboardingCompleted: Bool?
    /// Coalesce `relationship.changed` + `relationship_ended` double-delivery.
    private var relationshipReconcileTask: Task<Void, Never>?
    /// Coalesce `join_request_accepted` + `relationship.changed(linked)` into one atomic sync.
    private var traineeCoachLinkSyncTask: Task<Void, Never>?
    private var traineeCoachLinkSyncGeneration = 0
    /// Coalesce `plan.assignment.changed` + `plan_*` inbox types.
    private var planAssignmentSyncTask: Task<Void, Never>?
    private var pendingPlanAssignmentAction: String?
    private var pendingPlanAssignmentTitle: String?
    private var pendingPlanAssignmentTraineeProfileId: String?

    var currentUser: User? {
        users.first { $0.id == session?.userId }
    }

    var currentTrainer: TrainerProfile? {
        guard let user = currentUser, user.role == .trainer else { return nil }
        return trainers.first { $0.userId == user.id }
    }

    var currentTrainee: TraineeProfile? {
        guard let user = currentUser, user.role == .trainee else { return nil }
        return trainees.first { $0.userId == user.id }
    }

    init() {
        pendingBoostCheckout = Self.loadPendingBoost()
        Task { await restoreIfNeeded() }
    }

    /// Canvas / Xcode Previews — skips network restore and loads demo data.
    init(previewRole: UserRole) {
        isRestoringSession = false
        assessmentCompleted = true
        profileSetupCompleted = true
        seedPreviewData(as: previewRole)
    }

    static func preview(role: UserRole) -> AppStore {
        AppStore(previewRole: role)
    }

    func restoreIfNeeded() async {
        defer { isRestoringSession = false }
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            try await AuthTokenRefresher.shared.refreshIfExpiring()
            try await refreshSession()
            refreshAssessmentFlag()
            scheduleCoachMemorySync()
            await AuthTokenRefresher.shared.scheduleProactiveRefresh()
            await LocalizationController.shared.pullFromServer()
        } catch {
            clearLocalSession()
        }
    }

    func login(email: String, password: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        // Stay on auth UI until gates resolve — avoids splash + welcome interstitial.
        isBootstrappingSession = true
        defer { isBootstrappingSession = false }
        let response = try await api.login(email: normalized, password: password)
        apply(auth: response)
        try await refreshSession()
        refreshAssessmentFlag()
        scheduleCoachMemorySync()
        await LocalizationController.shared.pullFromServer()
    }

    func signup(name: String, email: String, password: String, role: UserRole, inviteCode: String?) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.validation("Enter your name.") }
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        guard password.count >= 6 else { throw AppError.validation("Password must be at least 6 characters.") }
        isBootstrappingSession = true
        defer { isBootstrappingSession = false }
        let response = try await api.signup(
            SignupBody(
                name: name,
                email: normalized,
                password: password,
                role: role.rawValue,
                inviteCode: inviteCode
            )
        )
        apply(auth: response)
        try await refreshSession()
        refreshAssessmentFlag()
        scheduleCoachMemorySync()
        await LocalizationController.shared.pullFromServer()
    }

    /// Debounced RAG memory sync for AI Coach (login, assessment, plan changes).
    func scheduleCoachMemorySync(force: Bool = false) {
        coachMemorySyncTask?.cancel()
        coachMemorySyncTask = Task { [coachAPI] in
            let delayNs: UInt64 = force ? 200_000_000 : 1_500_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            _ = try? await coachAPI.syncMemory()
        }
    }

    /// Apply profile-setup fields collected at signup (role-specific).
    /// Prefer `saveMeProfile` / `fetchMeProfile` for server truth; this remains a local optimistic helper.
    func applyProfileSetup(
        gender: String,
        location: String,
        heightCm: Int?,
        weightKg: Double?
    ) {
        let trimmedGender = gender.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)

        if var trainee = currentTrainee {
            if !trimmedGender.isEmpty { trainee.gender = trimmedGender }
            if !trimmedLocation.isEmpty { trainee.location = trimmedLocation }
            if let heightCm { trainee.heightCm = heightCm }
            if let weightKg { trainee.weightKg = weightKg }
            upsert(trainee)
        }
        if var trainer = currentTrainer {
            if !trimmedGender.isEmpty { trainer.gender = trimmedGender }
            if !trimmedLocation.isEmpty { trainer.location = trimmedLocation }
            upsert(trainer)
        }
    }

    func updateCurrentUserName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var user = currentUser else { return }
        user.name = trimmed
        upsert(user)
    }

    // MARK: - Live /me/profile

    /// Last successful profile snapshot (optimistic UI cache; not UserDefaults source of truth).
    var meProfileCache: MeProfileResponse?
    /// Server absolute avatar URL — source of truth for custom photos.
    var remoteAvatarURL: String?
    /// Server catalog asset (e.g. Avatar_01_Color) when no custom URL.
    var remoteAvatarAsset: String?

    /// Catalog asset for display when `remoteAvatarURL` is absent. Never returns broken `custom`.
    var displayAvatarAsset: String? {
        if let url = remoteAvatarURL, !url.isEmpty { return nil }
        if let asset = remoteAvatarAsset, TTAvatarCatalog.isAssetName(asset) { return asset }
        if let userId = session?.userId,
           let saved = TTAvatarCatalog.saved(for: userId),
           TTAvatarCatalog.isAssetName(saved) {
            return saved
        }
        return nil
    }

    @discardableResult
    func fetchMeProfile() async throws -> MeProfileResponse {
        let response = try await api.meProfile()
        applyMeProfileResponse(response)
        return response
    }

    @discardableResult
    func saveMeProfile(_ body: UpdateMeProfileBody) async throws -> MeProfileResponse {
        let response = try await api.patchMeProfile(body)
        applyMeProfileResponse(response)
        // Soft-refresh /me gates without blocking
        Task { try? await refreshSessionQuietly() }
        return response
    }

    @discardableResult
    func uploadProfileAvatar(jpegData: Data, previewImage: UIImage? = nil) async throws -> MeAvatarUploadResponse {
        if jpegData.count > 5 * 1024 * 1024 {
            throw AppError.validation("Photo must be 5 MB or smaller.")
        }
        let response = try await api.uploadMeAvatar(
            fileData: jpegData,
            filename: "avatar.jpg",
            mimeType: "image/jpeg"
        )
        if let url = response.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            remoteAvatarURL = url
            remoteAvatarAsset = nil
            if let previewImage {
                Task { await TTRemoteImageCache.shared.store(previewImage, for: url) }
                if let userId = session?.userId {
            _ = TTAvatarCatalog.saveCustomImage(previewImage, for: userId)
                }
            }
        }
        _ = try? await fetchMeProfile()
        return response
    }

    func deleteProfileAvatar() async throws {
        let previousURL = remoteAvatarURL
        try await api.deleteMeAvatar()
        remoteAvatarURL = nil
        if let previousURL {
            Task { await TTRemoteImageCache.shared.remove(for: previousURL) }
        }
        if let userId = session?.userId {
            try? FileManager.default.removeItem(at: TTAvatarCatalog.customImageURL(for: userId))
            UserDefaults.standard.removeObject(forKey: TTAvatarCatalog.storageKey(userId: userId))
        }
        _ = try? await fetchMeProfile()
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        try await api.changeMePassword(currentPassword: currentPassword, newPassword: newPassword)
    }

    func applyMeProfileResponse(_ response: MeProfileResponse) {
        meProfileCache = response
        applyServerGateFlags(
            assessmentCompleted: response.assessmentCompleted,
            onboardingCompleted: response.onboardingCompleted
        )
        refreshAssessmentFlag()

        let role = response.user.resolvedRole
        let user = User(
            id: response.user.id,
            name: response.user.name,
            email: response.user.email,
            password: currentUser?.password ?? "",
            role: role,
            createdAt: response.user.createdAt ?? currentUser?.createdAt ?? .now
        )
        upsert(user)

        if let traineeDTO = response.trainee {
            var trainee = traineeDTO.asTraineeProfile()
            if trainee.gender == nil { trainee.gender = response.profile.gender }
            if trainee.location == nil { trainee.location = response.profile.location }
            if trainee.heightCm == 0, let h = response.profile.heightCm { trainee.heightCm = h }
            if trainee.weightKg == 0, let w = response.profile.weightKg { trainee.weightKg = w }
            upsert(trainee)
        } else if let trainerDTO = response.trainer {
            upsert(trainerDTO.asTrainerProfile(existing: currentTrainer))
        } else {
            // Mirror profile fields onto existing role profile if DTO omitted
            applyProfileSetup(
                gender: response.profile.gender ?? "",
                location: response.profile.location ?? "",
                heightCm: response.profile.heightCm,
                weightKg: response.profile.weightKg
            )
        }

        applyRemoteAvatarFields(
            url: response.profile.avatarUrl ?? response.user.avatarUrl,
            asset: response.profile.avatarAsset ?? response.user.avatarAsset
        )
    }

    /// Syncs in-memory avatar from server; local disk is cache only, never required to show.
    private func applyRemoteAvatarFields(url: String?, asset: String?) {
        let trimmedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasURL = trimmedURL.map { !$0.isEmpty && $0.lowercased().hasPrefix("http") } ?? false
        let previousURL = remoteAvatarURL

        if hasURL, let trimmedURL {
            remoteAvatarURL = trimmedURL
            remoteAvatarAsset = nil
            if previousURL != trimmedURL {
                Task { _ = await TTRemoteImageCache.shared.image(for: trimmedURL) }
            }
        if let userId = session?.userId {
                // Drop broken `custom` token — URL is source of truth after reinstall.
                UserDefaults.standard.removeObject(forKey: TTAvatarCatalog.storageKey(userId: userId))
            }
            return
        }

        remoteAvatarURL = nil

        if let asset, TTAvatarCatalog.isAssetName(asset) {
            remoteAvatarAsset = asset
            if let previousURL {
                Task { await TTRemoteImageCache.shared.remove(for: previousURL) }
            }
            if let userId = session?.userId {
                TTAvatarCatalog.save(asset, for: userId)
                try? FileManager.default.removeItem(at: TTAvatarCatalog.customImageURL(for: userId))
            }
        } else {
            remoteAvatarAsset = nil
            if let userId = session?.userId {
                let saved = TTAvatarCatalog.saved(for: userId)
                if TTAvatarCatalog.isCustom(saved),
                   TTAvatarCatalog.loadCustomImage(for: userId) == nil {
                    UserDefaults.standard.removeObject(forKey: TTAvatarCatalog.storageKey(userId: userId))
                }
            }
        }
    }

    private func refreshSessionQuietly() async throws {
        let me = try await api.me()
        applyServerGateFlags(
            assessmentCompleted: me.assessmentCompleted,
            onboardingCompleted: me.onboardingCompleted
        )
        refreshAssessmentFlag()
        if let user = me.resolvedUser?.asUser() {
            var u = user
            u.password = currentUser?.password ?? ""
            upsert(u)
        }
        if let trainer = me.trainer { upsert(trainer) }
        if let trainee = me.trainee {
            upsertTraineePreservingCoachLink(trainee)
        }
    }

    func submitAssessment(_ draft: FitnessAssessment) async throws {
        do {
            try await api.submitAssessment(AssessmentBody(draft))
        } catch let error as AppError where error.isNotFound {
            persistAssessment(draft)
        }
        if var trainee = currentTrainee {
            trainee.goal = draft.goal
            trainee.weightKg = draft.weightKg
            trainee.dailyCalorieTarget = draft.calorieGoal
            upsert(trainee)
        }
        markAssessmentCompleted()
        persistAssessment(draft)
        scheduleCoachMemorySync(force: true)
    }

    func submitTrainerAssessment(_ draft: TrainerAssessment) async throws {
        do {
            try await api.submitTrainerAssessment(TrainerAssessmentBody(draft))
        } catch let error as AppError where error.isNotFound {
            persistTrainerAssessment(draft)
        }
        if var trainer = currentTrainer {
            trainer.specialty = draft.specialty.isEmpty ? draft.coachingFocus : draft.specialty
            trainer.yearsExperience = draft.yearsExperience
            trainer.bio = composedTrainerBio(draft)
            upsert(trainer)
        }
        markAssessmentCompleted()
        persistTrainerAssessment(draft)
        scheduleCoachMemorySync(force: true)
    }

    func persistAssessment(_ draft: FitnessAssessment) {
        guard let userId = session?.userId,
              let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: "assessment.payload.\(userId)")
    }

    func persistTrainerAssessment(_ draft: TrainerAssessment) {
        guard let userId = session?.userId,
              let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: "trainer.assessment.payload.\(userId)")
    }

    func markAssessmentCompleted() {
        serverAssessmentCompleted = true
        assessmentCompleted = true
        guard let userId = session?.userId else { return }
        UserDefaults.standard.set(true, forKey: "assessment.completed.\(userId)")
    }

    func markProfileSetupCompleted() {
        serverOnboardingCompleted = true
        profileSetupCompleted = true
        guard let userId = session?.userId else { return }
        UserDefaults.standard.set(true, forKey: "profile.setup.completed.\(userId)")
    }

    /// Assessment / onboarding gates — **server is source of truth** when flags are present.
    func refreshAssessmentFlag() {
        guard let userId = session?.userId else {
            assessmentCompleted = false
            profileSetupCompleted = false
            return
        }

        if let server = serverAssessmentCompleted {
            assessmentCompleted = server
            UserDefaults.standard.set(server, forKey: "assessment.completed.\(userId)")
        } else {
            // Legacy backend / offline: local cache only (no profile heuristics).
            var completed = UserDefaults.standard.bool(forKey: "assessment.completed.\(userId)")
            if !completed {
                let hasTraineePayload = UserDefaults.standard.data(forKey: "assessment.payload.\(userId)") != nil
                let hasTrainerPayload = UserDefaults.standard.data(forKey: "trainer.assessment.payload.\(userId)") != nil
                completed = hasTraineePayload || hasTrainerPayload
            }
            assessmentCompleted = completed
        }

        if let server = serverOnboardingCompleted {
            profileSetupCompleted = server
            UserDefaults.standard.set(server, forKey: "profile.setup.completed.\(userId)")
        } else {
            profileSetupCompleted = UserDefaults.standard.bool(forKey: "profile.setup.completed.\(userId)")
        }
    }

    private func applyServerGateFlags(assessmentCompleted: Bool?, onboardingCompleted: Bool?) {
        if let assessmentCompleted {
            serverAssessmentCompleted = assessmentCompleted
        }
        if let onboardingCompleted {
            serverOnboardingCompleted = onboardingCompleted
        }
    }

    private func composedTrainerBio(_ draft: TrainerAssessment) -> String {
        var parts: [String] = []
        let bio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bio.isEmpty { parts.append(bio) }
        let philosophy = draft.philosophy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !philosophy.isEmpty { parts.append(philosophy) }
        if !draft.certifications.isEmpty {
            parts.append("Certifications: \(draft.certifications.joined(separator: ", "))")
        }
        if !draft.sessionStyle.isEmpty {
            parts.append("Session style: \(draft.sessionStyle)")
        }
        return parts.joined(separator: "\n\n")
    }

    func requestPasswordReset(email: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        try await api.requestPasswordReset(email: normalized)
    }

    func logout() async {
        await NotificationStore.shared.unregisterCurrentToken()
        NotificationStore.shared.stop()
        HumanCallStore.shared.stopMonitoring()
        let refresh = TokenStore.refreshToken()
        if let refresh {
            await api.logout(refreshToken: refresh)
        }
        clearLocalSession()
    }

    func user(forUserId userId: String) -> User? {
        users.first { $0.id == userId }
    }

    func user(forTrainee trainee: TraineeProfile) -> User? {
        users.first { $0.id == trainee.userId }
    }

    func user(forTrainer trainer: TrainerProfile) -> User? {
        users.first { $0.id == trainer.userId }
    }

    func trainer(for trainee: TraineeProfile) -> TrainerProfile? {
        trainers.first { $0.id == trainee.trainerId }
    }

    func trainees(for trainer: TrainerProfile) -> [TraineeProfile] {
        trainees.filter { $0.trainerId == trainer.id }
    }

    func assignedPlan(for trainee: TraineeProfile) -> WorkoutPlan? {
        guard let assignment = assignments
            .filter({ $0.traineeId == trainee.id })
            .sorted(by: { $0.assignedAt > $1.assignedAt })
            .first
        else { return nil }
        return plans.first { $0.id == assignment.planId }
    }

    func assign(planId: String, to traineeId: String) async throws {
        try await api.assignPlan(planId: planId, traineeId: traineeId)
        assignments.removeAll { $0.traineeId == traineeId }
        assignments.append(PlanAssignment(id: UUID().uuidString, planId: planId, traineeId: traineeId, assignedAt: .now))
    }

    func unassign(planId: String, from traineeId: String) async throws {
        try await api.unassignPlan(planId: planId, traineeId: traineeId)
        assignments.removeAll { $0.traineeId == traineeId && $0.planId == planId }
    }

    func updatePlan(_ draft: WorkoutPlan) async throws {
        let updated = try await api.updatePlan(id: draft.id, PlanBody(plan: draft))
        if var updated {
            if updated.days.isEmpty { updated.days = draft.days }
            if updated.notes == nil { updated.notes = draft.notes }
            upsert(updated)
            saveTemplates(from: updated)
        } else {
            upsert(draft)
            saveTemplates(from: draft)
            let remote = (try? await api.trainerPlans()) ?? []
            if !remote.isEmpty { plans = remote }
        }
        scheduleCoachMemorySync(force: true)
    }

    func deletePlan(id: String) async throws {
        try await api.deletePlan(id: id)
        plans.removeAll { $0.id == id }
        assignments.removeAll { $0.planId == id }
        scheduleCoachMemorySync(force: true)
    }

    func createPlan(_ draft: WorkoutPlan) async throws {
        let created = try await api.createPlan(PlanBody(plan: draft))
        if var created {
            if created.days.isEmpty { created.days = draft.days }
            if created.notes == nil { created.notes = draft.notes }
            upsert(created)
            saveTemplates(from: created)
        } else if currentTrainer != nil {
            upsert(draft)
            saveTemplates(from: draft)
            let remote = (try? await api.trainerPlans()) ?? []
            if !remote.isEmpty { plans = remote }
        }
        scheduleCoachMemorySync(force: true)
    }

    func createPlan(title: String, focus: String, duration: Int, level: String, days: Int, exerciseDrafts: [WorkoutExercise]) async throws {
        guard let trainer = currentTrainer else { return }
        try await createPlan(
            WorkoutPlan(
                id: UUID().uuidString,
                trainerId: trainer.id,
                title: title,
                focus: focus,
                durationMinutes: duration,
                level: level,
                daysPerWeek: days,
                exercises: exerciseDrafts
            )
        )
    }

    /// Legacy instant link — prefer `createJoinRequest` for Profile join UX.
    func linkTrainee(toInviteCode code: String) async throws {
        _ = try await createJoinRequest(inviteCode: code, message: nil)
    }

    /// Trainee sends a join request (pending until Accept).
    @discardableResult
    func createJoinRequest(inviteCode: String, message: String?) async throws -> JoinRequestDTO {
        guard currentTrainee != nil else { throw AppError.validation("Only trainees can request to join a trainer.") }
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw AppError.validation("Enter an invite code.") }
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = CreateJoinRequestBody(
            inviteCode: code,
            message: (trimmedMessage?.isEmpty == false) ? trimmedMessage : nil
        )
        let created = try await api.createJoinRequest(body)
        pendingJoinRequest = created
        await refreshTraineeJoinState()
        return pendingJoinRequest ?? created
    }

    func refreshTraineeJoinState() async {
        guard session?.role == .trainee else { return }
        do {
            let state = try await api.traineeJoinState()
            applyTraineeJoinState(state)
        } catch {
            #if DEBUG
            print("[TacTech] refreshTraineeJoinState failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Atomic join-state apply — never clear pending until an active link is confirmed
    /// (avoids pending → empty join form → My Trainer flicker on accept).
    @MainActor
    private func applyTraineeJoinState(_ state: TraineeJoinStateDTO) {
        if let link = state.activeLink {
            applyActiveTrainerLink(link)
            pendingJoinRequest = nil
            return
        }
        if let pending = state.pendingRequest, pending.isPending {
            pendingJoinRequest = pending
            return
        }
        // Server reports neither — during accept sync keep sticky pending / local link.
        if isSyncingCoachLink, pendingJoinRequest?.isPending == true {
            return
        }
        pendingJoinRequest = state.pendingRequest
    }

    func cancelJoinRequest(id: String) async throws {
        let cancelled = try await api.cancelJoinRequest(id: id)
        if cancelled.id == pendingJoinRequest?.id || cancelled.status.lowercased() == "cancelled" {
            pendingJoinRequest = nil
        }
        await refreshTraineeJoinState()
    }

    func fetchTrainerJoinRequests() async {
        guard session?.role == .trainer else { return }
        do {
            trainerJoinRequests = try await api.trainerJoinRequests(status: "pending")
        } catch {
            #if DEBUG
            print("[TacTech] fetchTrainerJoinRequests failed: \(error.localizedDescription)")
            #endif
        }
    }

    func acceptJoinRequest(id: String) async throws {
        try await api.acceptJoinRequest(id: id)
        trainerJoinRequests.removeAll { $0.id == id }
        await reloadTrainerRoster()
        await fetchTrainerJoinRequests()
        await NotificationStore.shared.refreshUnread()
        await NotificationStore.shared.refreshInbox()
    }

    func rejectJoinRequest(id: String, reason: String? = nil) async throws {
        try await api.rejectJoinRequest(id: id, reason: reason)
        trainerJoinRequests.removeAll { $0.id == id }
        await fetchTrainerJoinRequests()
        await NotificationStore.shared.refreshUnread()
    }

    /// Socket / inbox: refresh join-related state for the current role.
    func handleJoinRequestRealtime(type: String) async {
        let t = type.lowercased()
        if session?.role == .trainer, t == "join_request" {
            await fetchTrainerJoinRequests()
            await NotificationStore.shared.refreshUnread()
        } else if session?.role == .trainee {
            if t == "join_request_accepted" {
                // Coalesced light sync — never full refreshSession (wipes trainerId mid-accept).
                scheduleTraineeCoachLinkSync()
            } else if t == "join_request_rejected" || t == "join_request_cancelled" {
                pendingJoinRequest = nil
                isSyncingCoachLink = false
                await refreshTraineeJoinState()
                if t == "join_request_rejected" {
                    softToast = TTToastMessage(
                        text: LocalizationController.shared.localized("join.request_declined"),
                        style: .error
                    )
                }
            }
        }
    }

    /// Single entry for accept / `relationship.changed(linked)` — debounced, idempotent, no UI flash.
    @MainActor
    func scheduleTraineeCoachLinkSync() {
        guard session?.role == .trainee else { return }
        isSyncingCoachLink = true
        traineeCoachLinkSyncGeneration += 1
        let generation = traineeCoachLinkSyncGeneration
        traineeCoachLinkSyncTask?.cancel()
        traineeCoachLinkSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, generation == self.traineeCoachLinkSyncGeneration else { return }
            await self.performTraineeCoachLinkSync()
            if generation == self.traineeCoachLinkSyncGeneration {
                self.isSyncingCoachLink = false
            }
        }
    }

    @MainActor
    private func performTraineeCoachLinkSync() async {
        let alreadyLinked = hasResolvedCoachLink

        var linked = false
        for attempt in 0..<3 {
            await refreshTraineeJoinState()
            if hasResolvedCoachLink {
                linked = true
                break
            }
            // Eventual consistency window after Accept — retry briefly.
            try? await Task.sleep(for: .milliseconds(450 + attempt * 250))
            guard !Task.isCancelled else { return }
        }

        if linked {
            // Enrich profile; never clear on 404 during accept (join-state is source of truth).
            await enrichTraineeTrainerFromServer(allowClearOnNotFound: false)
            await refreshAssignedPlanForCurrentTrainee()
            // Toast only on pending → linked transition (not idempotent replays).
            if !alreadyLinked {
                let name = linkedTrainerDisplayName() ?? "your trainer"
                let template = LocalizationController.shared.localized("join.linked_with")
                softToast = TTToastMessage(
                    text: String(format: template, name),
                    style: .success
                )
            }
        } else {
            // Final authoritative read without sticky hold.
            await refreshTraineeJoinState()
        }
    }

    private var hasResolvedCoachLink: Bool {
        guard let trainee = currentTrainee else { return false }
        return trainer(for: trainee) != nil
    }

    private func linkedTrainerDisplayName() -> String? {
        guard let trainee = currentTrainee,
              let trainer = trainer(for: trainee) else { return nil }
        return user(forTrainer: trainer)?.name
    }

    /// Socket `relationship.changed` / inbox `relationship_ended` — live roster & My Trainer sync.
    /// Debounced so domain event + notification do not double-refresh.
    @MainActor
    func handleRelationshipChanged(
        action: String,
        reason: String?,
        trainerUserId: String?,
        traineeUserId: String?,
        traineeProfileId: String?
    ) {
        let actionNorm = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !actionNorm.isEmpty else { return }
        relationshipReconcileTask?.cancel()
        relationshipReconcileTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self.applyRelationshipChanged(
                action: actionNorm,
                reason: reason?.lowercased(),
                trainerUserId: trainerUserId,
                traineeUserId: traineeUserId,
                traineeProfileId: traineeProfileId
            )
        }
    }

    /// Foreground / reconnect belt: refresh join + roster + assigned plan without polling.
    @MainActor
    func reconcileRelationshipOnForeground() async {
        guard session != nil else { return }
        switch session?.role {
        case .trainer:
            await reloadTrainerRoster()
            await fetchTrainerJoinRequests()
        case .trainee:
            await refreshTraineeJoinState()
            await reconcileTraineeTrainerLinkFromServer()
            await refreshAssignedPlanForCurrentTrainee()
        case .none:
            break
        }
    }

    // MARK: - Live assigned plan (trainee)

    @MainActor
    func beginTraineeSessionUI() {
        traineeSessionUIDepth += 1
    }

    @MainActor
    func endTraineeSessionUI() {
        traineeSessionUIDepth = max(0, traineeSessionUIDepth - 1)
        if traineeSessionUIDepth == 0 {
            planChangeNotice = nil
        }
    }

    /// Socket `plan.assignment.changed` / inbox `plan_*`.
    /// Trainee: refetch `GET /trainee/assigned-plan`. Trainer (2nd device): soft plans/roster refresh.
    @MainActor
    func handlePlanAssignmentChanged(
        action: String,
        planId: String?,
        planTitle: String?,
        traineeProfileId: String? = nil
    ) {
        guard session?.role == .trainee || session?.role == .trainer else { return }
        let actionNorm = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !actionNorm.isEmpty else { return }
        // Keep latest fields across domain + inbox double-delivery.
        pendingPlanAssignmentAction = Self.normalizePlanAssignmentAction(actionNorm)
        if let planTitle, !planTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingPlanAssignmentTitle = planTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let traineeProfileId, !traineeProfileId.isEmpty {
            pendingPlanAssignmentTraineeProfileId = traineeProfileId
        }
        _ = planId // trainee fetch is authoritative for plan body
        planAssignmentSyncTask?.cancel()
        planAssignmentSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let action = self.pendingPlanAssignmentAction ?? "updated"
            let title = self.pendingPlanAssignmentTitle
            let profileId = self.pendingPlanAssignmentTraineeProfileId
            self.pendingPlanAssignmentAction = nil
            self.pendingPlanAssignmentTitle = nil
            self.pendingPlanAssignmentTraineeProfileId = nil
            if self.session?.role == .trainee {
                await self.applyPlanAssignmentChanged(action: action, planTitle: title)
            } else if self.session?.role == .trainer {
                await self.applyTrainerPlanAssignmentChanged(traineeProfileId: profileId)
            }
        }
    }

    /// Optional multi-device polish — actor device already updated local state after REST.
    @MainActor
    private func applyTrainerPlanAssignmentChanged(traineeProfileId: String?) async {
        if let plans = try? await api.trainerPlans() {
            self.plans = plans
        }
        if let traineeProfileId, !traineeProfileId.isEmpty {
            await loadTrainerDetail(traineeId: traineeProfileId)
        } else {
            await reloadTrainerRoster()
        }
    }

    private static func normalizePlanAssignmentAction(_ raw: String) -> String {
        switch raw {
        case "plan_assigned", "assign", "assigned", "created":
            return "assigned"
        case "plan_unassigned", "unassign", "unassigned", "removed":
            return "unassigned"
        case "plan_updated", "update", "updated", "patched":
            return "updated"
        default:
            return raw
        }
    }

    @MainActor
    private func applyPlanAssignmentChanged(action: String, planTitle: String?) async {
        await refreshAssignedPlanForCurrentTrainee()

        let title = planTitle
            ?? currentTrainee.flatMap { assignedPlan(for: $0)?.title }

        if isTraineeSessionUIActive {
            // Refresh store quietly; don't toast or kick out of Live Form / logging.
            switch action {
            case "assigned":
                planChangeNotice = "New plan ready"
            case "unassigned":
                planChangeNotice = "Plan removed — applies next session"
            default:
                planChangeNotice = "Plan updated — applies next session"
            }
            return
        }

        let loc = LocalizationController.shared
        switch action {
        case "assigned":
            if let title, !title.isEmpty {
                softToast = TTToastMessage(text: "\(loc.localized("workout.your_plan")): \(title)", style: .success)
            } else {
                softToast = TTToastMessage(text: loc.localized("plan.new_assigned"), style: .success)
            }
        case "unassigned":
            softToast = TTToastMessage(text: loc.localized("plan.removed"), style: .info)
        case "updated":
            softToast = TTToastMessage(text: loc.localized("plan.updated"), style: .info)
        default:
            softToast = TTToastMessage(text: loc.localized("plan.updated"), style: .info)
        }
    }

    @MainActor
    private func applyRelationshipChanged(
        action: String,
        reason: String?,
        trainerUserId: String?,
        traineeUserId: String?,
        traineeProfileId: String?
    ) async {
        let isLinked = action == "linked" || action == "link" || action == "accepted"
        let isUnlinked = action == "unlinked" || action == "unlink" || action == "ended" || action == "removed"

        switch session?.role {
        case .trainer:
            if isUnlinked {
                let leftName = traineeDisplayName(
                    profileId: traineeProfileId,
                    userId: traineeUserId
                )
                if let profileId = traineeProfileId, !profileId.isEmpty {
                    trainees.removeAll { $0.id == profileId }
                    assignments.removeAll { $0.traineeId == profileId }
                }
                if let userId = traineeUserId, !userId.isEmpty {
                    let ids = trainees.filter { $0.userId == userId }.map(\.id)
                    trainees.removeAll { $0.userId == userId }
                    assignments.removeAll { ids.contains($0.traineeId) }
                }
                await reloadTrainerRoster()
                await fetchTrainerJoinRequests()
                if reason == "trainee_left", let leftName, !leftName.isEmpty {
                    softToast = TTToastMessage(text: "\(leftName) left your roster", style: .info)
                }
            } else if isLinked {
                await reloadTrainerRoster()
                await fetchTrainerJoinRequests()
            }
        case .trainee:
            if isUnlinked {
                clearLocalTrainerLinkForCurrentTrainee()
                pendingJoinRequest = nil
                isSyncingCoachLink = false
                try? await refreshSession()
                await reconcileTraineeTrainerLinkFromServer()
                await refreshTraineeJoinState()
                await refreshAssignedPlanForCurrentTrainee()
                if reason == "trainer_removed" {
                    softToast = TTToastMessage(
                        text: LocalizationController.shared.localized("relationship.removed_roster"),
                        style: .info
                    )
                }
            } else if isLinked {
                // Same coalesced path as join_request_accepted — no full session refresh.
                scheduleTraineeCoachLinkSync()
            }
        case .none:
            break
        }
    }

    private func traineeDisplayName(profileId: String?, userId: String?) -> String? {
        if let profileId, !profileId.isEmpty,
           let trainee = trainees.first(where: { $0.id == profileId }) {
            return user(forTrainee: trainee)?.name
        }
        if let userId, !userId.isEmpty,
           let trainee = trainees.first(where: { $0.userId == userId }) {
            return user(forTrainee: trainee)?.name
        }
        if let userId, !userId.isEmpty {
            return users.first(where: { $0.id == userId })?.name
        }
        return nil
    }

    private func applyActiveTrainerLink(_ link: ActiveTrainerLinkDTO) {
        guard var trainee = currentTrainee else { return }
        trainee.trainerId = link.trainerId
        upsert(trainee)
        let summary = link.trainer
        upsert(
            TrainerProfile(
                id: link.trainerId,
                userId: summary.id,
                inviteCode: "",
                specialty: "",
                yearsExperience: 0,
                bio: ""
            )
        )
        upsert(
            User(
                id: summary.id,
                name: summary.name,
                email: "",
                password: "",
                role: .trainer,
                createdAt: .now
            )
        )
    }

    /// Merge `/me` trainee without wiping a live coach link on eventual-consistency lag.
    private func upsertTraineePreservingCoachLink(_ incoming: TraineeProfile) {
        var merged = incoming
        if merged.trainerId == nil,
           let localTrainerId = currentTrainee?.trainerId,
           !localTrainerId.isEmpty,
           isSyncingCoachLink || pendingJoinRequest?.isPending == true || hasResolvedCoachLink {
            merged.trainerId = localTrainerId
        }
        upsert(merged)
    }

    /// Trainee leaves the linked trainer. Clears local trainer link + assigned plan cache, then refreshes `/me`.
    /// 404 “No trainer linked” is treated as success (stale UI) — local link cleared + refresh.
    @MainActor
    func unlinkTrainer() async throws {
        guard currentTrainee != nil else { throw AppError.validation("Only trainees can leave a trainer.") }
        do {
            try await api.unlinkTrainer()
        } catch let error as AppError where error.isNotFound {
            #if DEBUG
            print("[TacTech] unlink 404 — clearing stale local trainer link")
            #endif
            clearLocalTrainerLinkForCurrentTrainee()
            pendingJoinRequest = nil
        try await refreshSession()
            await reconcileTraineeTrainerLinkFromServer()
            await refreshTraineeJoinState()
            return
        } catch {
            throw error
        }
        clearLocalTrainerLinkForCurrentTrainee()
        pendingJoinRequest = nil
        try await refreshSession()
        await reconcileTraineeTrainerLinkFromServer()
        await refreshTraineeJoinState()
    }

    /// Trainer removes a trainee from the roster. Updates local list; pull-to-refresh still loads server truth.
    /// 404 (already removed) clears local roster entry and still reloads.
    @MainActor
    func removeTrainee(traineeId: String) async throws {
        guard currentTrainer != nil else { throw AppError.validation("Only trainers can remove trainees.") }
        do {
            try await api.removeTrainee(traineeId: traineeId)
        } catch let error as AppError where error.isNotFound {
            #if DEBUG
            print("[TacTech] remove trainee 404 — dropping stale roster entry \(traineeId)")
            #endif
            trainees.removeAll { $0.id == traineeId }
            assignments.removeAll { $0.traineeId == traineeId }
            await reloadTrainerRoster()
            return
        } catch {
            throw error
        }
        trainees.removeAll { $0.id == traineeId }
        assignments.removeAll { $0.traineeId == traineeId }
        await reloadTrainerRoster()
        await fetchTrainerJoinRequests()
    }

    @MainActor
    private func reloadTrainerRoster() async {
        guard let items = try? await api.trainerTrainees() else { return }
        if let trainerId = currentTrainer?.id {
            trainees.removeAll { $0.trainerId == trainerId }
        }
        apply(traineeItems: items)
    }

    @MainActor
    private func clearLocalTrainerLinkForCurrentTrainee() {
        guard var trainee = currentTrainee else { return }
        let id = trainee.id
        trainee.trainerId = nil
        upsert(trainee)
        assignments.removeAll { $0.traineeId == id }
    }

    /// If `/trainee/trainer` says not linked, force-clear local `trainerId` so My Trainer empties immediately.
    @MainActor
    private func reconcileTraineeTrainerLinkFromServer() async {
        await enrichTraineeTrainerFromServer(allowClearOnNotFound: true)
    }

    /// Fetch linked trainer profile. When `allowClearOnNotFound` is false (accept sync),
    /// a brief 404 must not wipe a join-state active link.
    @MainActor
    private func enrichTraineeTrainerFromServer(allowClearOnNotFound: Bool) async {
        guard currentTrainee != nil else { return }
        do {
            let trainerPayload = try await api.traineeTrainer()
            if let trainer = trainerPayload.profile { upsert(trainer) }
            if let user = trainerPayload.user {
                upsert(user.asUser())
            } else if let name = trainerPayload.name,
                      let userId = trainerPayload.userId ?? trainerPayload.profile?.userId {
                upsert(User(id: userId, name: name, email: trainerPayload.email ?? "", password: "", role: .trainer, createdAt: .now))
            }
            if let profile = trainerPayload.profile, var trainee = currentTrainee {
                trainee.trainerId = profile.id
                upsert(trainee)
            }
        } catch let error as AppError where error.isNotFound {
            if allowClearOnNotFound, !isSyncingCoachLink {
                clearLocalTrainerLinkForCurrentTrainee()
            }
        } catch {
            // Keep last-known trainer on transient network errors.
        }
    }

    func saveWorkoutLog(_ log: WorkoutLog) async throws {
        let created = try await api.createWorkoutLog(
            WorkoutLogBody(
                planId: log.planId,
                completedAt: log.completedAt,
                durationMinutes: log.durationMinutes,
                sets: log.sets.map {
                    WorkoutSetBody(exerciseId: $0.exerciseId, setNumber: $0.setNumber, reps: $0.reps, weightKg: $0.weightKg)
                }
            )
        )
        upsert(created ?? log)
        if let trainee = currentTrainee, let logs = try? await api.traineeLogs() {
            replaceLogs(logs, traineeId: trainee.id)
        }
    }

    func saveMeal(_ meal: Meal) async throws {
        let created = try await api.createMeal(
            MealBody(
                name: meal.name,
                eatenAt: meal.eatenAt,
                portionGrams: meal.portionGrams,
                macros: meal.macros,
                source: meal.source,
                isEstimate: meal.isEstimate
            )
        )
        upsert(created ?? meal)
        if let trainee = currentTrainee {
            await refreshDay(for: trainee.id, on: meal.eatenAt)
        }
    }

    /// Local calorie goal update for the nutrition home slider.
    func updateDailyCalorieTarget(_ value: Int) {
        guard var trainee = currentTrainee else { return }
        trainee.dailyCalorieTarget = max(1200, min(value, 5000))
        upsert(trainee)
    }

    func saveFeedback(_ item: TrainerFeedback) async throws {
        let created = try await api.sendFeedback(
            FeedbackBody(traineeId: item.traineeId, message: item.message, relatedExerciseId: item.relatedExerciseId)
        )
        upsert(created ?? item)
    }

    func saveFormReport(_ report: FormReport) async throws {
        let created = try await api.createFormReport(
            FormReportBody(
                exerciseId: report.exerciseId,
                score: report.score,
                cues: report.cues,
                repCount: report.repCount,
                createdAt: report.createdAt
            )
        )
        upsert(created ?? report)
    }

    func meals(for traineeId: String, on date: Date) -> [Meal] {
        meals.filter { $0.traineeId == traineeId && Calendar.current.isDate($0.eatenAt, inSameDayAs: date) }
            .sorted { $0.eatenAt > $1.eatenAt }
    }

    func logs(for traineeId: String) -> [WorkoutLog] {
        workoutLogs.filter { $0.traineeId == traineeId }.sorted { $0.completedAt > $1.completedAt }
    }

    func analytics(for traineeId: String) -> TraineeAnalytics? {
        traineeAnalyticsById[traineeId]
    }

    /// Reloads logs + analytics for a trainee (trainer detail pull-to-refresh / open).
    func refreshTraineePerformance(traineeId: String, periodDays: Int = 30) async throws {
        async let logsTask = api.trainerLogs(traineeId: traineeId)
        async let analyticsTask = api.trainerTraineeAnalytics(traineeId: traineeId, periodDays: periodDays)
        let (logs, analytics) = try await (logsTask, analyticsTask)
        replaceLogs(logs, traineeId: traineeId)
        // Prefer full /logs list; merge any recentLogs that might be newer.
        if !analytics.recentLogs.isEmpty {
            mergeLogs(analytics.recentLogs, traineeId: traineeId)
        }
        traineeAnalyticsById[traineeId] = analytics
    }

    /// Trainees currently assigned to this plan (latest assignment wins per trainee).
    func traineesAssigned(toPlanId planId: String) -> [(trainee: TraineeProfile, assignedAt: Date)] {
        let latestByTrainee = Dictionary(grouping: assignments.filter { $0.planId == planId }, by: \.traineeId)
            .compactMapValues { group in group.max(by: { $0.assignedAt < $1.assignedAt }) }
        return latestByTrainee.compactMap { traineeId, assignment in
            // Only count if this is still their active assigned plan.
            guard assignedPlan(forTraineeId: traineeId)?.id == planId,
                  let trainee = trainees.first(where: { $0.id == traineeId })
            else { return nil }
            return (trainee, assignment.assignedAt)
        }
        .sorted { lhs, rhs in
            let ln = user(forTrainee: lhs.trainee)?.name ?? ""
            let rn = user(forTrainee: rhs.trainee)?.name ?? ""
            return ln.localizedCaseInsensitiveCompare(rn) == .orderedAscending
        }
    }

    private func assignedPlan(forTraineeId traineeId: String) -> WorkoutPlan? {
        guard let assignment = assignments
            .filter({ $0.traineeId == traineeId })
            .sorted(by: { $0.assignedAt > $1.assignedAt })
            .first
        else { return nil }
        return plans.first { $0.id == assignment.planId }
    }

    /// Follow / adherence status for a trainee on a specific plan.
    func planFollowStatus(traineeId: String, plan: WorkoutPlan) -> PlanFollowStatus {
        let calendar = Calendar.current
        let today = Date()
        let planLogs = workoutLogs
            .filter { $0.traineeId == traineeId && $0.planId == plan.id }
            .sorted { $0.completedAt > $1.completedAt }

        if planLogs.contains(where: { calendar.isDate($0.completedAt, inSameDayAs: today) }) {
            return .trainedToday
        }
        if plan.session(on: today) != nil {
            return .dueToday
        }
        if let last = planLogs.first?.completedAt {
            let days = calendar.dateComponents([.day], from: last, to: today).day ?? 99
            if days <= 7 { return .following }
            return .behind
        }
        return .notStarted
    }

    /// % of scheduled plan days in the lookback window that have a matching workout log.
    func planAdherencePercent(traineeId: String, plan: WorkoutPlan, lookbackDays: Int = 14) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard lookbackDays > 0 else { return 0 }

        var expected = 0
        var completed = 0
        let planLogs = workoutLogs.filter { $0.traineeId == traineeId && $0.planId == plan.id }

        for offset in 0..<lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            guard plan.session(on: day) != nil else { continue }
            expected += 1
            if planLogs.contains(where: { calendar.isDate($0.completedAt, inSameDayAs: day) }) {
                completed += 1
            }
        }

        guard expected > 0 else {
            // Flat plans without scheduled days: any log in window counts as engaged.
            let recent = planLogs.contains {
                guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return false }
                return $0.completedAt >= start
            }
            return recent ? 100 : 0
        }
        return Int((Double(completed) / Double(expected) * 100).rounded())
    }

    func lastPlanWorkoutDate(traineeId: String, planId: String) -> Date? {
        workoutLogs
            .filter { $0.traineeId == traineeId && $0.planId == planId }
            .map(\.completedAt)
            .max()
    }

    func feedback(for traineeId: String) -> [TrainerFeedback] {
        feedback.filter { $0.traineeId == traineeId }.sorted { $0.createdAt > $1.createdAt }
    }

    func formReports(for traineeId: String) -> [FormReport] {
        formReports.filter { $0.traineeId == traineeId }.sorted { $0.createdAt > $1.createdAt }
    }

    func exercise(id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func savedAssessmentAge() -> Int? {
        guard let userId = session?.userId,
              let data = UserDefaults.standard.data(forKey: "assessment.payload.\(userId)"),
              let draft = try? JSONDecoder().decode(FitnessAssessment.self, from: data)
        else { return nil }
        return draft.age
    }

    var isBoostActiveForSandow: Bool {
        myBoost?.active == true || entitlements?.boost.active == true
    }

    /// Chart bars from last loaded Sandow response (empty → zeros for current period).
    var sandowChartScores: [TTSandowDayScore] {
        if let sandowScore {
            return Self.mapSandowPoints(sandowScore.points)
        }
        return Self.zeroSandowScores(for: sandowPeriod)
    }

    /// Loads live Sandow Score. Prefers `GET /me/sandow-score`; falls back to local compose on 404.
    func loadSandowScore(period: SandowScorePeriod? = nil, force: Bool = false) async {
        let target = period ?? sandowPeriod
        if isLoadingSandowScore && !force { return }
        sandowPeriod = target
        isLoadingSandowScore = true
        defer { isLoadingSandowScore = false }

        do {
            let response = try await api.sandowScore(period: target.queryValue)
            sandowScore = response
            return
        } catch let error as AppError where error.isNotFound {
            sandowScore = await composeSandowScoreFallback(period: target)
        } catch let error as AppError where error == .unauthorized {
            // Keep last known; session clear handled elsewhere.
        } catch {
            // Keep previous points while offline; only seed zeros if never loaded.
            if sandowScore == nil {
                sandowScore = await composeSandowScoreFallback(period: target)
            }
        }
    }

    /// Local compose when `/me/sandow-score` is not shipped yet. Never invents random scores.
    func composeSandowScoreFallback(period: SandowScorePeriod) async -> SandowScoreResponse {
        if session?.role == .trainer {
            if isBoostActiveForSandow {
                return await composeTrainerBoostSandow(period: period)
            }
            return composeTrainerRosterSandow(period: period)
        }
        return composeTraineeWorkoutSandow(period: period)
    }

    /// @deprecated Prefer `loadSandowScore` / `sandowChartScores`. Real data only — zeros when empty.
    func weeklySandowScores(forTraineeId traineeId: String? = nil) -> [TTSandowDayScore] {
        let id = traineeId ?? currentTrainee?.id
        let response = composeTraineeWorkoutSandow(period: .week, traineeId: id)
        return Self.mapSandowPoints(response.points)
    }

    private func composeTraineeWorkoutSandow(
        period: SandowScorePeriod,
        traineeId: String? = nil
    ) -> SandowScoreResponse {
        let id = traineeId ?? currentTrainee?.id
        let reports = id.map { formReports(for: $0) } ?? []
        let logs = id.map { self.logs(for: $0) } ?? []
        let points = Self.buildDayPoints(period: period) { dayStart in
            let dayReports = reports.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: dayStart) }
            let dayLogs = logs.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: dayStart) }
            if !dayReports.isEmpty {
                let avg = dayReports.map(\.score).reduce(0, +) / max(dayReports.count, 1)
                return min(100, max(0, avg))
            }
            if !dayLogs.isEmpty {
                return min(100, max(0, 55 + dayLogs.count * 8 + min(dayLogs.map(\.durationMinutes).reduce(0, +) / 10, 20)))
            }
            return 0
        }
        let empty = !points.contains { $0.score > 0 }
        return SandowScoreResponse(
            role: "trainee",
            mode: "workout_performance",
            period: period.queryValue,
            title: "TacTech Score",
            subtitle: "Workout & form performance",
            summaryScore: points.map(\.score).max(),
            emptyCaption: empty ? "Log workouts to build your score" : nil,
            points: points
        )
    }

    private func composeTrainerRosterSandow(period: SandowScorePeriod) -> SandowScoreResponse {
        let clients = currentTrainer.map { trainees(for: $0) } ?? []
        let allLogs = clients.flatMap { logs(for: $0.id) }
        let allReports = clients.flatMap { formReports(for: $0.id) }
        let points = Self.buildDayPoints(period: period) { dayStart in
            let dayReports = allReports.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: dayStart) }
            let dayLogs = allLogs.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: dayStart) }
            if !dayReports.isEmpty {
                let avg = dayReports.map(\.score).reduce(0, +) / max(dayReports.count, 1)
                return min(100, max(0, avg))
            }
            if !dayLogs.isEmpty {
                return min(100, max(0, 50 + dayLogs.count * 6))
            }
            return 0
        }
        let empty = !points.contains { $0.score > 0 }
        return SandowScoreResponse(
            role: "trainer",
            mode: "roster_performance",
            period: period.queryValue,
            title: "TacTech Score",
            subtitle: "Clients performance",
            summaryScore: points.map(\.score).max(),
            boostActive: false,
            traineeCount: clients.count,
            emptyCaption: empty ? "No client activity yet" : nil,
            points: points
        )
    }

    private func composeTrainerBoostSandow(period: SandowScorePeriod) async -> SandowScoreResponse {
        let days = period.dayCount
        do {
            let analytics = try await api.fetchCoachAnalytics(periodDays: days)
            let series = analytics.series ?? []
            let points: [SandowScorePoint]
            if series.isEmpty {
                points = Self.buildDayPoints(period: period) { _ in 0 }
            } else {
                let maxRaw = max(series.map { $0.views + $0.impressions + $0.contacts * 3 }.max() ?? 1, 1)
                points = series.map { day in
                    let raw = day.views + day.impressions + day.contacts * 3
                    let score = Int((Double(raw) / Double(maxRaw) * 100).rounded())
                    let label = Self.shortLabel(forDateKey: day.date, period: period)
                    return SandowScorePoint(
                        date: day.date,
                        label: label,
                        score: min(100, max(0, score)),
                        views: day.views,
                        impressions: day.impressions,
                        contacts: day.contacts
                    )
                }
            }
            let empty = !points.contains { $0.score > 0 }
            return SandowScoreResponse(
                role: "trainer",
                mode: "boost_analytics",
                period: period.queryValue,
                title: "TacTech Score",
                subtitle: "Boost reach",
                summaryScore: points.map(\.score).max(),
                boostActive: true,
                traineeCount: currentTrainer.map { trainees(for: $0).count },
                emptyCaption: empty ? "Boost to see reach" : nil,
                points: points
            )
        } catch {
            let points = Self.buildDayPoints(period: period) { _ in 0 }
            return SandowScoreResponse(
                role: "trainer",
                mode: "boost_analytics",
                period: period.queryValue,
                title: "TacTech Score",
                subtitle: "Boost reach",
                boostActive: true,
                emptyCaption: "Boost to see reach",
                points: points
            )
        }
    }

    private static func buildDayPoints(
        period: SandowScorePeriod,
        scoreForDay: (Date) -> Int
    ) -> [SandowScorePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dates: [Date]
        switch period {
        case .week:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))
                ?? today
            dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            dates = (0..<30).reversed().compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today)
            }
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return dates.map { day in
            let key = formatter.string(from: day)
            let label = shortLabel(forDateKey: key, period: period, date: day)
            return SandowScorePoint(date: key, label: label, score: scoreForDay(day))
        }
    }

    private static func shortLabel(forDateKey key: String, period: SandowScorePeriod, date: Date? = nil) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let resolved = date ?? formatter.date(from: key) ?? Date()
        switch period {
        case .week:
            return Weekday.from(date: resolved).short
        case .month:
            return "\(calendar.component(.day, from: resolved))"
        }
    }

    private static func mapSandowPoints(_ points: [SandowScorePoint]) -> [TTSandowDayScore] {
        points.map { point in
            let weekday: Weekday? = {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: point.date) {
                    return Weekday.from(date: date)
                }
                let lower = point.label.lowercased()
                return Weekday.allCases.first {
                    $0.short.lowercased() == lower || $0.rawValue == lower
                }
            }()
            return TTSandowDayScore(
                id: point.id,
                label: point.label.isEmpty ? (weekday?.short ?? point.date) : point.label,
                score: max(0, min(100, point.score)),
                weekday: weekday,
                dateKey: point.date.isEmpty ? nil : point.date
            )
        }
    }

    private static func zeroSandowScores(for period: SandowScorePeriod) -> [TTSandowDayScore] {
        mapSandowPoints(buildDayPoints(period: period) { _ in 0 })
    }

    /// Saved templates plus unique prescriptions previously used in this trainer's plans.
    func templates(forExerciseId exerciseId: String) -> [ExerciseTemplate] {
        guard let trainerId = currentTrainer?.id else { return [] }
        var seen = Set<String>()
        var result: [ExerciseTemplate] = []

        let saved = exerciseTemplates
            .filter { $0.trainerId == trainerId && $0.exerciseId == exerciseId }
            .sorted { $0.updatedAt > $1.updatedAt }
        for item in saved {
            let key = item.fingerprint
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }

        for plan in plans where plan.trainerId == trainerId {
            let fromDays = plan.days.flatMap(\.exercises)
            let fromFlat = plan.exercises
            for we in fromDays + fromFlat where we.exerciseId == exerciseId {
                let template = ExerciseTemplate.from(workoutExercise: we, trainerId: trainerId, planTitle: plan.title)
                let key = template.fingerprint
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(template)
            }
        }

        return result
    }

    func saveExerciseTemplate(_ template: ExerciseTemplate) {
        if let index = exerciseTemplates.firstIndex(where: { $0.id == template.id }) {
            exerciseTemplates[index] = template
        } else if let dup = exerciseTemplates.firstIndex(where: {
            $0.trainerId == template.trainerId
                && $0.exerciseId == template.exerciseId
                && $0.fingerprint == template.fingerprint
        }) {
            var updated = template
            updated.id = exerciseTemplates[dup].id
            updated.updatedAt = .now
            exerciseTemplates[dup] = updated
        } else {
            exerciseTemplates.insert(template, at: 0)
        }
        persistExerciseTemplates()
    }

    func saveTemplates(from plan: WorkoutPlan) {
        let trainerId = currentTrainer?.id ?? plan.trainerId
        let items = plan.days.flatMap(\.exercises)
        let source = items.isEmpty ? plan.exercises : items
        for we in source {
            saveExerciseTemplate(
                ExerciseTemplate.from(workoutExercise: we, trainerId: trainerId, planTitle: plan.title)
            )
        }
    }

    func deleteExerciseTemplate(id: String) {
        exerciseTemplates.removeAll { $0.id == id }
        persistExerciseTemplates()
    }

    func loadExerciseTemplates() {
        guard let trainerId = currentTrainer?.id,
              let data = UserDefaults.standard.data(forKey: "exercise.templates.\(trainerId)"),
              let decoded = try? JSONDecoder().decode([ExerciseTemplate].self, from: data)
        else {
            exerciseTemplates = []
            return
        }
        exerciseTemplates = decoded
    }

    private func persistExerciseTemplates() {
        guard let trainerId = currentTrainer?.id else { return }
        let mine = exerciseTemplates.filter { $0.trainerId == trainerId }
        guard let data = try? JSONEncoder().encode(mine) else { return }
        UserDefaults.standard.set(data, forKey: "exercise.templates.\(trainerId)")
    }

    func dailyMacros(for traineeId: String, on date: Date) -> MacroEstimate {
        if let cached = macrosByKey[macroKey(traineeId, on: date)] {
            return cached
        }
        return meals(for: traineeId, on: date).reduce(MacroEstimate(calories: 0, protein: 0, carbs: 0, fat: 0)) { partial, meal in
            MacroEstimate(
                calories: partial.calories + meal.macros.calories,
                protein: partial.protein + meal.macros.protein,
                carbs: partial.carbs + meal.macros.carbs,
                fat: partial.fat + meal.macros.fat
            )
        }
    }

    func lookupFood(query: String) -> FoodKnowledge? {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return nil }
        return foodCatalog.first { item in
            item.name.lowercased().contains(needle) || item.keywords.contains { $0.contains(needle) || needle.contains($0) }
        }
    }

    func searchFood(query: String) async -> FoodKnowledge? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return lookupFood(query: query) }
        if let remote = try? await api.lookupFood(query: query) {
            if !foodCatalog.contains(where: { $0.name == remote.name }) {
                foodCatalog.insert(remote, at: 0)
            }
            return remote
        }
        return lookupFood(query: query)
    }

    func refreshDay(for traineeId: String, on date: Date) async {
        do {
            if session?.role == .trainer {
                let remoteMeals = try await api.trainerMeals(traineeId: traineeId, on: date)
                replaceMeals(remoteMeals, traineeId: traineeId, on: date)
                if let macros = try? await api.trainerMacros(traineeId: traineeId, on: date) {
                    macrosByKey[macroKey(traineeId, on: date)] = macros
                }
            } else if currentTrainee?.id == traineeId {
                let remoteMeals = try await api.traineeMeals(on: date)
                replaceMeals(remoteMeals, traineeId: traineeId, on: date)
                if let macros = try? await api.traineeMacros(on: date) {
                    macrosByKey[macroKey(traineeId, on: date)] = macros
                }
            }
        } catch {
            if let error = error as? AppError, error == .unauthorized {
                clearLocalSession()
            }
        }
    }

    private func refreshSession() async throws {
        do {
            let me = try await api.me()
            if let user = me.resolvedUser {
                upsert(user.asUser())
                session = Session(userId: user.id, role: user.role)
            } else if session == nil {
                throw AppError.unauthorized
            }
            if let trainer = me.trainer { upsert(trainer) }
            if let trainee = me.trainee {
                // `/me` can lag Accept — don't clobber a just-applied trainerId with nil.
                upsertTraineePreservingCoachLink(trainee)
            }
            applyServerGateFlags(
                assessmentCompleted: me.assessmentCompleted,
                onboardingCompleted: me.onboardingCompleted
            )
            refreshAssessmentFlag()
        } catch {
            if session == nil { throw error }
        }

        exercises = try await api.exercises()
        if session?.role == .trainer {
            try await loadTrainerWorkspace()
            await fetchTrainerJoinRequests()
        } else {
            try await loadTraineeWorkspace()
            await refreshTraineeJoinState()
        }
        await refreshEntitlements()
        await refreshAIEntitlements()
        await refreshAICapabilities()
        // Avatar source of truth — required so home/profile work after reinstall.
        _ = try? await fetchMeProfile()
        if session?.role == .trainer {
            await refreshMyBoost()
        }
        AIStoreKitService.shared.startListeningForUpdates()
    }

    /// Loads `/me/entitlements`. Failures are silent — never blocks workspace or AI.
    func refreshEntitlements() async {
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            entitlements = try await api.entitlements()
        } catch let error as AppError where error == .unauthorized {
            // Session clear is handled by callers of authenticated workspace loads.
            entitlements = nil
        } catch {
            // Keep last known value; Phase 1 treats missing as inactive.
        }
    }

    /// Loads `/me/ai` (+ mirrors into entitlements.ai when possible). Silent on failure.
    func refreshAIEntitlements() async {
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            let me = try await api.myAI()
            aiEntitlement = me
            // Keep entitlements.ai in sync when we already have a payload.
            if var ents = entitlements {
                ents.ai = EntitlementSlice(
                    active: me.active,
                    plan: me.plan,
                    tier: nil,
                    startsAt: me.startsAt,
                    endsAt: me.endsAt,
                    source: me.source
                )
                entitlements = ents
            } else {
                await refreshEntitlements()
            }
        } catch let error as AppError where error == .unauthorized {
            aiEntitlement = nil
        } catch {
            // Keep last known.
        }
    }

    /// Loads `GET /coach/ai/capabilities` into `aiCapabilities`. Silent on failure.
    func refreshAICapabilities() async {
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            aiCapabilities = try await api.aiCapabilities()
        } catch let error as AppError where error == .unauthorized {
            // Keep fallback.
        } catch {
            // Keep last known / fallback.
        }
    }

    /// Solo trainee: `POST /coach/programs/generate` → upsert assigned plan.
    /// Returns the plan on success. Throws `aiRequired` / `conflict` / others for UI handling.
    @discardableResult
    func generateAIProgram(horizonDays: Int = 7, notes: String? = nil) async throws -> WorkoutPlan {
        guard session?.role == .trainee, let trainee = currentTrainee else {
            throw AppError.validation("Only trainees can generate an AI week.")
        }
        if trainee.trainerId != nil {
            throw AppError.conflict("You already have a trainer. Use their assigned plan.")
        }
        let plan = try await api.generateAIProgram(horizonDays: horizonDays, notes: notes)
        upsert(plan)
        assignments.removeAll { $0.traineeId == trainee.id }
        assignments.append(
            PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now)
        )
        planChangeNotice = "AI week ready"
        return plan
    }

    var hasLinkedTrainer: Bool {
        currentTrainee?.trainerId != nil
    }

    var canShowSoloAIGenerate: Bool {
        session?.role == .trainee
            && !hasLinkedTrainer
            && aiCapabilities.structuredPlanJson
    }

    /// Presents AI paywall for trainee and trainer. Returns true if presented / already showing.
    @discardableResult
    func presentAIPaywallIfNeeded(for error: Error) -> Bool {
        guard let app = error as? AppError, app.isAIRequired else { return false }
        guard session != nil else { return false }
        guard !showAIPaywall else { return true }
        showAIPaywall = true
        return true
    }

    /// Present AI paywall from Unlock CTA (both roles).
    func presentAIPaywall() {
        guard session != nil else { return }
        guard !showAIPaywall else { return }
        showAIPaywall = true
    }

    func dismissAIPaywall(unlocked: Bool) {
        showAIPaywall = false
        if unlocked {
            NotificationCenter.default.post(name: .ttAIPaywallUnlocked, object: nil)
        }
    }

    /// Loads trainer Boost status. Silent for non-trainers / failures.
    func refreshMyBoost() async {
        guard session?.role == .trainer else {
            myBoost = nil
            return
        }
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            myBoost = try await api.myBoost()
        } catch let error as AppError where error == .unauthorized {
            myBoost = nil
        } catch {
            // Keep last known value.
        }
    }

    /// Trainee contacts a public coach — opens existing human chat via `ttOpenHumanChat`.
    @discardableResult
    func contactCoach(profileId: String, message: String? = nil) async throws -> CoachContactResponse {
        guard session?.role == .trainee else {
            throw AppError.validation("Only trainees can contact coaches.")
        }
        let response = try await api.contactCoach(id: profileId, message: message)
        NotificationCenter.default.post(
            name: .ttOpenHumanChat,
            object: nil,
            userInfo: ["threadId": response.threadId]
        )
        return response
    }

    /// Trainee inquires about a coach package — opens human chat with package context.
    @discardableResult
    func inquireCoachPackage(
        coachProfileId: String,
        packageId: String,
        message: String? = nil
    ) async throws -> PackageInquireResponse {
        guard session?.role == .trainee else {
            throw AppError.validation("Only trainees can inquire about packages.")
        }
        let response = try await api.inquireCoachPackage(
            coachProfileId: coachProfileId,
            packageId: packageId,
            message: message
        )
        NotificationCenter.default.post(
            name: .ttOpenHumanChat,
            object: nil,
            userInfo: ["threadId": response.threadId]
        )
        return response
    }

    enum BoostPurchaseResult: Equatable {
        case confirmed(MeBoostDTO)
        case canceled
        case stillPending
    }

    struct BoostPurchaseOutcome: Equatable {
        var result: BoostPurchaseResult
        /// Soft publish warning from checkout response (non-blocking).
        var warning: String?
    }

    private static let pendingBoostDefaultsKey = "tactech.pendingBoostCheckout"

    /// Creates Boost checkout (Stripe or local wallet), presents pay URL, confirms on return.
    func purchaseBoost(productId: String, provider: String?) async throws -> BoostPurchaseOutcome {
        guard session?.role == .trainer else {
            throw AppError.validation("Only trainers can purchase Boost.")
        }
        let checkout = try await api.createBoostCheckout(productId: productId, provider: provider)
        rememberPendingBoost(from: checkout)
        let trimmedWarning = checkout.warning?.trimmingCharacters(in: .whitespacesAndNewlines)
        let warning = (trimmedWarning?.isEmpty == false) ? trimmedWarning : nil
        guard let url = URL(string: checkout.url) else {
            throw AppError.api("Invalid checkout URL.")
        }

        do {
            let callback = try await BoostCheckoutPresenter.shared.present(checkoutURL: url)
            let result = try await finalizeBoostCallback(callback)
            return BoostPurchaseOutcome(result: result, warning: warning)
        } catch let error as BoostCheckoutPresenter.PresentError where error == .canceled {
            clearPendingBoost()
            return BoostPurchaseOutcome(result: .canceled, warning: warning)
        }
    }

    /// Handles `tactech://billing/boost/…` from `onOpenURL` (Safari / cold start).
    @discardableResult
    func handleOpenURL(_ url: URL) async -> Bool {
        if pendingBoostCheckout == nil {
            restorePendingBoostFromDisk()
        }
        guard let outcome = BoostBillingURL.parse(url) else { return false }
        switch outcome {
        case .cancel:
            clearPendingBoost()
            NotificationCenter.default.post(name: .ttBoostCheckoutCanceled, object: nil)
            return true
        case .stripeSuccess(let sessionId):
            do {
                _ = try await confirmBoostCheckout(
                    checkoutSessionId: sessionId,
                    attemptId: nil,
                    provider: pendingBoostCheckout?.provider ?? "stripe",
                    retryIfInactive: true
                )
                NotificationCenter.default.post(name: .ttBoostCheckoutSucceeded, object: nil)
                NotificationCenter.default.post(name: .ttSandowScoreShouldRefresh, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .ttBoostCheckoutFailed,
                    object: nil,
                    userInfo: ["detail": error.localizedDescription]
                )
            }
            return true
        case .localSuccess(let attemptId):
            do {
                let provider = pendingBoostCheckout?.provider
                _ = try await confirmBoostCheckout(
                    checkoutSessionId: nil,
                    attemptId: attemptId,
                    provider: provider,
                    retryIfInactive: true
                )
                NotificationCenter.default.post(name: .ttBoostCheckoutSucceeded, object: nil)
                NotificationCenter.default.post(name: .ttSandowScoreShouldRefresh, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .ttBoostCheckoutFailed,
                    object: nil,
                    userInfo: ["detail": error.localizedDescription]
                )
            }
            return true
        }
    }

    private func finalizeBoostCallback(_ url: URL) async throws -> BoostPurchaseResult {
        guard let outcome = BoostBillingURL.parse(url) else {
            if let pending = pendingBoostCheckout, pending.hasIdentity {
                let boost = try await confirmBoostCheckout(
                    checkoutSessionId: pending.checkoutSessionId,
                    attemptId: pending.attemptId,
                    provider: pending.provider,
                    retryIfInactive: true
                )
                return boost.active ? .confirmed(boost) : .stillPending
            }
            throw AppError.api("Unexpected checkout return.")
        }
        switch outcome {
        case .cancel:
            clearPendingBoost()
            return .canceled
        case .stripeSuccess(let sessionId):
            let boost = try await confirmBoostCheckout(
                checkoutSessionId: sessionId,
                attemptId: nil,
                provider: pendingBoostCheckout?.provider ?? "stripe",
                retryIfInactive: true
            )
            return boost.active ? .confirmed(boost) : .stillPending
        case .localSuccess(let attemptId):
            let boost = try await confirmBoostCheckout(
                checkoutSessionId: nil,
                attemptId: attemptId,
                provider: pendingBoostCheckout?.provider,
                retryIfInactive: true
            )
            return boost.active ? .confirmed(boost) : .stillPending
        }
    }

    /// Confirms Stripe session or local wallet attempt; retries when IPN lags.
    @discardableResult
    func confirmBoostCheckout(
        checkoutSessionId: String? = nil,
        attemptId: String? = nil,
        provider: String? = nil,
        retryIfInactive: Bool = false
    ) async throws -> MeBoostDTO {
        // Legacy call site: `confirmBoostCheckout(sessionId:)`.
        let session = checkoutSessionId
        let attempt = attemptId
        let prov = provider ?? pendingBoostCheckout?.provider

        var lastError: Error?
        let attempts = retryIfInactive ? 3 : 1
        for i in 0..<attempts {
            if i > 0 {
                try? await Task.sleep(for: .milliseconds(900 + i * 300))
            }
            do {
                let boost = try await api.confirmBoostCheckout(
                    checkoutSessionId: session,
                    attemptId: attempt,
                    provider: prov
                )
                myBoost = boost
                if boost.active {
                    clearPendingBoost()
                    await refreshEntitlements()
                    await refreshMyBoost()
                    return myBoost ?? boost
                }
                // Inactive — IPN may still be in flight; keep pending and retry.
                lastError = AppError.api("Boost payment is still processing.")
            } catch {
                lastError = error
                await refreshMyBoost()
                await refreshEntitlements()
                if let boost = myBoost, boost.active {
                    clearPendingBoost()
                    return boost
                }
            }
        }

        await refreshMyBoost()
        await refreshEntitlements()
        if let boost = myBoost, boost.active {
            clearPendingBoost()
            return boost
        }
        throw lastError ?? AppError.api("Could not confirm Boost.")
    }

    /// Compatibility wrapper for Phase 2 Stripe-only call sites.
    @discardableResult
    func confirmBoostCheckout(sessionId: String) async throws -> MeBoostDTO {
        try await confirmBoostCheckout(
            checkoutSessionId: sessionId,
            attemptId: nil,
            provider: "stripe",
            retryIfInactive: true
        )
    }

    func rememberPendingBoost(from checkout: BoostCheckoutResponse) {
        pendingBoostCheckout = PendingBoostCheckout(
            checkoutSessionId: checkout.checkoutSessionId,
            attemptId: checkout.attemptId,
            provider: checkout.provider?.lowercased()
        )
    }

    func clearPendingBoost() {
        pendingBoostCheckout = nil
    }

    func restorePendingBoostFromDisk() {
        pendingBoostCheckout = Self.loadPendingBoost()
    }

    private static func persistPendingBoost(_ value: PendingBoostCheckout?) {
        if let value, value.hasIdentity,
           let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: pendingBoostDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingBoostDefaultsKey)
        }
    }

    private static func loadPendingBoost() -> PendingBoostCheckout? {
        guard let data = UserDefaults.standard.data(forKey: pendingBoostDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(PendingBoostCheckout.self, from: data)
    }

    private func loadTrainerWorkspace() async throws {
        plans = try await api.trainerPlans()
        loadExerciseTemplates()
        let items = try await api.trainerTrainees()
        if let trainerId = currentTrainer?.id {
            // Replace roster from server so removed trainees disappear on refresh.
            trainees.removeAll { $0.trainerId == trainerId }
        }
        apply(traineeItems: items)
        for trainee in trainees where trainee.trainerId == currentTrainer?.id {
            await loadTrainerDetail(traineeId: trainee.id)
        }
    }

    private func loadTrainerDetail(traineeId: String) async {
        if let detail = try? await api.trainerTrainee(id: traineeId) {
            apply(traineeItems: [detail])
        }
        if let logs = try? await api.trainerLogs(traineeId: traineeId) {
            replaceLogs(logs, traineeId: traineeId)
        }
        if let analytics = try? await api.trainerTraineeAnalytics(traineeId: traineeId) {
            traineeAnalyticsById[traineeId] = analytics
            if !analytics.recentLogs.isEmpty {
                mergeLogs(analytics.recentLogs, traineeId: traineeId)
            }
        }
        if let reports = try? await api.trainerFormReports(traineeId: traineeId) {
            replaceFormReports(reports, traineeId: traineeId)
        }
        if let notes = try? await api.trainerFeedback(traineeId: traineeId) {
            replaceFeedback(notes, traineeId: traineeId)
        }
        await refreshDay(for: traineeId, on: Date())
    }

    private func loadTraineeWorkspace() async throws {
        await enrichTraineeTrainerFromServer(allowClearOnNotFound: !isSyncingCoachLink)
        if let plan = try? await api.assignedPlan(), let trainee = currentTrainee {
            upsert(plan)
            assignments.removeAll { $0.traineeId == trainee.id }
            assignments.append(PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now))
        } else if let trainee = currentTrainee, trainee.trainerId == nil {
            assignments.removeAll { $0.traineeId == trainee.id }
        }
        if let logs = try? await api.traineeLogs(), let trainee = currentTrainee {
            replaceLogs(logs, traineeId: trainee.id)
        }
        if let reports = try? await api.traineeFormReports(), let trainee = currentTrainee {
            replaceFormReports(reports, traineeId: trainee.id)
        }
        if let notes = try? await api.traineeFeedback(), let trainee = currentTrainee {
            replaceFeedback(notes, traineeId: trainee.id)
        }
        if let trainee = currentTrainee {
            await refreshDay(for: trainee.id, on: Date())
        }
    }

    /// Pull latest assigned plan for the signed-in trainee (Workout tab / home refresh).
    func refreshAssignedPlanForCurrentTrainee() async {
        guard session?.role == .trainee, let trainee = currentTrainee else { return }
        do {
            if let plan = try await api.assignedPlan() {
                upsert(plan)
                assignments.removeAll { $0.traineeId == trainee.id }
                assignments.append(PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now))
            } else {
                assignments.removeAll { $0.traineeId == trainee.id }
            }
        } catch {
            // Keep local assignment on transient network errors.
        }
    }

    private func apply(auth response: AuthResponse) {
        TokenStore.save(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresIn: response.expiresIn
        )
        Task { await AuthTokenRefresher.shared.scheduleProactiveRefresh() }
        upsert(response.user.asUser())
        if let trainer = response.trainer { upsert(trainer) }
        if let trainee = response.trainee { upsert(trainee) }
        applyServerGateFlags(
            assessmentCompleted: response.assessmentCompleted,
            onboardingCompleted: response.onboardingCompleted
        )
        // Set session only after gate flags are known, then materialize UI flags immediately.
        session = Session(userId: response.user.id, role: response.user.role)
        refreshAssessmentFlag()
    }

    private func apply(traineeItems items: [TraineeListItem]) {
        for item in items {
            if let profile = item.profile { upsert(profile) }
            if let user = item.user {
                upsert(user.asUser())
            } else if let name = item.name, let userId = item.userId ?? item.profile?.userId {
                upsert(
                    User(
                        id: userId,
                        name: name,
                        email: item.email ?? "",
                        password: "",
                        role: .trainee,
                        createdAt: .now
                    )
                )
            }
            if let plan = item.assignedPlan, let trainee = item.profile {
                upsert(plan)
                assignments.removeAll { $0.traineeId == trainee.id }
                assignments.append(PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now))
            }
        }
    }

    private func upsert(_ user: User) {
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        } else {
            users.append(user)
        }
    }

    private func upsert(_ trainer: TrainerProfile) {
        if let index = trainers.firstIndex(where: { $0.id == trainer.id }) {
            trainers[index] = trainer
        } else {
            trainers.append(trainer)
        }
    }

    private func upsert(_ trainee: TraineeProfile) {
        if let index = trainees.firstIndex(where: { $0.id == trainee.id }) {
            trainees[index] = trainee
        } else {
            trainees.append(trainee)
        }
    }

    private func upsert(_ plan: WorkoutPlan) {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
    }

    private func upsert(_ log: WorkoutLog) {
        if let index = workoutLogs.firstIndex(where: { $0.id == log.id }) {
            workoutLogs[index] = log
        } else {
            workoutLogs.append(log)
        }
        NotificationCenter.default.post(name: .ttSandowScoreShouldRefresh, object: nil)
    }

    private func upsert(_ meal: Meal) {
        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index] = meal
        } else {
            meals.append(meal)
        }
    }

    private func upsert(_ item: TrainerFeedback) {
        if let index = feedback.firstIndex(where: { $0.id == item.id }) {
            feedback[index] = item
        } else {
            feedback.append(item)
        }
    }

    private func upsert(_ report: FormReport) {
        if let index = formReports.firstIndex(where: { $0.id == report.id }) {
            formReports[index] = report
        } else {
            formReports.append(report)
        }
    }

    private func replaceMeals(_ items: [Meal], traineeId: String, on date: Date) {
        meals.removeAll { $0.traineeId == traineeId && Calendar.current.isDate($0.eatenAt, inSameDayAs: date) }
        meals.append(contentsOf: items)
    }

    private func replaceLogs(_ items: [WorkoutLog], traineeId: String) {
        workoutLogs.removeAll { $0.traineeId == traineeId }
        workoutLogs.append(contentsOf: items)
    }

    /// Upsert logs without wiping the full trainee history (analytics recentLogs merge).
    private func mergeLogs(_ items: [WorkoutLog], traineeId: String) {
        for item in items where item.traineeId == traineeId || item.traineeId.isEmpty {
            var log = item
            if log.traineeId.isEmpty { log.traineeId = traineeId }
            if let idx = workoutLogs.firstIndex(where: { $0.id == log.id }) {
                workoutLogs[idx] = log
            } else {
                workoutLogs.append(log)
            }
        }
    }

    private func replaceFeedback(_ items: [TrainerFeedback], traineeId: String) {
        feedback.removeAll { $0.traineeId == traineeId }
        feedback.append(contentsOf: items)
    }

    private func replaceFormReports(_ items: [FormReport], traineeId: String) {
        formReports.removeAll { $0.traineeId == traineeId }
        formReports.append(contentsOf: items)
    }

    private func macroKey(_ traineeId: String, on date: Date) -> String {
        "\(traineeId)|\(APIConfig.dateQuery(date))"
    }

    private func clearLocalSession() {
        pendingJoinRequest = nil
        trainerJoinRequests = []
        Task { await AuthTokenRefresher.shared.cancelProactiveRefresh() }
        TokenStore.clear()
        session = nil
        isBootstrappingSession = false
        users = []
        trainers = []
        trainees = []
        exercises = []
        plans = []
        assignments = []
        workoutLogs = []
        traineeAnalyticsById = [:]
        meals = []
        feedback = []
        formReports = []
        macrosByKey = [:]
        foodCatalog = SeedData.foodCatalog
        exerciseTemplates = []
        entitlements = nil
        aiEntitlement = nil
        aiCapabilities = .fallback
        aiSoftNotice = nil
        myBoost = nil
        clearPendingBoost()
        showAIPaywall = false
        AIStoreKitService.shared.stopListeningForUpdates()
        assessmentCompleted = false
        profileSetupCompleted = false
        serverAssessmentCompleted = nil
        serverOnboardingCompleted = nil
        meProfileCache = nil
        remoteAvatarURL = nil
        remoteAvatarAsset = nil
        sandowScore = nil
        sandowPeriod = .week
        isLoadingSandowScore = false
    }

    // MARK: - Preview seeding

    private func seedPreviewData(as role: UserRole) {
        let now = Date()
        let trainerUser = User(
            id: "user-trainer-preview",
            name: "Alex Coach",
            email: "trainer@tactech.app",
            password: "preview",
            role: .trainer,
            createdAt: now
        )
        let traineeUser = User(
            id: "user-trainee-preview",
            name: "Maya Athlete",
            email: "trainee@tactech.app",
            password: "preview",
            role: .trainee,
            createdAt: now
        )
        let traineeUser2 = User(
            id: "user-trainee-preview-2",
            name: "Jordan Lee",
            email: "jordan@tactech.app",
            password: "preview",
            role: .trainee,
            createdAt: now
        )

        let trainer = TrainerProfile(
            id: "trainer-preview",
            userId: trainerUser.id,
            inviteCode: "TACT-MAYA",
            specialty: "Strength & Conditioning",
            yearsExperience: 8,
            bio: "Helping athletes move better every week.",
            gender: "Male",
            location: "Karachi"
        )

        let trainee = TraineeProfile(
            id: "trainee-preview",
            userId: traineeUser.id,
            trainerId: trainer.id,
            goal: "Build strength",
            heightCm: 168,
            weightKg: 62,
            dailyCalorieTarget: 2100,
            gender: "Female",
            location: "Karachi"
        )
        let trainee2 = TraineeProfile(
            id: "trainee-preview-2",
            userId: traineeUser2.id,
            trainerId: trainer.id,
            goal: "Fat loss",
            heightCm: 178,
            weightKg: 82,
            dailyCalorieTarget: 2400,
            gender: "Male",
            location: "Lahore"
        )

        let squat = Exercise(
            id: "ex-squat",
            name: "Back Squat",
            muscleGroup: "Legs",
            equipment: "Barbell",
            difficulty: "Intermediate",
            cues: ["Brace core", "Knees track toes"],
            icon: "figure.strengthtraining.traditional"
        )
        let press = Exercise(
            id: "ex-press",
            name: "Bench Press",
            muscleGroup: "Chest",
            equipment: "Barbell",
            difficulty: "Intermediate",
            cues: ["Retract scapula", "Control the descent"],
            icon: "dumbbell.fill"
        )

        let we1 = WorkoutExercise(
            id: "we-1",
            exerciseId: squat.id,
            sets: 4,
            reps: 8,
            restSeconds: 90,
            recommendedWeightKg: 40
        )
        let we2 = WorkoutExercise(
            id: "we-2",
            exerciseId: press.id,
            sets: 3,
            reps: 10,
            restSeconds: 75,
            recommendedWeightKg: 30
        )

        let todayWeekday = Weekday.from(date: now)
        let planDay = PlanDay(
            id: "day-today",
            weekday: todayWeekday,
            startTime: "18:00",
            title: "Full Body Strength",
            focus: "Compound lifts",
            durationMinutes: 45,
            location: "Gym",
            warmup: "5 min bike",
            cooldown: "Stretch",
            coachNotes: "Keep form crisp",
            exercises: [we1, we2]
        )

        let plan = WorkoutPlan(
            id: "plan-preview",
            trainerId: trainer.id,
            title: "Athlete Base Plan",
            focus: "Full body",
            durationMinutes: 45,
            level: "Intermediate",
            daysPerWeek: 4,
            exercises: [we1, we2],
            notes: "Preview plan",
            days: [planDay]
        )

        let assignment = PlanAssignment(
            id: "assign-preview",
            planId: plan.id,
            traineeId: trainee.id,
            assignedAt: now
        )

        let meal = Meal(
            id: "meal-preview",
            traineeId: trainee.id,
            name: "Grilled Chicken Bowl",
            eatenAt: now,
            portionGrams: 320,
            macros: MacroEstimate(calories: 480, protein: 42, carbs: 38, fat: 14),
            source: "manual",
            isEstimate: false
        )

        let log = WorkoutLog(
            id: "log-preview",
            traineeId: trainee.id,
            planId: plan.id,
            completedAt: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now,
            durationMinutes: 42,
            sets: [
                WorkoutSetLog(id: "set-1", exerciseId: squat.id, setNumber: 1, reps: 8, weightKg: 40)
            ]
        )

        let note = TrainerFeedback(
            id: "fb-preview",
            trainerId: trainer.id,
            traineeId: trainee.id,
            message: "Great depth on squats — keep bracing.",
            createdAt: now,
            relatedExerciseId: squat.id
        )

        let form = FormReport(
            id: "form-preview",
            traineeId: trainee.id,
            exerciseId: squat.id,
            createdAt: now,
            score: 86,
            cues: ["Brace earlier", "Drive through mid-foot"],
            repCount: 8
        )

        users = [trainerUser, traineeUser, traineeUser2]
        trainers = [trainer]
        trainees = [trainee, trainee2]
        exercises = [squat, press]
        plans = [plan]
        assignments = [assignment]
        meals = [meal]
        workoutLogs = [log]
        feedback = [note]
        formReports = [form]
        foodCatalog = SeedData.foodCatalog

        switch role {
        case .trainer:
            session = Session(userId: trainerUser.id, role: .trainer)
            exerciseTemplates = [
                ExerciseTemplate.from(workoutExercise: we1, trainerId: trainer.id, planTitle: plan.title)
            ]
        case .trainee:
            session = Session(userId: traineeUser.id, role: .trainee)
        }
    }
}

enum AppError: LocalizedError, Equatable {
    case invalidCredentials
    case validation(String)
    case api(String)
    case unauthorized
    case notFound(String)
    /// HTTP 403 — not allowed (e.g. only current trainees may review).
    case forbidden(String)
    /// Coach / upstream rate limit — `retryAfter` is suggested wait in seconds.
    case rateLimited(String, retryAfter: TimeInterval)
    /// HTTP 402 / `AI_REQUIRED` / `AI_QUOTA_EXCEEDED` — present AI paywall (trainee + trainer).
    case aiRequired(String)
    /// HTTP 409 — Apple subscription linked to another account / `HAS_TRAINER`.
    case conflict(String)
    /// HTTP 502 / `PROVIDER_ERROR` — JazzCash / Easypaisa / Stripe upstream.
    case providerError(String)
    /// HTTP 501/503 / `AI_CAPABILITY_UNAVAILABLE` — Coming soon placeholder.
    case aiUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Email or password is incorrect."
        case .validation(let message), .api(let message), .notFound(let message),
             .forbidden(let message),
             .aiRequired(let message), .conflict(let message), .providerError(let message),
             .aiUnavailable(let message): message
        case .rateLimited(let message, _): message
        case .unauthorized: "Please sign in again."
        }
    }

    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    var isAIRequired: Bool {
        if case .aiRequired = self { return true }
        return false
    }

    var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }

    var isAIUnavailable: Bool {
        if case .aiUnavailable = self { return true }
        return false
    }

    var retryAfterSeconds: TimeInterval? {
        if case let .rateLimited(_, retryAfter) = self { return retryAfter }
        return nil
    }
}
