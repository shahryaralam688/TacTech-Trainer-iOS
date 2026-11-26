import Foundation
import Security

struct APIUser: Codable, Hashable {
    var id: String
    var name: String
    var email: String
    var role: UserRole
    var createdAt: Date
    var avatarUrl: String? = nil
    var avatarAsset: String? = nil

    func asUser() -> User {
        User(
            id: id,
            name: name,
            email: email,
            password: "",
            role: role,
            createdAt: createdAt,
            avatarUrl: avatarUrl,
            avatarAsset: avatarAsset
        )
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
    /// Server source of truth — returning users skip assessment on new devices.
    var assessmentCompleted: Bool?
    var onboardingCompleted: Bool?
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
    var avatarUrl: String? = nil
    var avatarAsset: String? = nil
    /// Required from backend — gates assessment / profile setup (nil = legacy fallback).
    var assessmentCompleted: Bool?
    var onboardingCompleted: Bool?

    var resolvedUser: APIUser? {
        if let user { return user }
        guard let id, let name, let email, let role, let createdAt else { return nil }
        return APIUser(id: id, name: name, email: email, role: role, createdAt: createdAt, avatarUrl: avatarUrl, avatarAsset: avatarAsset)
    }
}

// MARK: - Personal Info /me/profile

struct MeProfileResponse: Decodable {
    var user: MeProfileUser
    var profile: EditableProfile
    var trainer: MeTrainerProfileDTO?
    var trainee: MeTraineeProfileDTO?
    var assessmentCompleted: Bool?
    var onboardingCompleted: Bool?
}

struct MeProfileUser: Decodable {
    var id: String
    var name: String
    var email: String
    var role: String
    var createdAt: Date?
    var avatarUrl: String?
    var avatarAsset: String?

    var resolvedRole: UserRole {
        UserRole(rawValue: role.lowercased()) ?? .trainee
    }
}

struct EditableProfile: Decodable {
    var gender: String?
    var location: String?
    var heightCm: Int?
    var weightKg: Double?
    var accountType: String?
    var avatarUrl: String?
    var avatarAsset: String?
    var phone: String?
    var bio: String?
}

struct MeTraineeProfileDTO: Decodable {
    var id: String
    var userId: String
    var trainerId: String?
    var goal: String?
    var heightCm: Int?
    var weightKg: Double?
    var dailyCalorieTarget: Int?
    var gender: String?
    var location: String?

    func asTraineeProfile() -> TraineeProfile {
        TraineeProfile(
            id: id,
            userId: userId,
            trainerId: trainerId,
            goal: goal ?? "",
            heightCm: heightCm ?? 0,
            weightKg: weightKg ?? 0,
            dailyCalorieTarget: dailyCalorieTarget ?? 0,
            gender: gender,
            location: location
        )
    }
}

struct MeTrainerProfileDTO: Decodable {
    var id: String
    var userId: String
    var inviteCode: String?
    var specialty: String?
    var yearsExperience: Int?
    var bio: String?
    var gender: String?
    var location: String?

    func asTrainerProfile(existing: TrainerProfile?) -> TrainerProfile {
        TrainerProfile(
            id: id,
            userId: userId,
            inviteCode: inviteCode ?? existing?.inviteCode ?? "",
            specialty: specialty ?? existing?.specialty ?? "",
            yearsExperience: yearsExperience ?? existing?.yearsExperience ?? 0,
            bio: bio ?? existing?.bio ?? "",
            gender: gender ?? existing?.gender,
            location: location ?? existing?.location
        )
    }
}

struct UpdateMeProfileBody: Encodable {
    var name: String? = nil
    var email: String? = nil
    var gender: String? = nil
    var location: String? = nil
    var heightCm: Int? = nil
    var weightKg: Double? = nil
    var avatarAsset: String? = nil

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(heightCm, forKey: .heightCm)
        try c.encodeIfPresent(weightKg, forKey: .weightKg)
        try c.encodeIfPresent(avatarAsset, forKey: .avatarAsset)
    }

    private enum CodingKeys: String, CodingKey {
        case name, email, gender, location, heightCm, weightKg, avatarAsset
    }
}

struct MeAvatarUploadResponse: Decodable {
    var avatarUrl: String?
    var avatarAsset: String?
}

struct ChangeMePasswordBody: Encodable {
    var currentPassword: String
    var newPassword: String
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

struct AssessmentBody: Encodable {
    var goal: String
    var gender: String
    var weightKg: Double
    var age: Int
    var heightCm: Double
    var hasTargetWeight: Bool?
    var targetWeightKg: Double
    var bmi: Double?
    var experienceLevel: String
    var hasExperience: Bool?
    var fitnessLevel: Int
    var activityLevel: String
    var workoutLocation: String
    var equipment: [String]
    var limitations: [String]
    var diet: String
    var daysPerWeek: Int
    var workoutDuration: String
    var exercisePreferences: [String]
    var supplementFrequency: String
    var takesSupplements: Bool?
    var supplements: [String]
    var calorieGoal: Int
    var sleepHours: String
    var sleepQuality: String
    var waterIntake: String
    var improvementAreas: [String]
    var frontPhotoCaptured: Bool
    var sidePhotoCaptured: Bool
    var backPhotoCaptured: Bool
    var bodyScanCaptured: Bool
    var voiceCaptured: Bool
    var concerns: String

    init(_ assessment: FitnessAssessment) {
        goal = assessment.goal
        gender = assessment.gender
        weightKg = assessment.weightKg
        age = assessment.age
        heightCm = assessment.heightCm
        hasTargetWeight = assessment.hasTargetWeight
        targetWeightKg = assessment.targetWeightKg
        bmi = assessment.bmi
        experienceLevel = assessment.experienceLevel
        hasExperience = assessment.hasExperience
        fitnessLevel = assessment.fitnessLevel
        activityLevel = assessment.activityLevel
        workoutLocation = assessment.workoutLocation
        equipment = assessment.equipment
        limitations = assessment.limitations
        diet = assessment.diet
        daysPerWeek = assessment.daysPerWeek
        workoutDuration = assessment.workoutDuration
        exercisePreferences = assessment.exercisePreferences
        supplementFrequency = assessment.supplementFrequency
        takesSupplements = assessment.takesSupplements
        supplements = assessment.supplements
        calorieGoal = assessment.calorieGoal
        sleepHours = assessment.sleepHours
        sleepQuality = assessment.sleepQuality
        waterIntake = assessment.waterIntake
        improvementAreas = assessment.improvementAreas
        frontPhotoCaptured = assessment.frontPhotoCaptured
        sidePhotoCaptured = assessment.sidePhotoCaptured
        backPhotoCaptured = assessment.backPhotoCaptured
        bodyScanCaptured = assessment.bodyScanCaptured
        voiceCaptured = assessment.voiceCaptured
        concerns = assessment.concerns
    }
}

struct TrainerAssessmentBody: Encodable {
    var coachingFocus: String
    var yearsExperience: Int
    var certifications: [String]
    var specialty: String
    var clientTypes: [String]
    var maxClients: Int
    var sessionStyle: String
    var daysPerWeek: Int
    var trainingModes: [String]
    var gender: String
    var bio: String
    var philosophy: String

    init(_ assessment: TrainerAssessment) {
        coachingFocus = assessment.coachingFocus
        yearsExperience = assessment.yearsExperience
        certifications = assessment.certifications
        specialty = assessment.specialty
        clientTypes = assessment.clientTypes
        maxClients = assessment.maxClients
        sessionStyle = assessment.sessionStyle
        daysPerWeek = assessment.daysPerWeek
        trainingModes = assessment.trainingModes
        gender = assessment.gender
        bio = assessment.bio
        philosophy = assessment.philosophy
    }
}

struct RefreshBody: Encodable {
    var refreshToken: String
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
    var mealType: String? = nil
    var notes: String? = nil
    var photoUrl: String? = nil
    var status: String? = nil
    var kind: String? = nil
    var detail: String? = nil
    var tz: String? = TimeZone.current.identifier
    /// Optional: the foods of a photo-analysed meal. Single-item callers leave it nil.
    var items: [MealItemBody]? = nil
}

/// PATCH /trainee/meals/{id}: only the fields that are set are sent.
struct UpdateMealBody: Encodable {
    var eatenAt: Date? = nil
    var portionGrams: Double? = nil
    var macros: MacroEstimate? = nil
    var status: String? = nil
    var kind: String? = nil
    var detail: String? = nil
    var tz: String? = TimeZone.current.identifier
}

struct UpdateTraineeGoalBody: Encodable {
    var dailyCalorieTarget: Int
}

struct MealPhotoUploadResponse: Decodable {
    var photoUrl: String
}

struct MealAnalyzeBody: Encodable {
    var photoUrl: String
    var tz: String? = TimeZone.current.identifier
}

struct MealAnalyzeAlternative: Decodable, Hashable {
    var name: String
    var kind: String?
    var portionGrams: Double?
    var macros: MacroEstimate?
}

/// One food found in the photos (`POST /trainee/meals/analyze`, multipart field `files`).
struct AnalyzedMealItem: Decodable, Hashable {
    var name: String?
    var searchKey: String?
    /// "plate" | "piece" | "drink"
    var category: String?
    var grams: Double?
    var portionLabel: String?
    var modifierLabel: String?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    /// "verified_label" | "database_match" | "ai_estimate"
    var trustSource: String?
    var confidence: Double?
    /// "curry_oil" | "tea_sugar" | "milk_type" | nil
    var modifierProfile: String?
    var alternatives: [String]?
    var suggestedModifiers: [String]?
}

struct MealPhotosAnalysis: Decodable {
    var isFood: Bool?
    var message: String?
    var mealTag: String?
    var items: [AnalyzedMealItem]?
}

/// `GET /trainee/meals/barcode/{code}` (`caloriesPer100g`, `proteinPer100g`, …, `barcode`) and
/// `POST /trainee/meals/parse-label` (`kcalPer100G`, `proteinPer100G`, …). Both spellings of every key decode.
struct BarcodeMealItem: Decodable, Hashable {
    var name: String?
    var caloriesPer100g: Double?
    var proteinPer100g: Double?
    var carbsPer100g: Double?
    var fatPer100g: Double?
    var servingGrams: Double?
    var category: String?
    var trustSource: String?
    var barcode: String?

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func double(_ names: [String]) -> Double? {
            for name in names {
                if let key = AnyKey(stringValue: name), let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
            }
            return nil
        }
        func string(_ names: [String]) -> String? {
            for name in names {
                if let key = AnyKey(stringValue: name), let value = try? c.decodeIfPresent(String.self, forKey: key) { return value }
            }
            return nil
        }
        name = string(["name"])
        caloriesPer100g = double(["caloriesPer100g", "caloriesPer100G", "kcalPer100g", "kcalPer100G"])
        proteinPer100g = double(["proteinPer100g", "proteinPer100G"])
        carbsPer100g = double(["carbsPer100g", "carbsPer100G"])
        fatPer100g = double(["fatPer100g", "fatPer100G"])
        servingGrams = double(["servingGrams"])
        category = string(["category"])
        trustSource = string(["trustSource"])
        barcode = string(["barcode"])
    }
}

struct BarcodeLookupResponse: Decodable {
    var found: Bool?
    var item: BarcodeMealItem?
}

/// `POST /trainee/meals/refine`: the tray as it is now, plus what the person wants changed.
/// TODO: the item keys are assumed to match `MealItemBody` (same as a saved meal's items).
typealias RefineMealItemBody = MealItemBody

struct RefineMealBody: Encodable {
    var items: [RefineMealItemBody]
    var instruction: String
}

struct ParseLabelBody: Encodable {
    var ocrText: String
    var productName: String?
}

/// `GET /trainee/meals/frequent`: meals eaten at least twice in the last 30 days.
struct FrequentMeal: Decodable, Identifiable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var count: Int?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var kind: String?
    var detail: String?
    var portionGrams: Double?
    /// The foods of the latest such meal (same keys as an analysed item).
    var mealItems: [AnalyzedMealItem]?
}

struct FrequentMealsResponse: Decodable {
    var items: [FrequentMeal]?
}

/// One item of a saved meal (`POST /trainee/meals` → `items`).
struct MealItemBody: Encodable {
    var name: String
    var searchKey: String?
    var category: String
    var grams: Double
    var portionLabel: String?
    var modifierLabel: String?
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var trustSource: String
    var confidence: Double?
}

struct MealAnalyzeResponse: Decodable {
    var name: String?
    var kind: String?
    var portionGrams: Double?
    var macros: MacroEstimate?
    var confidence: Double?
    var alternatives: [MealAnalyzeAlternative]?
}

struct MealSummaryBucket: Decodable, Identifiable, Hashable {
    var id: String { label + "-" + (title ?? "") }
    var label: String
    var title: String?
    var daysLogged: Int?
    var avgCalories: Int?
    var totalCalories: Int?
    var daysOverGoal: Int?
    var avgProtein: Double?
    var avgCarbs: Double?
    var avgFat: Double?
    var meals: [Meal]?
}

struct MealSummaryResponse: Decodable {
    var period: String?
    var goal: Int?
    var buckets: [MealSummaryBucket]?
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

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

actor APIClient {
    private let failFast: Bool
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// `failFast`: the launch / sign-in flavour (no waiting for connectivity, `TTNetworkTiming` limits, 5xx → `LaunchServerError`).
    init(failFast: Bool = false) {
        self.failFast = failFast
        let configuration: URLSessionConfiguration
        if failFast {
            configuration = TTNetworkTiming.failFastConfiguration()
        } else {
            configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.waitsForConnectivity = true
        }
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

    // MARK: - Personal Info / Profile

    func meProfile() async throws -> MeProfileResponse {
        try await send(path: "/me/profile", method: .get)
    }

    func patchMeProfile(_ body: UpdateMeProfileBody) async throws -> MeProfileResponse {
        try await send(path: "/me/profile", method: .patch, body: body)
    }

    func uploadMeAvatar(fileData: Data, filename: String, mimeType: String) async throws -> MeAvatarUploadResponse {
        try await sendMultipart(
            path: "/me/avatar",
            fields: [
                .file(name: "file", filename: filename, mimeType: mimeType, data: fileData)
            ]
        )
    }

    func deleteMeAvatar() async throws {
        try await sendVoid(path: "/me/avatar", method: .delete, body: EmptyBody())
    }

    func changeMePassword(currentPassword: String, newPassword: String) async throws {
        try await sendVoid(
            path: "/me/password",
            method: .post,
            body: ChangeMePasswordBody(currentPassword: currentPassword, newPassword: newPassword)
        )
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

    func trainerTrainees() async throws -> [TraineeListItem] {
        try await sendArray("/trainer/trainees")
    }

    func trainerTrainee(id: String) async throws -> TraineeListItem {
        try await send(path: "/trainer/trainees/\(id)", method: .get)
    }

    private var encodedTZ: String {
        TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "UTC"
    }

    func trainerMeals(traineeId: String, on date: Date) async throws -> [Meal] {
        try await sendArray("/trainer/trainees/\(traineeId)/meals?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)")
    }

    func trainerMacros(traineeId: String, on date: Date) async throws -> MacroEstimate {
        try await send(path: "/trainer/trainees/\(traineeId)/macros?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)", method: .get)
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

    func submitAssessment(_ body: AssessmentBody) async throws {
        try await sendVoid(path: "/trainee/assessment", method: .post, body: body)
    }

    func submitTrainerAssessment(_ body: TrainerAssessmentBody) async throws {
        try await sendVoid(path: "/trainer/assessment", method: .post, body: body)
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

    func traineeMeals(on date: Date) async throws -> [Meal] {
        try await sendArray("/trainee/meals?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)")
    }

    /// Meals between two dates.
    func traineeMeals(from: Date, to: Date) async throws -> [Meal] {
        try await sendArray("/trainee/meals?from=\(APIConfig.dateQuery(from))&to=\(APIConfig.dateQuery(to))&tz=\(encodedTZ)")
    }

    func traineeMealSummary(period: String) async throws -> MealSummaryResponse {
        try await send(path: "/trainee/meals/summary?period=\(period)&tz=\(encodedTZ)", method: .get)
    }

    func createMeal(_ body: MealBody) async throws -> Meal? {
        try await sendOptional(path: "/trainee/meals", method: .post, body: body)
    }

    /// Multipart "file" (JPEG/PNG up to 5 MB) → `{photoUrl}`.
    func uploadMealPhoto(fileData: Data, filename: String = "meal.jpg", mimeType: String = "image/jpeg") async throws -> MealPhotoUploadResponse {
        try await sendMultipart(
            path: "/trainee/meals/photo",
            fields: [.file(name: "file", filename: filename, mimeType: mimeType, data: fileData)]
        )
    }

    /// 1–5 small JPEGs under the multipart field `files`.
    /// `hint` is an optional one-line note from the person (trimmed, at most 200 characters, omitted when empty).
    func analyzeMealPhotos(jpegs: [Data], hint: String? = nil) async throws -> MealPhotosAnalysis {
        var fields = jpegs.enumerated().map { index, data -> MultipartFormField in
            .file(name: "files", filename: "meal\(index + 1).jpg", mimeType: "image/jpeg", data: data)
        }
        let note = String((hint ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if !note.isEmpty { fields.append(.text(name: "hint", value: note)) }
        return try await sendMultipart(path: "/trainee/meals/analyze", fields: fields)
    }

    /// Returns the same shape as the photo analysis (`isFood`, `message`, `mealTag`, `items`).
    func refineMeal(_ body: RefineMealBody) async throws -> MealPhotosAnalysis {
        try await send(path: "/trainee/meals/refine", method: .post, body: body)
    }

    /// On-device OCR text of a nutrition label (10–3000 characters) → per-100 g values.
    func parseNutritionLabel(ocrText: String, productName: String? = nil) async throws -> BarcodeLookupResponse {
        let text = String(ocrText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3000))
        let name = productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await send(
            path: "/trainee/meals/parse-label", method: .post,
            body: ParseLabelBody(ocrText: text, productName: (name?.isEmpty == false) ? name : nil)
        )
    }

    func frequentMeals(limit: Int = 8) async throws -> [FrequentMeal] {
        let response: FrequentMealsResponse = try await send(path: "/trainee/meals/frequent?limit=\(limit)", method: .get)
        return response.items ?? []
    }

    func lookupBarcode(_ code: String) async throws -> BarcodeLookupResponse {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        return try await send(path: "/trainee/meals/barcode/\(encoded)", method: .get)
    }

    func analyzeMealPhoto(photoUrl: String) async throws -> MealAnalyzeResponse? {
        try await sendOptional(path: "/trainee/meals/analyze", method: .post, body: MealAnalyzeBody(photoUrl: photoUrl))
    }

    func updateMeal(id: String, body: UpdateMealBody) async throws -> Meal? {
        try await sendOptional(path: "/trainee/meals/\(id)", method: .patch, body: body)
    }

    /// PATCH /me/trainee (daily calorie target).
    func updateDailyCalorieTarget(_ value: Int) async throws -> TraineeProfile? {
        try await sendOptional(path: "/me/trainee", method: .patch, body: UpdateTraineeGoalBody(dailyCalorieTarget: value))
    }

    func deleteMeal(id: String) async throws {
        try await sendVoid(path: "/trainee/meals/\(id)", method: .delete, body: EmptyBody())
    }

    func traineeMacros(on date: Date) async throws -> MacroEstimate {
        try await send(path: "/trainee/macros?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)", method: .get)
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

    private enum MultipartFormField {
        case text(name: String, value: String)
        case file(name: String, filename: String, mimeType: String, data: Data)
    }

    private func sendMultipart<T: Decodable>(
        path: String,
        fields: [MultipartFormField],
        allowRetry: Bool = true
    ) async throws -> T {
        try await AuthTokenRefresher.shared.refreshIfExpiring()
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard let token = TokenStore.accessToken() else { throw AppError.unauthorized }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = buildMultipartBody(fields: fields, boundary: boundary)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.api("Invalid response from server.")
        }
        if http.statusCode == 401, allowRetry {
            try await AuthTokenRefresher.shared.refresh()
            return try await sendMultipart(path: path, fields: fields, allowRetry: false)
        }
        if !(200...299).contains(http.statusCode) {
            if http.statusCode == 401 {
                TokenStore.clear()
                throw AppError.unauthorized
            }
            if http.statusCode == 404 {
                throw AppError.notFound(Self.detail(from: data) ?? "Not found.")
            }
            throw AppError.api(Self.detail(from: data) ?? "Request failed (\(http.statusCode)).")
        }
        return try decode(T.self, from: data)
    }

    private func buildMultipartBody(fields: [MultipartFormField], boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        for field in fields {
            body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
            switch field {
            case let .text(name, value):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)".data(using: .utf8)!)
                body.append("\(value)\(crlf)".data(using: .utf8)!)
            case let .file(name, filename, mimeType, data):
                body.append(
                    "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!
                )
                body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
                body.append(data)
                body.append(crlf.data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
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
        if authorized {
            try await AuthTokenRefresher.shared.refreshIfExpiring()
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
            try await AuthTokenRefresher.shared.refresh()
            return try await raw(path: path, method: method, body: body, authorized: authorized, allowRetry: false)
        }

        if (200...299).contains(http.statusCode) {
            return data
        }

        if http.statusCode == 401 {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        if failFast, http.statusCode >= 500 { throw LaunchServerError(status: http.statusCode) }
        let detail = Self.detail(from: data)
        let code = Self.code(from: data)
        if http.statusCode == 402 || code == "AI_REQUIRED" || code == "AI_QUOTA_EXCEEDED" {
            throw AppError.aiRequired(detail ?? "AI Coach Pro is required.")
        }
        if http.statusCode == 501 || http.statusCode == 503 || code == "AI_CAPABILITY_UNAVAILABLE" {
            throw AppError.aiUnavailable(detail ?? "This AI feature is coming soon.")
        }
        if code == "AI_PROVIDER_NOT_CONFIGURED" {
            throw AppError.aiUnavailable(detail ?? "AI is not configured yet. Coming soon.")
        }
        if http.statusCode == 409 || code == "CONFLICT" || code == "HAS_TRAINER" {
            throw AppError.conflict(
                detail
                    ?? (code == "HAS_TRAINER"
                        ? "You already have a trainer. Use their assigned plan."
                        : "This Apple subscription is already linked to another TacTech account. Sign in with that account or contact support.")
            )
        }
        if http.statusCode == 502 || code == "PROVIDER_ERROR" {
            throw AppError.providerError(detail ?? "Payment provider error — try again")
        }
        if http.statusCode == 400 || code == "VALIDATION" || code == "VALIDATION_ERROR" {
            throw AppError.validation(detail ?? "Invalid request.")
        }
        if http.statusCode == 403 {
            if code == "PLAN_LOCKED" {
                throw AppError.forbidden(
                    detail ?? "This plan was assigned by your trainer and can’t be edited."
                )
            }
            throw AppError.forbidden(detail ?? "Not allowed.")
        }
        if http.statusCode == 404 {
            throw AppError.notFound(detail ?? "Not found.")
        }
        throw AppError.api(detail ?? "Request failed (\(http.statusCode)).")
    }

    private func makeRequest(path: String, method: HTTPMethod, authorized: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        if method == .post || method == .put || method == .patch || method == .delete {
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

    private static func code(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["code"] as? String
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
        clearExpiry()
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
    private static let sharedTactechDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Date.tactech(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(value)")
        }
        return decoder
    }()

    static var tactech: JSONDecoder { sharedTactechDecoder }
}

extension Date {
    private static let tactechDateLock = NSLock()

    private static let tactechISOFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let tactechISOStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let tactechFallbackFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd"
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    static func tactech(from value: String) -> Date? {
        tactechDateLock.lock()
        defer { tactechDateLock.unlock() }
        if let date = tactechISOFractional.date(from: value) { return date }
        if let date = tactechISOStandard.date(from: value) { return date }
        for formatter in tactechFallbackFormatters {
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

    var isForbidden: Bool {
        if case .forbidden = self { return true }
        return false
    }
}
