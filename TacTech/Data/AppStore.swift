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
    var assessmentCompleted = false
    var profileSetupCompleted = false
    /// Trainer-saved exercise prescriptions (local).
    var exerciseTemplates: [ExerciseTemplate] = []
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
            try await refreshSession()
            refreshAssessmentFlag()
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
        refreshAssessmentFlag()
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
        refreshAssessmentFlag()
    }

    /// Apply profile-setup fields collected at signup (role-specific).
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

        guard let userId = session?.userId else { return }
        var payload: [String: Any] = [
            "gender": trimmedGender,
            "location": trimmedLocation
        ]
        if let heightCm { payload["heightCm"] = heightCm }
        if let weightKg { payload["weightKg"] = weightKg }
        UserDefaults.standard.set(payload, forKey: "profile.setup.\(userId)")
    }

    func updateCurrentUserName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var user = currentUser else { return }
        user.name = trimmed
        upsert(user)
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
        guard let userId = session?.userId else { return }
        UserDefaults.standard.set(true, forKey: "assessment.completed.\(userId)")
        assessmentCompleted = true
    }

    func markProfileSetupCompleted() {
        guard let userId = session?.userId else { return }
        UserDefaults.standard.set(true, forKey: "profile.setup.completed.\(userId)")
        profileSetupCompleted = true
    }

    func refreshAssessmentFlag() {
        guard let userId = session?.userId else {
            assessmentCompleted = false
            profileSetupCompleted = false
            return
        }
        // Both trainer and trainee must complete their role-specific assessment once.
        assessmentCompleted = UserDefaults.standard.bool(forKey: "assessment.completed.\(userId)")
        profileSetupCompleted = UserDefaults.standard.bool(forKey: "profile.setup.completed.\(userId)")
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
            saveTemplates(from: created)
        } else if currentTrainer != nil {
            upsert(draft)
            saveTemplates(from: draft)
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

    /// Weekly Sandow score bars — real form scores when available, else plan consistency.
    func weeklySandowScores(forTraineeId traineeId: String? = nil) -> [TTSandowDayScore] {
        let calendar = Calendar.current
        let today = Date()
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let id = traineeId ?? currentTrainee?.id
        let reports = id.map { formReports(for: $0) } ?? []
        let weekLogs = id.map { self.logs(for: $0) } ?? []

        return Weekday.allCases.map { day in
            let dayDate = calendar.date(byAdding: .day, value: day.sortIndex, to: start) ?? today
            let dayReports = reports.filter { calendar.isDate($0.createdAt, inSameDayAs: dayDate) }
            let dayLogs = weekLogs.filter { calendar.isDate($0.completedAt, inSameDayAs: dayDate) }
            let score: Int
            if !dayReports.isEmpty {
                let avg = dayReports.map(\.score).reduce(0, +) / dayReports.count
                score = min(100, max(60, avg))
            } else if !dayLogs.isEmpty {
                score = min(100, max(70, 72 + dayLogs.count * 6))
            } else {
                // Stable placeholder so the chart never looks empty.
                let seed = abs((id ?? "x").hashValue &+ day.sortIndex * 17)
                score = 68 + (seed % 22)
            }
            return TTSandowDayScore(id: day.rawValue, weekday: day, score: score)
        }
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
        loadExerciseTemplates()
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
        exerciseTemplates = []
        assessmentCompleted = false
        profileSetupCompleted = false
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

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Email or password is incorrect."
        case .validation(let message), .api(let message), .notFound(let message): message
        case .unauthorized: "Session expired. Please sign in again."
        }
    }
}
