import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppStore {
    let api = APIClient.shared
    /// Launch / sign-in flavour: fails fast instead of waiting for connectivity (limits in `TTNetworkTiming`).
    let launchAPI = APIClient(failFast: true)
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
    /// Meals the trainee repeats (server: eaten twice or more in 30 days). Refreshed when Nutrition opens and after a save.
    var frequentMeals: [FrequentMeal] = []
    var feedback: [TrainerFeedback] = []
    var formReports: [FormReport] = []
    var foodCatalog: [FoodKnowledge] = SeedData.foodCatalog
    var isRestoringSession = true
    /// The launch restore failed for a reason that is NOT a rejected sign-in (no connection, timeout, server error).
    /// The tokens are kept; the splash offers Retry. Only meaningful while `isRestoringSession` is true.
    var launchConnectionFailed = false
    /// Why the launch restore failed (offline / server unreachable / server error). Set together with `launchConnectionFailed`.
    var launchFailure: LaunchFailure?
    /// Set when cold launch entered offline / with backend unreachable so the store re-syncs once connectivity returns.
    var needsOfflineSync = false
    var assessmentCompleted = false
    var profileSetupCompleted = false
    /// Interactive login/signup in flight — keep auth UI until gates + workspace resolve (no splash replay).
    var isBootstrappingSession = false
    /// Trainer-saved exercise prescriptions (local).
    var exerciseTemplates: [ExerciseTemplate] = []
    /// Trainer-defined exercises added locally (catalog has no create API). Persisted per trainer.
    var customExercises: [Exercise] = []
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
    var traineeSessionUIDepth = 0
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
    /// Active workout session fetched from `GET /trainee/sessions/active`. Nil when none.
    var activeWorkoutSession: WorkoutSession?
    /// True while fetching or mutating the active session.
    var isLoadingSession = false

    // MARK: Trainer: live "Training now"
    /// Trainee PROFILE ids with a live workout session (from `workout.session.changed` and fetches).
    var trainingNowIds: Set<String> = []
    /// Last known live session per trainee profile id (filled by the trainee profile screen).
    var liveSessionByTrainee: [String: WorkoutSession] = [:]
    /// The trainee profile currently open, if any (set by that screen).
    var openTraineeProfileId: String?
    @ObservationIgnored var liveSessionSyncTask: Task<Void, Never>?
    @ObservationIgnored var sessionFetchGeneration = 0
    @ObservationIgnored private var backgroundRefreshTask: Task<Void, Never>?
    @ObservationIgnored var pendingLiveCompletedFor: Set<String> = []
    /// In-flight Finish call (guards against double finish).
    @ObservationIgnored var completeWorkoutTask: Task<Void, Error>?

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
    var macrosByKey: [String: MacroEstimate] = [:]
    /// Last values from `GET /me` or login/signup — nil means backend omitted the field.
    private var serverAssessmentCompleted: Bool?
    private var serverOnboardingCompleted: Bool?
    /// Coalesce `relationship.changed` + `relationship_ended` double-delivery.
    var relationshipReconcileTask: Task<Void, Never>?
    /// Coalesce `join_request_accepted` + `relationship.changed(linked)` into one atomic sync.
    var traineeCoachLinkSyncTask: Task<Void, Never>?
    var traineeCoachLinkSyncGeneration = 0
    /// Coalesce `plan.assignment.changed` + `plan_*` inbox types.
    var planAssignmentSyncTask: Task<Void, Never>?
    var pendingPlanAssignmentAction: String?
    var pendingPlanAssignmentTitle: String?
    var pendingPlanAssignmentTraineeProfileId: String?

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
        TTNetworkMonitor.startIfNeeded()   // so `LaunchFailure` can tell "offline" from "server unreachable"
        hydrateOfflineWorkspaceIfAvailable()
        startRestore()
    }

    /// The launch restore currently running (cancelled and replaced by `retryLaunchRestore`), and its watchdog.
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var restoreWatchdog: Task<Void, Never>?
    @ObservationIgnored private var offlineGraceTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotSaveTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectSyncTask: Task<Void, Never>?

    /// Starts exactly one restore (any earlier one is cancelled first) with a hard cap on its total time.
    private func startRestore() {
        restoreTask?.cancel()
        restoreWatchdog?.cancel()
        offlineGraceTask?.cancel()

        // Offline with a cached/JWT session: let the user straight into the app without waiting on doomed requests.
        if session != nil && !TTNetworkMonitor.isOnline {
            launchConnectionFailed = false
            launchFailure = nil
            isRestoringSession = false
            needsOfflineSync = true
            return
        }

        // Online (e.g. Wi-Fi connected) with a cached/JWT session, but backend may be down or slow:
        // cap splash wait to 1.5s so the app still opens smoothly while sync continues in the background.
        if session != nil {
            offlineGraceTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled, let self, self.isRestoringSession, self.session != nil else { return }
                self.launchConnectionFailed = false
                self.launchFailure = nil
                self.isRestoringSession = false
            }
        }

        let task = Task {
            await AuthTokenRefresher.shared.cancelInFlightRefresh()
            await restoreIfNeeded()
        }
        restoreTask = task
        restoreWatchdog = Task { [weak self] in
            try? await Task.sleep(for: TTNetworkTiming.restoreOverallLimit)
            guard !Task.isCancelled, let self else { return }
            task.cancel()
            if self.session != nil {
                self.needsOfflineSync = true
                self.launchConnectionFailed = false
                self.launchFailure = nil
                self.isRestoringSession = false
            } else if self.isRestoringSession, !self.launchConnectionFailed {
                // Still running after the cap with no local session: report it as unreachable/offline.
                self.launchFailure = TTNetworkMonitor.isOnline ? .unreachable : .offline
                self.launchConnectionFailed = true
            }
        }
    }

    /// Retry on the launch error state: drop the stuck request and send the same restore again.
    func retryLaunchRestore() {
        launchConnectionFailed = false
        launchFailure = nil
        isRestoringSession = true
        startRestore()
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
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else {
            isRestoringSession = false
            return
        }
        do {
            try await AuthTokenRefresher.shared.refreshIfExpiring()
            try await refreshSession()
            // A superseded (cancelled) attempt must not finish: its failed requests were swallowed on the way.
            try Task.checkCancellation()
            refreshAssessmentFlag()
            scheduleCoachMemorySync()
            await AuthTokenRefresher.shared.scheduleProactiveRefresh()
            await LocalizationController.shared.pullFromServer()
            try Task.checkCancellation()
            needsOfflineSync = false
            launchConnectionFailed = false
            launchFailure = nil
            isRestoringSession = false
            offlineGraceTask?.cancel()
            restoreWatchdog?.cancel()
            scheduleSaveOfflineSnapshot()
        } catch {
            // Superseded by a Retry: the new attempt owns the state.
            if Task.isCancelled { return }
            offlineGraceTask?.cancel()
            restoreWatchdog?.cancel()
            if TokenStore.accessToken() == nil && TokenStore.refreshToken() == nil {
                // The server really rejected the sign-in (401 after a refresh already cleared the tokens): sign out.
                clearLocalSession()
                isRestoringSession = false
            } else if session != nil {
                // Offline, timeout, or backend down while we have a local/JWT session: enter the app and sync later.
                needsOfflineSync = true
                launchConnectionFailed = false
                launchFailure = nil
                isRestoringSession = false
            } else {
                // No connection, timeout or a server error with no local session: keep tokens and offer Retry.
                launchFailure = LaunchFailure.classify(error).flatMap { $0 == .unauthorized ? nil : $0 } ?? .unreachable
                launchConnectionFailed = true
            }
        }
    }

    /// Quietly syncs the session in the background once network/backend comes back after an offline launch.
    func syncAfterReconnectIfNeeded() {
        guard needsOfflineSync, session != nil, !isRestoringSession else { return }
        guard reconnectSyncTask == nil else { return }
        needsOfflineSync = false
        reconnectSyncTask = Task { [weak self] in
            defer { self?.reconnectSyncTask = nil }
            guard let self else { return }
            do {
                try await AuthTokenRefresher.shared.refreshIfExpiring()
                try await self.refreshSession()
                self.refreshAssessmentFlag()
                self.scheduleSaveOfflineSnapshot()
            } catch {
                if TokenStore.accessToken() == nil && TokenStore.refreshToken() == nil {
                    self.clearLocalSession()
                } else if self.session != nil {
                    self.needsOfflineSync = true
                }
            }
        }
    }

    func login(email: String, password: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        // Stay on auth UI until gates resolve — avoids splash + welcome interstitial.
        isBootstrappingSession = true
        defer { isBootstrappingSession = false }
        let response = try await launchAPI.login(email: normalized, password: password)
        apply(auth: response)
        await finishSignInLoad()
    }

    /// After a successful sign-in / sign-up: load the workspace. If that fails or runs long, show the launch states
    /// (offline / not responding / still connecting) with Retry instead of leaving a spinner, and keep the tokens.
    private func finishSignInLoad() async {
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: TTNetworkTiming.serverWaitLimit)
            guard !Task.isCancelled else { return }
            self?.isRestoringSession = true          // hand over to the splash with "Still connecting…"
        }
        defer { watchdog.cancel() }
        do {
            try await refreshSession()
            refreshAssessmentFlag()
            scheduleCoachMemorySync()
            await LocalizationController.shared.pullFromServer()
            launchConnectionFailed = false
            launchFailure = nil
            isRestoringSession = false
        } catch {
            // Signed in, but the workspace could not load: same Retry states as at launch (retry = the launch restore).
            launchFailure = LaunchFailure.classify(error).flatMap { $0 == .unauthorized ? nil : $0 } ?? .unreachable
            launchConnectionFailed = true
            isRestoringSession = true
        }
    }

    func signup(name: String, email: String, password: String, role: UserRole, inviteCode: String?) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.validation("Enter your name.") }
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        guard password.count >= 6 else { throw AppError.validation("Password must be at least 6 characters.") }
        isBootstrappingSession = true
        defer { isBootstrappingSession = false }
        let response = try await launchAPI.signup(
            SignupBody(
                name: name,
                email: normalized,
                password: password,
                role: role.rawValue,
                inviteCode: inviteCode
            )
        )
        apply(auth: response)
        await finishSignInLoad()
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
        scheduleSaveOfflineSnapshot()
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
        try await launchAPI.requestPasswordReset(email: normalized)
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

    func savedAssessmentAge() -> Int? {
        guard let userId = session?.userId,
              let data = UserDefaults.standard.data(forKey: "assessment.payload.\(userId)"),
              let draft = try? JSONDecoder().decode(FitnessAssessment.self, from: data)
        else { return nil }
        return draft.age
    }

    func refreshSession() async throws {
        do {
            let me = try await launchAPI.me()
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
            throw error
        }

        exercises = try await launchAPI.exercises()
        if session?.role == .trainer {
            try await loadTrainerWorkspace()
        } else {
            try await loadTraineeWorkspace()
        }
        scheduleSaveOfflineSnapshot()

        // Everything below is non-critical for the first screen. Running it in the
        // background lets the splash clear as soon as Home has what it needs, instead
        // of blocking the launch on entitlements / AI / avatar / boost round-trips.
        let role = session?.role
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            if role == .trainer {
                await self.fetchTrainerJoinRequests()
            } else {
                await self.refreshTraineeJoinState()
            }
            guard !Task.isCancelled, self.session != nil else { return }
            await self.refreshEntitlements()
            await self.refreshAIEntitlements()
            await self.refreshAICapabilities()
            // Avatar source of truth — required so home/profile work after reinstall.
            _ = try? await self.fetchMeProfile()
            if role == .trainer {
                await self.refreshMyBoost()
            }
            guard !Task.isCancelled, self.session != nil else { return }
            AIStoreKitService.shared.startListeningForUpdates()
        }
    }

    private func loadTrainerWorkspace() async throws {
        plans = try await launchAPI.trainerPlans()
        loadExerciseTemplates()
        loadCustomExercises()
        mergeCustomExercises()
        let items = try await launchAPI.trainerTrainees()
        if let trainerId = currentTrainer?.id {
            // Replace roster from server so removed trainees disappear on refresh.
            trainees.removeAll { $0.trainerId == trainerId }
        }
        apply(traineeItems: items)
        // Load each trainee's detail concurrently instead of serially — a serial loop
        // made cold launch scale with roster size (one round-trip per trainee).
        let roster = trainees.filter { $0.trainerId == currentTrainer?.id }.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for traineeId in roster {
                group.addTask { [weak self] in
                    await self?.loadTrainerDetail(traineeId: traineeId)
                }
            }
        }
    }

    func loadTrainerDetail(traineeId: String) async {
        if let detail = try? await launchAPI.trainerTrainee(id: traineeId) {
            apply(traineeItems: [detail])
        }
        if let logs = try? await launchAPI.trainerLogs(traineeId: traineeId) {
            replaceLogs(logs, traineeId: traineeId)
        }
        if let analytics = try? await launchAPI.trainerTraineeAnalytics(traineeId: traineeId) {
            traineeAnalyticsById[traineeId] = analytics
            if !analytics.recentLogs.isEmpty {
                mergeLogs(analytics.recentLogs, traineeId: traineeId)
            }
        }
        if let reports = try? await launchAPI.trainerFormReports(traineeId: traineeId) {
            replaceFormReports(reports, traineeId: traineeId)
        }
        if let notes = try? await launchAPI.trainerFeedback(traineeId: traineeId) {
            replaceFeedback(notes, traineeId: traineeId)
        }
        await refreshDay(for: traineeId, on: Date(), failFast: true)
    }

    private func loadTraineeWorkspace() async throws {
        await enrichTraineeTrainerFromServer(allowClearOnNotFound: !isSyncingCoachLink)
        do {
            if var plan = try await launchAPI.assignedPlan(), let trainee = currentTrainee {
                if (plan.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    plan.source = plan.resolvedSource
                }
                upsert(plan)
                assignments.removeAll { $0.traineeId == trainee.id }
                assignments.append(PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now))
            } else if let trainee = currentTrainee {
                clearOrRetainLocalPlanAssignment(for: trainee)
            }
        } catch {
            // Keep existing local assignment on transient network errors.
        }
        if let logs = try? await launchAPI.traineeLogs(), let trainee = currentTrainee {
            replaceLogs(logs, traineeId: trainee.id)
        }
        if let reports = try? await launchAPI.traineeFormReports(), let trainee = currentTrainee {
            replaceFormReports(reports, traineeId: trainee.id)
        }
        if let notes = try? await launchAPI.traineeFeedback(), let trainee = currentTrainee {
            replaceFeedback(notes, traineeId: trainee.id)
        }
        if let trainee = currentTrainee {
            await refreshDay(for: trainee.id, on: Date(), failFast: true)
        }
    }

    func apply(auth response: AuthResponse) {
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
        scheduleSaveOfflineSnapshot()
    }

    func apply(traineeItems items: [TraineeListItem]) {
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
                        createdAt: .now,
                        avatarUrl: item.avatarUrl,
                        avatarAsset: item.avatarAsset
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

    func upsert(_ user: User) {
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            var merged = user
            if merged.avatarUrl == nil { merged.avatarUrl = users[index].avatarUrl }
            if merged.avatarAsset == nil { merged.avatarAsset = users[index].avatarAsset }
            users[index] = merged
        } else {
            users.append(user)
        }
    }

    func upsert(_ trainer: TrainerProfile) {
        if !trainer.id.hasPrefix("offline-") {
            trainers.removeAll { $0.userId == trainer.userId && $0.id.hasPrefix("offline-") }
        }
        if let index = trainers.firstIndex(where: { $0.id == trainer.id }) {
            trainers[index] = trainer
        } else {
            trainers.append(trainer)
        }
    }

    func upsert(_ trainee: TraineeProfile) {
        if !trainee.id.hasPrefix("offline-") {
            trainees.removeAll { $0.userId == trainee.userId && $0.id.hasPrefix("offline-") }
        }
        if let index = trainees.firstIndex(where: { $0.id == trainee.id }) {
            trainees[index] = trainee
        } else {
            trainees.append(trainee)
        }
    }

    func upsert(_ plan: WorkoutPlan) {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
    }

    func upsert(_ log: WorkoutLog) {
        if let index = workoutLogs.firstIndex(where: { $0.id == log.id }) {
            workoutLogs[index] = log
        } else {
            workoutLogs.append(log)
        }
        NotificationCenter.default.post(name: .ttSandowScoreShouldRefresh, object: nil)
    }

    func upsert(_ meal: Meal) {
        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index] = meal
        } else {
            meals.append(meal)
        }
    }

    func upsert(_ item: TrainerFeedback) {
        if let index = feedback.firstIndex(where: { $0.id == item.id }) {
            feedback[index] = item
        } else {
            feedback.append(item)
        }
    }

    func upsert(_ report: FormReport) {
        if let index = formReports.firstIndex(where: { $0.id == report.id }) {
            formReports[index] = report
        } else {
            formReports.append(report)
        }
    }

    func replaceMeals(_ items: [Meal], traineeId: String, on date: Date) {
        let incomingIds = Set(items.map(\.id))
        meals.removeAll {
            incomingIds.contains($0.id) || ($0.traineeId == traineeId && Calendar.current.isDate($0.eatenAt, inSameDayAs: date))
        }
        let normalized = items.map { item -> Meal in
            var copy = item
            if copy.traineeId.isEmpty { copy.traineeId = traineeId }
            return copy
        }
        meals.append(contentsOf: normalized)
    }

    /// Replaces everything the server returned for a time window (same data in, same data out, whatever the time zone).
    func replaceMeals(_ items: [Meal], traineeId: String, window: ClosedRange<Date>) {
        let incomingIds = Set(items.map(\.id))
        meals.removeAll {
            incomingIds.contains($0.id) || ($0.traineeId == traineeId && window.contains($0.eatenAt))
        }
        let normalized = items.map { item -> Meal in
            var copy = item
            if copy.traineeId.isEmpty { copy.traineeId = traineeId }
            return copy
        }
        meals.append(contentsOf: normalized)
    }

    func replaceLogs(_ items: [WorkoutLog], traineeId: String) {
        workoutLogs.removeAll { $0.traineeId == traineeId }
        workoutLogs.append(contentsOf: items)
    }

    /// Upsert logs without wiping the full trainee history (analytics recentLogs merge).
    func mergeLogs(_ items: [WorkoutLog], traineeId: String) {
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

    func macroKey(_ traineeId: String, on date: Date) -> String {
        "\(traineeId)|\(APIConfig.dateQuery(date))"
    }

    func clearLocalSession() {
        restoreTask?.cancel()
        restoreTask = nil
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        restoreTask?.cancel()
        restoreTask = nil
        restoreWatchdog?.cancel()
        restoreWatchdog = nil
        offlineGraceTask?.cancel()
        offlineGraceTask = nil
        snapshotSaveTask?.cancel()
        snapshotSaveTask = nil
        reconnectSyncTask?.cancel()
        reconnectSyncTask = nil
        needsOfflineSync = false
        Self.removeOfflineWorkspaceSnapshot()
        coachMemorySyncTask?.cancel()
        coachMemorySyncTask = nil
        liveSessionSyncTask?.cancel()
        liveSessionSyncTask = nil
        completeWorkoutTask?.cancel()
        completeWorkoutTask = nil
        relationshipReconcileTask?.cancel()
        relationshipReconcileTask = nil
        traineeCoachLinkSyncTask?.cancel()
        traineeCoachLinkSyncTask = nil
        planAssignmentSyncTask?.cancel()
        planAssignmentSyncTask = nil
        sessionFetchGeneration &+= 1
        activeWorkoutSession = nil
        isLoadingSession = false
        liveSessionByTrainee = [:]
        openTraineeProfileId = nil
        pendingLiveCompletedFor = []
        isSyncingCoachLink = false
        pendingJoinRequest = nil
        trainerJoinRequests = []
        Task { await AuthTokenRefresher.shared.cancelProactiveRefresh() }
        TokenStore.clear()
        HumanChatStore.shared.resetSession()
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
        frequentMeals = []
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

    // MARK: - Offline launch workspace cache

    private struct OfflineWorkspaceSnapshot: Codable {
        var session: Session
        var users: [User]
        var trainers: [TrainerProfile]
        var trainees: [TraineeProfile]
        var exercises: [Exercise]
        var plans: [WorkoutPlan]
        var assignments: [PlanAssignment]
        var workoutLogs: [WorkoutLog]
        var meals: [Meal]
        var feedback: [TrainerFeedback]
        var formReports: [FormReport]
        var assessmentCompleted: Bool
        var profileSetupCompleted: Bool
        var remoteAvatarURL: String?
        var remoteAvatarAsset: String?
    }

    nonisolated private static var offlineSnapshotURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TacTech", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("offline_workspace_v1.json")
    }

    nonisolated private static func removeOfflineWorkspaceSnapshot() {
        try? FileManager.default.removeItem(at: offlineSnapshotURL)
    }

    func scheduleSaveOfflineSnapshot() {
        guard let session else { return }
        UserDefaults.standard.set(session.role.rawValue, forKey: "last.session.role.\(session.userId)")
        let snapshot = OfflineWorkspaceSnapshot(
            session: session,
            users: users,
            trainers: trainers,
            trainees: trainees,
            exercises: exercises,
            plans: plans,
            assignments: assignments,
            workoutLogs: workoutLogs,
            meals: meals,
            feedback: feedback,
            formReports: formReports,
            assessmentCompleted: assessmentCompleted,
            profileSetupCompleted: profileSetupCompleted,
            remoteAvatarURL: remoteAvatarURL,
            remoteAvatarAsset: remoteAvatarAsset
        )
        snapshotSaveTask?.cancel()
        snapshotSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let url = Self.offlineSnapshotURL
            await Task.detached(priority: .utility) {
                if let data = try? JSONEncoder.tactech.encode(snapshot) {
                    try? data.write(to: url, options: .atomic)
                }
            }.value
        }
    }

    private func hydrateOfflineWorkspaceIfAvailable() {
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        let claims = Self.decodeJWTClaims(from: TokenStore.accessToken())
            ?? Self.decodeJWTClaims(from: TokenStore.refreshToken())

        if let data = try? Data(contentsOf: Self.offlineSnapshotURL),
           let snapshot = try? JSONDecoder.tactech.decode(OfflineWorkspaceSnapshot.self, from: data),
           claims == nil || snapshot.session.userId == claims?.userId {
            session = snapshot.session
            users = snapshot.users
            trainers = snapshot.trainers
            trainees = snapshot.trainees
            exercises = snapshot.exercises
            plans = snapshot.plans
            assignments = snapshot.assignments
            workoutLogs = snapshot.workoutLogs
            meals = snapshot.meals
            feedback = snapshot.feedback
            formReports = snapshot.formReports
            assessmentCompleted = snapshot.assessmentCompleted
            profileSetupCompleted = snapshot.profileSetupCompleted
            remoteAvatarURL = snapshot.remoteAvatarURL
            remoteAvatarAsset = snapshot.remoteAvatarAsset
            ensureMinimalOfflineEntities(for: snapshot.session, name: claims?.name, email: claims?.email)
            return
        }

        if let claims {
            let resolvedRole: UserRole = claims.role
                ?? UserDefaults.standard.string(forKey: "last.session.role.\(claims.userId)").flatMap(UserRole.init(rawValue:))
                ?? (UserDefaults.standard.data(forKey: "trainer.assessment.payload.\(claims.userId)") != nil ? .trainer : .trainee)
            let fallbackSession = Session(userId: claims.userId, role: resolvedRole)
            session = fallbackSession
            if UserDefaults.standard.object(forKey: "assessment.completed.\(claims.userId)") != nil {
                refreshAssessmentFlag()
            } else {
                assessmentCompleted = true
                profileSetupCompleted = UserDefaults.standard.bool(forKey: "profile.setup.completed.\(claims.userId)")
            }
            ensureMinimalOfflineEntities(for: fallbackSession, name: claims.name, email: claims.email)
        }
    }

    private func ensureMinimalOfflineEntities(for session: Session, name: String?, email: String?) {
        if !users.contains(where: { $0.id == session.userId }) {
            let fallbackName = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? (session.role == .trainer ? "Coach" : "Athlete")
            users.append(
                User(
                    id: session.userId,
                    name: fallbackName,
                    email: email ?? "",
                    password: "",
                    role: session.role,
                    createdAt: .now
                )
            )
        }
        if session.role == .trainee, !trainees.contains(where: { $0.userId == session.userId }) {
            trainees.append(
                TraineeProfile(
                    id: "offline-\(session.userId)",
                    userId: session.userId,
                    trainerId: nil,
                    goal: "",
                    heightCm: 0,
                    weightKg: 0,
                    dailyCalorieTarget: 2000
                )
            )
        } else if session.role == .trainer, !trainers.contains(where: { $0.userId == session.userId }) {
            trainers.append(
                TrainerProfile(
                    id: "offline-\(session.userId)",
                    userId: session.userId,
                    inviteCode: "",
                    specialty: "",
                    yearsExperience: 0,
                    bio: ""
                )
            )
        }
    }

    private static func decodeJWTClaims(from token: String?) -> (userId: String, role: UserRole?, name: String?, email: String?)? {
        guard let token, !token.isEmpty else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let userId = (json["userId"] as? String)
            ?? (json["user_id"] as? String)
            ?? (json["sub"] as? String)
        guard let userId, !userId.isEmpty else { return nil }
        let roleRaw = (json["role"] as? String)?.lowercased()
        let role = roleRaw.flatMap(UserRole.init(rawValue:))
        let name = json["name"] as? String
        let email = json["email"] as? String
        return (userId, role, name, email)
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
