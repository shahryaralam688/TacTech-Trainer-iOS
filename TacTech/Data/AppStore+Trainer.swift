import Foundation
import Observation
import UIKit

extension AppStore {

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

    /// Returns whether the list loaded (callers may ignore it). Errors are still swallowed as before.
    @discardableResult
    func fetchTrainerJoinRequests() async -> Bool {
        guard session?.role == .trainer else { return true }
        do {
            trainerJoinRequests = try await api.trainerJoinRequests(status: "pending")
            return true
        } catch {
            #if DEBUG
            print("[TacTech] fetchTrainerJoinRequests failed: \(error.localizedDescription)")
            #endif
            return false
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

    // MARK: - Trainer: live workout session

    /// The trainee profile screen tells the store which trainee is open (nil when it closes).
    @MainActor
    func setOpenTraineeProfile(_ traineeId: String?) {
        openTraineeProfileId = traineeId
    }

    private static func sameSession(_ a: WorkoutSession?, _ b: WorkoutSession?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?):
            return a.id == b.id && a.planId == b.planId && a.dayId == b.dayId
                && a.startedAt == b.startedAt && a.completedAt == b.completedAt && a.sets == b.sets
        default: return false
        }
    }

    /// Fetches and stores one trainee's live session. Writes only when the value changed. A failed fetch
    /// keeps the last known state (no error surfaced). Never polls — callers trigger it.
    @MainActor
    func refreshLiveSession(traineeId: String) async {
        guard session?.role == .trainer, !traineeId.isEmpty else { return }
        let fetched: WorkoutSession?
        do {
            fetched = try await api.trainerActiveSession(traineeId: traineeId)
        } catch {
            return
        }
        let live = (fetched?.completedAt == nil) ? fetched : nil
        if !Self.sameSession(liveSessionByTrainee[traineeId], live) {
            if let live { liveSessionByTrainee[traineeId] = live } else { liveSessionByTrainee[traineeId] = nil }
        }
        if live != nil {
            if !trainingNowIds.contains(traineeId) { trainingNowIds.insert(traineeId) }
        } else if trainingNowIds.contains(traineeId) {
            trainingNowIds.remove(traineeId)
        }
    }

    /// `workout.session.changed` (already deduplicated by the socket owner).
    /// started / set_logged add the trainee to `trainingNowIds`; completed / discarded remove them.
    /// For the OPEN profile only, bursts within ~400 ms become one refetch; a "completed" event also reloads
    /// that trainee's logs (existing reload) so the Finished state can appear.
    @MainActor
    func handleWorkoutSessionChanged(traineeId: String, action: String) {
        guard session?.role == .trainer, !traineeId.isEmpty else { return }
        switch action.lowercased() {
        case "started", "set_logged":
            if !trainingNowIds.contains(traineeId) { trainingNowIds.insert(traineeId) }
        case "completed", "discarded":
            if trainingNowIds.contains(traineeId) { trainingNowIds.remove(traineeId) }
            if action.lowercased() == "completed" { pendingLiveCompletedFor.insert(traineeId) }
        default:
            break
        }
        guard openTraineeProfileId == traineeId else { return }
        scheduleLiveSessionRefresh(for: traineeId)
    }

    /// Socket reconnected: an open profile refetches (events may have been missed).
    @MainActor
    func handleRealtimeReconnected() {
        guard session?.role == .trainer, let id = openTraineeProfileId else { return }
        scheduleLiveSessionRefresh(for: id)
    }

    @MainActor
    private func scheduleLiveSessionRefresh(for traineeId: String) {
        liveSessionSyncTask?.cancel()
        liveSessionSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self.refreshLiveSession(traineeId: traineeId)
            if self.pendingLiveCompletedFor.remove(traineeId) != nil {
                // Finished state needs the new log.
                try? await self.refreshTraineePerformance(traineeId: traineeId)
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
    func upsertTraineePreservingCoachLink(_ incoming: TraineeProfile) {
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
    func enrichTraineeTrainerFromServer(allowClearOnNotFound: Bool) async {
        guard currentTrainee != nil else { return }
        do {
            let trainerPayload = try await launchAPI.traineeTrainer()
            if let trainer = trainerPayload.profile { upsert(trainer) }
            if let user = trainerPayload.user {
                upsert(user.asUser())
            } else if let name = trainerPayload.name,
                      let userId = trainerPayload.userId ?? trainerPayload.profile?.userId {
                upsert(User(
                    id: userId,
                    name: name,
                    email: trainerPayload.email ?? "",
                    password: "",
                    role: .trainer,
                    createdAt: .now,
                    avatarUrl: trainerPayload.avatarUrl,
                    avatarAsset: trainerPayload.avatarAsset
                ))
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
}
