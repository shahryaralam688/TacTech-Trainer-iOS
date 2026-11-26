import Foundation
import Observation
import UIKit

extension AppStore {

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

    // MARK: - Workout session lifecycle

    /// Fetches the active session and updates `activeWorkoutSession`. Safe to call on every Home appear.
    func refreshActiveSession() async {
        guard !isLoadingSession else { return }
        let generation = sessionFetchGeneration
        isLoadingSession = true
        defer { isLoadingSession = false }
        // On a thrown error keep the current session; clear only when the server answered "none".
        // (do/catch, not `try?`: `try?` would flatten "none" and "failed" into the same nil.)
        let result: WorkoutSession?
        do { result = try await api.activeSessionThrowing() } catch { return }
        // A Finish / start / discard / logout that happened while this request was in flight must not be undone by a stale answer.
        guard generation == sessionFetchGeneration, completeWorkoutTask == nil else { return }
        activeWorkoutSession = result
    }

    /// Starts a new session for the given plan/day. Throws if a session is already active.
    func startWorkoutSession(planId: String, dayId: String?) async throws -> WorkoutSession {
        isLoadingSession = true
        defer { isLoadingSession = false }
        let session = try await api.startSession(WorkoutSessionBody(planId: planId, dayId: dayId))
        sessionFetchGeneration &+= 1
        activeWorkoutSession = session
        return session
    }

    /// Saves one completed set to the active session. Returns the server-confirmed log entry or the
    /// local fallback if the server returns empty. Idempotent: the caller guards against duplicates.
    func logSet(sessionId: String, exerciseId: String, setNumber: Int, reps: Int, weightKg: Double,
                durationSeconds: Int? = nil, restSeconds: Int? = nil) async throws -> WorkoutSetLog {
        let body = SessionSetBody(exerciseId: exerciseId, setNumber: setNumber, reps: reps, weightKg: weightKg,
                                  durationSeconds: durationSeconds, restSeconds: restSeconds)
        let remote = try await api.logSessionSet(sessionId: sessionId, body)
        var log = remote ?? WorkoutSetLog(
            id: "\(exerciseId)-\(setNumber)",
            exerciseId: exerciseId, setNumber: setNumber, reps: reps, weightKg: weightKg
        )
        // Keep what we measured if the server doesn't echo the timing back.
        log.durationSeconds = log.durationSeconds ?? durationSeconds
        log.restSeconds = log.restSeconds ?? restSeconds
        // Mirror into the local session so progress ring is up-to-date without a full refresh.
        if activeWorkoutSession?.id == sessionId {
            if !(activeWorkoutSession?.sets.contains(where: { $0.exerciseId == log.exerciseId && $0.setNumber == log.setNumber }) ?? false) {
                activeWorkoutSession?.sets.append(log)
            }
        }
        return log
    }

    /// Completes the active session, saves the resulting WorkoutLog, and clears `activeWorkoutSession`.
    /// Throws if the server did not confirm; in that case the active session and its sets are untouched.
    /// Uses its own flag (not `isLoadingSession`) so a Home refresh can never block Finish. A second
    /// call while one is running waits for that run and shares its outcome — it never returns silently.
    func completeWorkoutSession(sessionId: String, durationMinutes: Int,
                                durationSeconds: Int? = nil, totalRestSeconds: Int? = nil) async throws {
        if let running = completeWorkoutTask {
            try await running.value
            return
        }
        let task = Task { @MainActor in
            try await self.performCompleteWorkoutSession(
                sessionId: sessionId, durationMinutes: durationMinutes,
                durationSeconds: durationSeconds, totalRestSeconds: totalRestSeconds
            )
        }
        completeWorkoutTask = task
        defer { completeWorkoutTask = nil }
        try await task.value
    }

    private func performCompleteWorkoutSession(sessionId: String, durationMinutes: Int,
                                                durationSeconds: Int?, totalRestSeconds: Int?) async throws {
        var log = try await api.completeSession(
            sessionId: sessionId,
            CompleteSessionBody(durationMinutes: durationMinutes, durationSeconds: durationSeconds, totalRestSeconds: totalRestSeconds)
        )
        // Keep what we measured if the server doesn't echo the timing back.
        let sessionDayId = activeWorkoutSession?.dayId
        if var completed = log {
            completed.durationSeconds = completed.durationSeconds ?? durationSeconds
            completed.totalRestSeconds = completed.totalRestSeconds ?? totalRestSeconds
            completed.planDayId = completed.planDayId ?? sessionDayId
            log = completed
        }
        // Server confirmed: the workout is finished from here on.
        sessionFetchGeneration &+= 1
        activeWorkoutSession = nil
        if let log { upsert(log) }
        // A failed refetch is not a failed workout — keep what we have and carry on.
        if let trainee = currentTrainee, let logs = try? await api.traineeLogs() {
            replaceLogs(logs, traineeId: trainee.id)
        }
    }

    /// Discards the active session without saving a workout log.
    func discardWorkoutSession(sessionId: String) async throws {
        isLoadingSession = true
        defer { isLoadingSession = false }
        try await api.discardSession(sessionId: sessionId)
        sessionFetchGeneration &+= 1
        activeWorkoutSession = nil
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
        applyPerformance([(traineeId, logs, analytics)])
    }

    /// Reloads logs + analytics for several trainees (trainer live sync). The requests run concurrently and the
    /// store is written ONCE at the end, and only if something actually changed.
    func refreshTraineesPerformance(traineeIds: [String], periodDays: Int = 30) async {
        let api = self.api
        let results = await withTaskGroup(of: (String, [WorkoutLog], TraineeAnalytics)?.self) { group -> [(String, [WorkoutLog], TraineeAnalytics)] in
            let load: @Sendable (String) async -> (String, [WorkoutLog], TraineeAnalytics)? = { id in
                async let logsTask = api.trainerLogs(traineeId: id)
                async let analyticsTask = api.trainerTraineeAnalytics(traineeId: id, periodDays: periodDays)
                guard let logs = try? await logsTask, let analytics = try? await analyticsTask else { return nil }
                return (id, logs, analytics)
            }
            // At most 4 trainees are in flight at once; the next one starts as soon as one finishes.
            let maxInFlight = 4
            var pending = traineeIds[...]
            for _ in 0..<min(maxInFlight, pending.count) {
                let id = pending.removeFirst()
                group.addTask { await load(id) }
            }
            var collected: [(String, [WorkoutLog], TraineeAnalytics)] = []
            for await item in group {
                if let item { collected.append(item) }
                if !pending.isEmpty {
                    let id = pending.removeFirst()
                    group.addTask { await load(id) }
                }
            }
            return collected
        }
        applyPerformance(results)
    }

    /// Same result as the old per-trainee `replaceLogs` + `mergeLogs` + analytics assignment, but built on local
    /// copies and assigned once — and not at all when nothing differs (an identical assignment still wakes every
    /// view that reads the property).
    private func applyPerformance(_ results: [(String, [WorkoutLog], TraineeAnalytics)]) {
        var nextLogs = workoutLogs
        var nextAnalytics = traineeAnalyticsById
        for (traineeId, logs, analytics) in results {
            // Prefer the full /logs list…
            if nextLogs.filter({ $0.traineeId == traineeId }) != logs {
                nextLogs.removeAll { $0.traineeId == traineeId }
                nextLogs.append(contentsOf: logs)
            }
            // …then merge any recentLogs that might be newer.
            for item in analytics.recentLogs where item.traineeId == traineeId || item.traineeId.isEmpty {
                var log = item
                if log.traineeId.isEmpty { log.traineeId = traineeId }
                if let idx = nextLogs.firstIndex(where: { $0.id == log.id }) {
                    if nextLogs[idx] != log { nextLogs[idx] = log }
                } else {
                    nextLogs.append(log)
                }
            }
            nextAnalytics[traineeId] = analytics
        }
        if nextLogs != workoutLogs { workoutLogs = nextLogs }
        if nextAnalytics != traineeAnalyticsById { traineeAnalyticsById = nextAnalytics }
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

    func assignedPlan(forTraineeId traineeId: String) -> WorkoutPlan? {
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

    // MARK: - Custom exercises (local, trainer-defined)

    /// Creates a local custom exercise, merges it into the live catalog, and persists it.
    /// Returns the new exercise so the caller can keep the user on the selection screen.
    @discardableResult
    func addCustomExercise(name: String, muscleGroup: String, equipment: String, difficulty: String) -> Exercise {
        let exercise = Exercise(
            id: "custom-\(UUID().uuidString)",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            muscleGroup: muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines),
            equipment: equipment.trimmingCharacters(in: .whitespacesAndNewlines),
            difficulty: difficulty.trimmingCharacters(in: .whitespacesAndNewlines),
            cues: [],
            icon: "figure.strengthtraining.traditional"
        )
        customExercises.insert(exercise, at: 0)
        if !exercises.contains(where: { $0.id == exercise.id }) {
            exercises.insert(exercise, at: 0)
        }
        persistCustomExercises()
        return exercise
    }

    func loadCustomExercises() {
        guard let trainerId = currentTrainer?.id,
              let data = UserDefaults.standard.data(forKey: "exercise.custom.\(trainerId)"),
              let decoded = try? JSONDecoder().decode([Exercise].self, from: data)
        else {
            customExercises = []
            return
        }
        customExercises = decoded
    }

    /// Re-adds persisted custom exercises after the backend catalog reload replaces `exercises`.
    func mergeCustomExercises() {
        for ex in customExercises where !exercises.contains(where: { $0.id == ex.id }) {
            exercises.insert(ex, at: 0)
        }
    }

    private func persistCustomExercises() {
        guard let trainerId = currentTrainer?.id,
              let data = try? JSONEncoder().encode(customExercises) else { return }
        UserDefaults.standard.set(data, forKey: "exercise.custom.\(trainerId)")
    }

    /// Pull latest assigned plan for the signed-in trainee (Workout tab / home refresh).
    func refreshAssignedPlanForCurrentTrainee() async {
        guard session?.role == .trainee, let trainee = currentTrainee else { return }
        do {
            if var plan = try await api.assignedPlan() {
                if (plan.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    plan.source = plan.resolvedSource
                }
                upsert(plan)
                assignments.removeAll { $0.traineeId == trainee.id }
                assignments.append(PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now))
            } else {
                // Solo AI generate assigns locally; `/trainee/assigned-plan` may still be empty.
                // Do not wipe a cached solo plan on refresh / Workout Hub open.
                clearOrRetainLocalPlanAssignment(for: trainee)
            }
        } catch {
            // Keep local assignment on transient network errors.
        }
    }

    /// When server has no assigned plan: clear for linked trainees; keep solo AI plan if still cached.
    func clearOrRetainLocalPlanAssignment(for trainee: TraineeProfile) {
        if trainee.trainerId != nil {
            assignments.removeAll { $0.traineeId == trainee.id }
            return
        }
        let latest = assignments
            .filter { $0.traineeId == trainee.id }
            .sorted { $0.assignedAt > $1.assignedAt }
            .first
        if let latest, plans.contains(where: { $0.id == latest.planId }) {
            return
        }
        assignments.removeAll { $0.traineeId == trainee.id }
    }
}
