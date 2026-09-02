import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private let api = APIClient()

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
    private var macrosByKey: [String: MacroEstimate] = [:]

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
        Task { await restoreIfNeeded() }
    }

    func restoreIfNeeded() async {
        defer { isRestoringSession = false }
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            try await refreshSession()
        } catch {
            clearLocalSession()
        }
    }

    func login(email: String, password: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        let response = try await api.login(email: normalized, password: password)
        apply(auth: response)
        try await refreshSession()
    }

    func signup(name: String, email: String, password: String, role: UserRole, inviteCode: String?) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.validation("Enter your name.") }
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        guard password.count >= 6 else { throw AppError.validation("Password must be at least 6 characters.") }
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
    }

    func requestPasswordReset(email: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        try await api.requestPasswordReset(email: normalized)
    }

    func logout() async {
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

    func createPlan(_ draft: WorkoutPlan) async throws {
        let created = try await api.createPlan(PlanBody(plan: draft))
        if var created {
            if created.days.isEmpty { created.days = draft.days }
            if created.notes == nil { created.notes = draft.notes }
            upsert(created)
        } else if currentTrainer != nil {
            upsert(draft)
            let remote = (try? await api.trainerPlans()) ?? []
            if !remote.isEmpty { plans = remote }
        }
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

    func linkTrainee(toInviteCode code: String) async throws {
        guard currentTrainee != nil else { throw AppError.validation("Only trainees can join a trainer.") }
        try await api.linkTrainer(inviteCode: code)
        try await refreshSession()
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

    func feedback(for traineeId: String) -> [TrainerFeedback] {
        feedback.filter { $0.traineeId == traineeId }.sorted { $0.createdAt > $1.createdAt }
    }

    func formReports(for traineeId: String) -> [FormReport] {
        formReports.filter { $0.traineeId == traineeId }.sorted { $0.createdAt > $1.createdAt }
    }

    func exercise(id: String) -> Exercise? {
        exercises.first { $0.id == id }
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
            if let trainee = me.trainee { upsert(trainee) }
        } catch {
            if session == nil { throw error }
        }

        exercises = try await api.exercises()
        if session?.role == .trainer {
            try await loadTrainerWorkspace()
        } else {
            try await loadTraineeWorkspace()
        }
    }

    private func loadTrainerWorkspace() async throws {
        plans = try await api.trainerPlans()
        let items = try await api.trainerTrainees()
        apply(traineeItems: items)
        for trainee in trainees {
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
        if let reports = try? await api.trainerFormReports(traineeId: traineeId) {
            replaceFormReports(reports, traineeId: traineeId)
        }
        if let notes = try? await api.trainerFeedback(traineeId: traineeId) {
            replaceFeedback(notes, traineeId: traineeId)
        }
        await refreshDay(for: traineeId, on: Date())
    }

    private func loadTraineeWorkspace() async throws {
        if let trainerPayload = try? await api.traineeTrainer() {
            if let trainer = trainerPayload.profile { upsert(trainer) }
            if let user = trainerPayload.user {
                upsert(user.asUser())
            } else if let name = trainerPayload.name, let userId = trainerPayload.userId ?? trainerPayload.profile?.userId {
                upsert(User(id: userId, name: name, email: trainerPayload.email ?? "", password: "", role: .trainer, createdAt: .now))
            }
        }
        if let plan = try? await api.assignedPlan(), let trainee = currentTrainee {
            upsert(plan)
            assignments.removeAll { $0.traineeId == trainee.id }
            assignments.append(PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now))
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

    private func apply(auth response: AuthResponse) {
        TokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        upsert(response.user.asUser())
        session = Session(userId: response.user.id, role: response.user.role)
        if let trainer = response.trainer { upsert(trainer) }
        if let trainee = response.trainee { upsert(trainee) }
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
        TokenStore.clear()
        session = nil
        users = []
        trainers = []
        trainees = []
        exercises = []
        plans = []
        assignments = []
        workoutLogs = []
        meals = []
        feedback = []
        formReports = []
        macrosByKey = [:]
        foodCatalog = SeedData.foodCatalog
    }
}

enum AppError: LocalizedError, Equatable {
    case invalidCredentials
    case validation(String)
    case api(String)
    case unauthorized
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Email or password is incorrect."
        case .validation(let message), .api(let message), .notFound(let message): message
        case .unauthorized: "Session expired. Please sign in again."
        }
    }
}
