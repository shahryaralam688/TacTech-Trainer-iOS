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
    var gender: String? = nil
    var location: String? = nil
}

struct TraineeProfile: Identifiable, Codable, Hashable {
    var id: String
    var userId: String
    var trainerId: String?
    var goal: String
    var heightCm: Int
    var weightKg: Double
    var dailyCalorieTarget: Int
    var gender: String? = nil
    var location: String? = nil
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

enum Weekday: String, Codable, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
    var short: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = Weekday(rawValue: raw) ?? .monday
    }

    static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        switch calendar.component(.weekday, from: date) {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        default: .saturday
        }
    }
}

struct PrescribedSet: Identifiable, Codable, Hashable {
    var id: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double?
    var rpe: Double?
}

struct WorkoutExercise: Identifiable, Codable, Hashable {
    var id: String
    var exerciseId: String
    var sets: Int
    var reps: Int
    var restSeconds: Int
    var recommendedWeightKg: Double?
    var tempo: String?
    var rpe: Double?
    var notes: String?
    var side: String?
    var prescribedSets: [PrescribedSet]

    init(
        id: String,
        exerciseId: String,
        sets: Int,
        reps: Int,
        restSeconds: Int,
        recommendedWeightKg: Double? = nil,
        tempo: String? = nil,
        rpe: Double? = nil,
        notes: String? = nil,
        side: String? = nil,
        prescribedSets: [PrescribedSet] = []
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.recommendedWeightKg = recommendedWeightKg
        self.tempo = tempo
        self.rpe = rpe
        self.notes = notes
        self.side = side
        self.prescribedSets = prescribedSets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        sets = try c.decode(Int.self, forKey: .sets)
        reps = try c.decode(Int.self, forKey: .reps)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        recommendedWeightKg = try c.decodeIfPresent(Double.self, forKey: .recommendedWeightKg)
        tempo = try c.decodeIfPresent(String.self, forKey: .tempo)
        rpe = try c.decodeIfPresent(Double.self, forKey: .rpe)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        side = try c.decodeIfPresent(String.self, forKey: .side)
        prescribedSets = try c.decodeIfPresent([PrescribedSet].self, forKey: .prescribedSets) ?? []
    }

    var workingSets: [PrescribedSet] {
        if !prescribedSets.isEmpty { return prescribedSets.sorted { $0.setNumber < $1.setNumber } }
        return (1...max(sets, 1)).map {
            PrescribedSet(id: "\(id)-\($0)", setNumber: $0, reps: reps, weightKg: recommendedWeightKg, rpe: rpe)
        }
    }

    var prescriptionLine: String {
        var parts = ["\(sets)×\(reps)"]
        if let kg = recommendedWeightKg { parts.append("\(kg.cleanKg) kg") }
        parts.append("\(restSeconds)s rest")
        if let tempo, !tempo.isEmpty { parts.append("tempo \(tempo)") }
        return parts.joined(separator: " · ")
    }
}

struct PlanDay: Identifiable, Codable, Hashable {
    var id: String
    var weekday: Weekday
    var startTime: String?
    var title: String
    var focus: String
    var durationMinutes: Int
    var location: String?
    var warmup: String?
    var cooldown: String?
    var coachNotes: String?
    var exercises: [WorkoutExercise]

    var timeLabel: String {
        startTime?.clockDisplay ?? "Time TBD"
    }
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
    var notes: String?
    var days: [PlanDay]

    init(
        id: String,
        trainerId: String,
        title: String,
        focus: String,
        durationMinutes: Int,
        level: String,
        daysPerWeek: Int,
        exercises: [WorkoutExercise],
        notes: String? = nil,
        days: [PlanDay] = []
    ) {
        self.id = id
        self.trainerId = trainerId
        self.title = title
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.level = level
        self.daysPerWeek = daysPerWeek
        self.exercises = exercises
        self.notes = notes
        self.days = days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        trainerId = try c.decode(String.self, forKey: .trainerId)
        title = try c.decode(String.self, forKey: .title)
        focus = try c.decode(String.self, forKey: .focus)
        durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        level = try c.decode(String.self, forKey: .level)
        daysPerWeek = try c.decode(Int.self, forKey: .daysPerWeek)
        exercises = try c.decodeIfPresent([WorkoutExercise].self, forKey: .exercises) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        days = try c.decodeIfPresent([PlanDay].self, forKey: .days) ?? []
    }

    var scheduledDays: [PlanDay] {
        days.sorted { $0.weekday.sortIndex < $1.weekday.sortIndex }
    }

    func session(on date: Date) -> PlanDay? {
        let weekday = Weekday.from(date: date)
        return days.first { $0.weekday == weekday }
    }

    func nextSession(from date: Date = .now) -> PlanDay? {
        if let today = session(on: date) { return today }
        let start = Weekday.from(date: date).sortIndex
        return scheduledDays.min { lhs, rhs in
            let left = (lhs.weekday.sortIndex - start + 7) % 7
            let right = (rhs.weekday.sortIndex - start + 7) % 7
            return left < right
        }
    }

    var allExercises: [WorkoutExercise] {
        if !days.isEmpty { return days.flatMap(\.exercises) }
        return exercises
    }

    var scheduleLine: String {
        if scheduledDays.isEmpty { return "\(daysPerWeek)x / week" }
        return scheduledDays.map { "\($0.weekday.short) \($0.timeLabel)" }.joined(separator: " · ")
    }
}

extension Weekday {
    var sortIndex: Int {
        switch self {
        case .monday: 0
        case .tuesday: 1
        case .wednesday: 2
        case .thursday: 3
        case .friday: 4
        case .saturday: 5
        case .sunday: 6
        }
    }
}

extension String {
    var clockDisplay: String {
        let parts = split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return self }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

extension Double {
    var cleanKg: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
    }
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

/// Trainer-saved (or plan-derived) prescription for a catalog exercise.
struct ExerciseTemplate: Identifiable, Codable, Hashable {
    var id: String
    var exerciseId: String
    var trainerId: String
    var name: String
    var sets: Int
    var reps: Int
    var restSeconds: Int
    var weightKg: Double
    var tempo: String
    var rpe: Double
    var howTo: String
    var side: String
    var setRows: [ExerciseTemplateSet]
    var updatedAt: Date

    var summary: String {
        let weight = weightKg.cleanKg
        return "\(sets)×\(reps) · \(weight) kg · \(restSeconds)s rest · RPE \(String(format: "%g", rpe))"
    }

    /// Dedupes equivalent prescriptions across saved templates and past plans.
    var fingerprint: String {
        let setsKey = setRows
            .sorted { $0.setNumber < $1.setNumber }
            .map { "\($0.setNumber):\($0.reps):\($0.weightKg)" }
            .joined(separator: "|")
        return "\(exerciseId)|\(sets)|\(reps)|\(restSeconds)|\(weightKg)|\(tempo)|\(rpe)|\(side)|\(setsKey)"
    }

    static func from(workoutExercise we: WorkoutExercise, trainerId: String, planTitle: String) -> ExerciseTemplate {
        let rows: [ExerciseTemplateSet]
        if we.prescribedSets.isEmpty {
            rows = (1...max(we.sets, 1)).map {
                ExerciseTemplateSet(
                    id: UUID().uuidString,
                    setNumber: $0,
                    reps: we.reps,
                    weightKg: we.recommendedWeightKg ?? 0
                )
            }
        } else {
            rows = we.prescribedSets.map {
                ExerciseTemplateSet(
                    id: $0.id,
                    setNumber: $0.setNumber,
                    reps: $0.reps,
                    weightKg: $0.weightKg ?? we.recommendedWeightKg ?? 0
                )
            }
        }
        return ExerciseTemplate(
            id: UUID().uuidString,
            exerciseId: we.exerciseId,
            trainerId: trainerId,
            name: "From \(planTitle)",
            sets: we.sets,
            reps: we.reps,
            restSeconds: we.restSeconds,
            weightKg: we.recommendedWeightKg ?? rows.last?.weightKg ?? 0,
            tempo: we.tempo ?? "3-1-1-0",
            rpe: we.rpe ?? 7.5,
            howTo: we.notes ?? "",
            side: we.side ?? "Both",
            setRows: rows,
            updatedAt: .now
        )
    }

    static func starter(for exercise: Exercise, trainerId: String) -> ExerciseTemplate {
        let (sets, reps, weight, rpe): (Int, Int, Double, Double) = {
            switch exercise.difficulty.lowercased() {
            case "beginner": return (3, 12, 20, 6.5)
            case "advanced": return (5, 5, 60, 8.5)
            default: return (4, 8, 40, 7.5)
            }
        }()
        let rows = (1...sets).map {
            ExerciseTemplateSet(id: UUID().uuidString, setNumber: $0, reps: reps, weightKg: weight)
        }
        return ExerciseTemplate(
            id: UUID().uuidString,
            exerciseId: exercise.id,
            trainerId: trainerId,
            name: "\(exercise.difficulty) starter",
            sets: sets,
            reps: reps,
            restSeconds: 90,
            weightKg: weight,
            tempo: "3-1-1-0",
            rpe: rpe,
            howTo: exercise.cues.joined(separator: " "),
            side: "Both",
            setRows: rows,
            updatedAt: .now
        )
    }
}

struct ExerciseTemplateSet: Identifiable, Codable, Hashable {
    var id: String
    var setNumber: Int
    var reps: Int
    var weightKg: Double
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
