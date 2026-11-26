import Foundation

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

extension APIClient {

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

    func submitAssessment(_ body: AssessmentBody) async throws {
        try await sendVoid(path: "/trainee/assessment", method: .post, body: body)
    }

    func submitTrainerAssessment(_ body: TrainerAssessmentBody) async throws {
        try await sendVoid(path: "/trainer/assessment", method: .post, body: body)
    }
}
