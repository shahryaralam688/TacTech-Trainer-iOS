import Foundation
import Observation

@Observable
final class AppStore {
    private let persistence: PersistenceStore

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

    init(persistence: PersistenceStore = PersistenceStore()) {
        self.persistence = persistence
        bootstrap()
    }

    func login(email: String, password: String) throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let user = users.first(where: { $0.email == normalized && $0.password == password }) else {
            throw AppError.invalidCredentials
        }
        session = Session(userId: user.id, role: user.role)
        persist()
    }

    func signup(name: String, email: String, password: String, role: UserRole, inviteCode: String?) throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.validation("Enter your name.") }
        guard normalized.contains("@") else { throw AppError.validation("Enter a valid email.") }
        guard password.count >= 6 else { throw AppError.validation("Password must be at least 6 characters.") }
        guard !users.contains(where: { $0.email == normalized }) else { throw AppError.validation("An account with this email already exists.") }

        let user = User(id: UUID().uuidString, name: name, email: normalized, password: password, role: role, createdAt: .now)
        users.append(user)

        switch role {
        case .trainer:
            trainers.append(
                TrainerProfile(
                    id: UUID().uuidString,
                    userId: user.id,
                    inviteCode: Self.makeInviteCode(from: name),
                    specialty: "Strength & Conditioning",
                    yearsExperience: 3,
                    bio: "Helping athletes move better and get stronger."
                )
            )
        case .trainee:
            let trainer = trainers.first { $0.inviteCode.caseInsensitiveCompare(inviteCode ?? "") == .orderedSame }
            trainees.append(
                TraineeProfile(
                    id: UUID().uuidString,
                    userId: user.id,
                    trainerId: trainer?.id,
                    goal: "Build strength",
                    heightCm: 170,
                    weightKg: 70,
                    dailyCalorieTarget: 2200
                )
            )
        }

        session = Session(userId: user.id, role: role)
        persist()
    }

    func logout() {
        session = nil
        persist()
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

    func assign(planId: String, to traineeId: String) {
        assignments.removeAll { $0.traineeId == traineeId }
        assignments.append(PlanAssignment(id: UUID().uuidString, planId: planId, traineeId: traineeId, assignedAt: .now))
        persist()
    }

    func createPlan(title: String, focus: String, duration: Int, level: String, days: Int, exerciseDrafts: [WorkoutExercise]) {
        guard let trainer = currentTrainer else { return }
        plans.append(
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
        persist()
    }

    func linkTrainee(toInviteCode code: String) throws {
        guard var trainee = currentTrainee else { throw AppError.validation("Only trainees can join a trainer.") }
        guard let trainer = trainers.first(where: { $0.inviteCode.caseInsensitiveCompare(code) == .orderedSame }) else {
            throw AppError.validation("Invite code not found.")
        }
        trainee.trainerId = trainer.id
        if let index = trainees.firstIndex(where: { $0.id == trainee.id }) {
            trainees[index] = trainee
        }
        persist()
    }

    func saveWorkoutLog(_ log: WorkoutLog) {
        workoutLogs.append(log)
        persist()
    }

    func saveMeal(_ meal: Meal) {
        meals.append(meal)
        persist()
    }

    func saveFeedback(_ item: TrainerFeedback) {
        feedback.append(item)
        persist()
    }

    func saveFormReport(_ report: FormReport) {
        formReports.append(report)
        persist()
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
        meals(for: traineeId, on: date).reduce(MacroEstimate(calories: 0, protein: 0, carbs: 0, fat: 0)) { partial, meal in
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
        return foodCatalog.first { item in
            item.name.lowercased().contains(needle) || item.keywords.contains { $0.contains(needle) || needle.contains($0) }
        }
    }

    private func bootstrap() {
        if let snapshot = persistence.load() {
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
            session = snapshot.session
        } else {
            let seed = SeedData.make()
            users = seed.users
            trainers = seed.trainers
            trainees = seed.trainees
            exercises = seed.exercises
            plans = seed.plans
            assignments = seed.assignments
            workoutLogs = seed.workoutLogs
            meals = seed.meals
            feedback = seed.feedback
            formReports = seed.formReports
            persist()
        }
    }

    private func persist() {
        persistence.save(
            Snapshot(
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
                formReports: formReports
            )
        )
    }

    private static func makeInviteCode(from name: String) -> String {
        let prefix = name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined().uppercased()
        return "TACT-\(prefix.isEmpty ? "TT" : prefix)\(Int.random(in: 100...999))"
    }
}

enum AppError: LocalizedError {
    case invalidCredentials
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Email or password is incorrect."
        case .validation(let message): message
        }
    }
}

struct Snapshot: Codable {
    var session: Session?
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
}

struct PersistenceStore {
    private var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("tactech-store.json")
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
