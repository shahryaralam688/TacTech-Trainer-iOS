import Foundation

struct AssignPlanBody: Encodable {
    var planId: String
    var traineeId: String
}

struct FeedbackBody: Encodable {
    var traineeId: String
    var message: String
    var relatedExerciseId: String?
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

// MARK: - Workout session API contracts

struct WorkoutSessionBody: Encodable {
    var planId: String
    var dayId: String?

    // The backend field is `planDayId` (StartWorkoutSessionRequest.plan_day_id).
    enum CodingKeys: String, CodingKey {
        case planId
        case dayId = "planDayId"
    }
}

struct SessionSetBody: Encodable {
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double
    /// Optional timing (nil fields are omitted from the request).
    var durationSeconds: Int? = nil
    var restSeconds: Int? = nil
}

struct WorkoutSession: Decodable, Identifiable {
    var id: String
    var planId: String
    var dayId: String?
    var startedAt: Date
    var completedAt: Date?
    var durationMinutes: Int?
    var sets: [WorkoutSetLog]

    enum CodingKeys: String, CodingKey {
        case id, planId, startedAt, completedAt, durationMinutes, sets
        // The backend sends `planDayId` (WorkoutSessionOut.plan_day_id).
        case dayId = "planDayId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        planId = try c.decode(String.self, forKey: .planId)
        dayId = try c.decodeIfPresent(String.self, forKey: .dayId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        sets = try c.decodeIfPresent([WorkoutSetLog].self, forKey: .sets) ?? []
    }
}

struct CompleteSessionBody: Encodable {
    var durationMinutes: Int
    var durationSeconds: Int? = nil
    var totalRestSeconds: Int? = nil
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

extension APIClient {

    func exercises() async throws -> [Exercise] {
        try await sendArray("/exercises")
    }

    func trainerPlans() async throws -> [WorkoutPlan] {
        try await sendArray("/trainer/plans")
    }

    func createPlan(_ body: PlanBody) async throws -> WorkoutPlan? {
        try await sendOptional(path: "/trainer/plans", method: .post, body: body)
    }

    func updatePlan(id: String, _ body: PlanBody) async throws -> WorkoutPlan? {
        try await sendOptional(path: "/trainer/plans/\(id)", method: .patch, body: body)
    }

    func deletePlan(id: String) async throws {
        try await sendVoid(path: "/trainer/plans/\(id)", method: .delete, body: EmptyBody())
    }

    func assignPlan(planId: String, traineeId: String) async throws {
        try await sendVoid(
            path: "/trainer/assignments",
            method: .post,
            body: AssignPlanBody(planId: planId, traineeId: traineeId)
        )
    }

    func unassignPlan(planId: String, traineeId: String) async throws {
        try await sendVoid(
            path: "/trainer/assignments?planId=\(planId)&traineeId=\(traineeId)",
            method: .delete,
            body: EmptyBody()
        )
    }

    func trainerLogs(traineeId: String) async throws -> [WorkoutLog] {
        try await sendArray("/trainer/trainees/\(traineeId)/logs")
    }

    func trainerTraineeAnalytics(traineeId: String, periodDays: Int = 30) async throws -> TraineeAnalytics {
        try await send(
            path: "/trainer/trainees/\(traineeId)/analytics?periodDays=\(periodDays)",
            method: .get
        )
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

    // MARK: - Session endpoints

    func startSession(_ body: WorkoutSessionBody) async throws -> WorkoutSession {
        try await send(path: "/trainee/sessions", method: .post, body: body)
    }

    func activeSession() async throws -> WorkoutSession? {
        try? await send(path: "/trainee/sessions/active", method: .get)
    }

    /// Same request as `activeSession()`, but failures are thrown instead of becoming `nil`.
    /// Returns `nil` only when the server answered and says there is no active session
    /// (404, empty body, or JSON `null`). Network/server/decoding errors throw.
    func activeSessionThrowing() async throws -> WorkoutSession? {
        let data: Data
        do {
            data = try await raw(path: "/trainee/sessions/active", method: .get, body: Optional<EmptyBody>.none, authorized: true)
        } catch let error as AppError where error.isNotFound {
            return nil
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if data.isEmpty || text == "null" { return nil }
        return try decode(WorkoutSession.self, from: data)
    }

    /// Trainer: the trainee's live workout (`GET /trainer/trainees/{profileId}/sessions/active`).
    /// `nil` only when the server answers `null` / an empty body (no live session). 403/404 and
    /// network/decoding errors throw — they are NOT "no session".
    func trainerActiveSession(traineeId: String) async throws -> WorkoutSession? {
        let data = try await raw(
            path: "/trainer/trainees/\(traineeId)/sessions/active",
            method: .get,
            body: Optional<EmptyBody>.none,
            authorized: true
        )
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if data.isEmpty || text == "null" { return nil }
        return try decode(WorkoutSession.self, from: data)
    }

    func logSessionSet(sessionId: String, _ body: SessionSetBody) async throws -> WorkoutSetLog? {
        try await sendOptional(path: "/trainee/sessions/\(sessionId)/sets", method: .post, body: body)
    }

    func completeSession(sessionId: String, _ body: CompleteSessionBody) async throws -> WorkoutLog? {
        try await sendOptional(path: "/trainee/sessions/\(sessionId)/complete", method: .post, body: body)
    }

    func discardSession(sessionId: String) async throws {
        try await sendVoid(path: "/trainee/sessions/\(sessionId)/discard", method: .post, body: EmptyBody())
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
}
