import Foundation

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case trainer
    case trainee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trainer: "Trainer"
        case .trainee: "Trainee"
        }
    }

    var subtitle: String {
        switch self {
        case .trainer: "Manage clients, assign plans, and review performance."
        case .trainee: "Follow your plan, train with form AI, and track nutrition."
        }
    }

    var icon: String {
        switch self {
        case .trainer: "figure.strengthtraining.traditional"
        case .trainee: "figure.run"
        }
    }
}

struct User: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var email: String
    var password: String
    var role: UserRole
    var createdAt: Date
}

struct TrainerProfile: Identifiable, Codable, Hashable {
    var id: String
    var userId: String
    var inviteCode: String
    var specialty: String
    var yearsExperience: Int
    var bio: String
}

struct TraineeProfile: Identifiable, Codable, Hashable {
    var id: String
    var userId: String
    var trainerId: String?
    var goal: String
    var heightCm: Int
    var weightKg: Double
    var dailyCalorieTarget: Int
}

struct Exercise: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var muscleGroup: String
    var equipment: String
    var difficulty: String
    var cues: [String]
    var icon: String
}

struct WorkoutExercise: Identifiable, Codable, Hashable {
    var id: String
    var exerciseId: String
    var sets: Int
    var reps: Int
    var restSeconds: Int
    var recommendedWeightKg: Double?
}

struct WorkoutPlan: Identifiable, Codable, Hashable {
    var id: String
    var trainerId: String
    var title: String
    var focus: String
    var durationMinutes: Int
    var level: String
    var daysPerWeek: Int
    var exercises: [WorkoutExercise]
}

struct PlanAssignment: Identifiable, Codable, Hashable {
    var id: String
    var planId: String
    var traineeId: String
    var assignedAt: Date
}

struct WorkoutSetLog: Identifiable, Codable, Hashable {
    var id: String
    var exerciseId: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double
}

struct WorkoutLog: Identifiable, Codable, Hashable {
    var id: String
    var traineeId: String
    var planId: String
    var completedAt: Date
    var durationMinutes: Int
    var sets: [WorkoutSetLog]
}

struct MacroEstimate: Codable, Hashable {
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct Meal: Identifiable, Codable, Hashable {
    var id: String
    var traineeId: String
    var name: String
    var eatenAt: Date
    var portionGrams: Double
    var macros: MacroEstimate
    var source: String
    var isEstimate: Bool
}

struct TrainerFeedback: Identifiable, Codable, Hashable {
    var id: String
    var trainerId: String
    var traineeId: String
    var message: String
    var createdAt: Date
    var relatedExerciseId: String?
}

struct FormReport: Identifiable, Codable, Hashable {
    var id: String
    var traineeId: String
    var exerciseId: String
    var createdAt: Date
    var score: Int
    var cues: [String]
    var repCount: Int
}

struct Session: Codable, Hashable {
    var userId: String
    var role: UserRole
}

struct FoodKnowledge: Hashable {
    var name: String
    var keywords: [String]
    var per100g: MacroEstimate
}
