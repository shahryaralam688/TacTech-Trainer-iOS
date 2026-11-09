import Foundation

struct FitnessAssessment: Codable, Hashable {
    // MARK: About you
    var goal: String = ""
    var gender: String = ""
    var age: Int = 18

    // Height
    var heightCm: Double = 170
    var heightUnit: String = "cm"       // "cm" or "ft"

    // Weight
    var weightKg: Double = 70
    var weightUnit: String = "kg"       // "kg" or "lbs"

    // Target weight
    var hasTargetWeight: Bool?
    var targetWeightKg: Double = 70

    // MARK: Your fitness
    /// Friendly experience bucket: Beginner / Intermediate / Advanced / Not Sure.
    var experienceLevel: String = ""
    /// Derived flag kept for existing business logic / API.
    var hasExperience: Bool?
    /// Derived 1…5 level kept for existing business logic / API.
    var fitnessLevel: Int = 3

    var activityLevel: String = ""      // Mostly Sitting … Extremely Active
    var workoutLocation: String = ""    // Gym / Home / Outdoors / Mix
    var equipment: [String] = []
    var daysPerWeek: Int = 3
    var workoutDuration: String = ""    // e.g. "30 Minutes"
    var exercisePreferences: [String] = []

    // MARK: Health
    var limitations: [String] = []
    var diet: String = ""

    /// Yes / Sometimes / No.
    var supplementFrequency: String = ""
    var takesSupplements: Bool?
    var supplements: [String] = []

    var sleepHours: String = ""         // e.g. "7–8 Hours"
    var waterIntake: String = ""        // e.g. "2–3 Litres"

    // MARK: Focus & profile
    var improvementAreas: [String] = []

    var frontPhotoCaptured: Bool = false
    var sidePhotoCaptured: Bool = false
    var backPhotoCaptured: Bool = false

    // MARK: Preserved fields (set via defaults / review sheet, kept for API + logic)
    var calorieGoal: Int = 1550
    var calorieUnit: String = "kcal"
    /// Legacy sleep descriptor — kept for API compatibility.
    var sleepQuality: String = ""
    var bodyScanCaptured: Bool = false
    var voiceCaptured: Bool = false
    var concerns: String = ""

    init() {}

    /// Body Mass Index computed from height + weight. Never entered by the user.
    var bmi: Double? {
        let meters = heightCm / 100
        guard meters > 0 else { return nil }
        return weightKg / (meters * meters)
    }

    /// Friendly, non-medical BMI band label.
    var bmiCategory: String? {
        guard let bmi else { return nil }
        switch bmi {
        case ..<18.5: return "Below healthy range"
        case 18.5..<25: return "Healthy range"
        case 25..<30: return "Above healthy range"
        default: return "Well above healthy range"
        }
    }

    // MARK: - Backward-compatible decoding
    // New fields fall back to defaults so older saved payloads still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys, _ d: String = "") -> String { (try? c.decode(String.self, forKey: k)) ?? d }
        func i(_ k: CodingKeys, _ d: Int) -> Int { (try? c.decode(Int.self, forKey: k)) ?? d }
        func dbl(_ k: CodingKeys, _ d: Double) -> Double { (try? c.decode(Double.self, forKey: k)) ?? d }
        func b(_ k: CodingKeys) -> Bool? { try? c.decodeIfPresent(Bool.self, forKey: k) ?? nil }
        func bD(_ k: CodingKeys, _ d: Bool) -> Bool { (try? c.decode(Bool.self, forKey: k)) ?? d }
        func arr(_ k: CodingKeys) -> [String] { (try? c.decode([String].self, forKey: k)) ?? [] }

        goal = s(.goal); gender = s(.gender); age = i(.age, 18)
        heightCm = dbl(.heightCm, 170); heightUnit = s(.heightUnit, "cm")
        weightKg = dbl(.weightKg, 70); weightUnit = s(.weightUnit, "kg")
        hasTargetWeight = b(.hasTargetWeight); targetWeightKg = dbl(.targetWeightKg, 70)
        experienceLevel = s(.experienceLevel)
        hasExperience = b(.hasExperience); fitnessLevel = i(.fitnessLevel, 3)
        activityLevel = s(.activityLevel); workoutLocation = s(.workoutLocation)
        equipment = arr(.equipment); daysPerWeek = i(.daysPerWeek, 3)
        workoutDuration = s(.workoutDuration); exercisePreferences = arr(.exercisePreferences)
        limitations = arr(.limitations); diet = s(.diet)
        supplementFrequency = s(.supplementFrequency)
        takesSupplements = b(.takesSupplements); supplements = arr(.supplements)
        sleepHours = s(.sleepHours); waterIntake = s(.waterIntake)
        improvementAreas = arr(.improvementAreas)
        frontPhotoCaptured = bD(.frontPhotoCaptured, false)
        sidePhotoCaptured = bD(.sidePhotoCaptured, false)
        backPhotoCaptured = bD(.backPhotoCaptured, false)
        calorieGoal = i(.calorieGoal, 1550); calorieUnit = s(.calorieUnit, "kcal")
        sleepQuality = s(.sleepQuality)
        bodyScanCaptured = bD(.bodyScanCaptured, false)
        voiceCaptured = bD(.voiceCaptured, false)
        concerns = s(.concerns)
    }
}

enum AssessmentCatalog {
    static let goals = [
        "Lose Weight",
        "Build Muscle",
        "Get Stronger",
        "Improve Fitness",
        "Stay Fit"
    ]

    static let experienceLevels = ["Beginner", "Intermediate", "Advanced", "Not Sure"]

    static let activityLevels: [(title: String, detail: String)] = [
        ("Mostly Sitting", "Little movement during the day"),
        ("Lightly Active", "Some walking or light tasks"),
        ("Moderately Active", "On your feet fairly often"),
        ("Very Active", "Lots of movement most days"),
        ("Extremely Active", "Active job or hard training")
    ]

    static let workoutLocations: [(title: String, detail: String)] = [
        ("Gym", "Full facility access"),
        ("Home", "Living room or home setup"),
        ("Outdoors", "Parks, trails, open air"),
        ("Mix of Places", "Wherever I can")
    ]

    static let equipment = [
        "Full Gym Equipment", "Dumbbells", "Barbell", "Resistance Bands",
        "Kettlebells", "Exercise Machines", "Bodyweight Only", "Other"
    ]

    static let workoutDurations = [
        "20 Minutes", "30 Minutes", "45 Minutes", "60 Minutes", "90+ Minutes"
    ]

    static let exercises = [
        "Weight Training", "Cardio", "Bodyweight Exercises", "HIIT", "Running",
        "Cycling", "Swimming", "Yoga", "Pilates", "Functional Training", "No Preference"
    ]

    static let limitations = [
        "No", "Back Pain", "Knee Pain", "Shoulder Pain", "Neck Pain",
        "Wrist Pain", "Hip Pain", "Ankle Pain", "Other"
    ]

    static let commonLimitations = ["No", "Back Pain", "Knee Pain"]

    static let diets = [
        "No Specific Diet", "Vegetarian", "Vegan", "Pescatarian",
        "Halal", "Keto", "Mediterranean", "Other"
    ]

    static let supplementFrequencies = ["Yes", "Sometimes", "No"]

    static let commonSupplements = [
        "Protein Powder", "Creatine", "Multivitamins", "Omega-3", "Pre-Workout", "Electrolytes"
    ]

    static let allSupplements = commonSupplements + [
        "BCAAs", "Vitamin D", "Caffeine", "Magnesium", "Iron",
        "Beta-Alanine", "Glutamine", "Fiber", "Calcium", "Other"
    ]

    static let sleepOptions: [(title: String, detail: String)] = [
        ("Less Than 5 Hours", "Running low"),
        ("5–6 Hours", "A bit short"),
        ("6–7 Hours", "Getting there"),
        ("7–8 Hours", "Solid rest"),
        ("8–9 Hours", "Well rested"),
        ("More Than 9 Hours", "Plenty of sleep")
    ]

    static let waterOptions: [(title: String, detail: String)] = [
        ("Less Than 1 Litre", "Could drink more"),
        ("1–2 Litres", "Doing okay"),
        ("2–3 Litres", "Well hydrated"),
        ("More Than 3 Litres", "Great hydration"),
        ("Not Sure", "No idea, really")
    ]

    static let improvementAreas = [
        "Lose Belly Fat", "Reduce Body Fat", "Build Muscle", "Build Upper Body Strength",
        "Build Lower Body Strength", "Improve Core Strength", "Improve Stamina",
        "Improve Flexibility", "Improve Posture", "Improve Overall Fitness"
    ]
}
