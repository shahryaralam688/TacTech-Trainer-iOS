import Foundation

struct FitnessAssessment: Codable, Hashable {
    var goal: String = ""
    var gender: String = ""
    var weightKg: Double = 128
    var weightUnit: String = "kg"
    var age: Int = 18
    var hasExperience: Bool?
    var fitnessLevel: Int = 3
    var limitations: [String] = []
    var diet: String = ""
    var daysPerWeek: Int = 5
    var exercisePreferences: [String] = []
    var takesSupplements: Bool?
    var supplements: [String] = []
    var calorieGoal: Int = 1550
    var calorieUnit: String = "kcal"
    var sleepQuality: String = ""
    var bodyScanCaptured: Bool = false
    var voiceCaptured: Bool = false
    var concerns: String = ""
}

enum AssessmentCatalog {
    static let goals = [
        "I wanna lose weight",
        "I wanna try AI Coach",
        "I wanna get bulks",
        "I wanna gain endurance",
        "Just trying out the app! 👍"
    ]

    static let limitations = [
        "Arthritis", "Back Pain", "Asthma", "Obesity", "Knee Pain", "Muscle Pain", "None"
    ]

    static let commonLimitations = ["Knee Pain", "Muscle Pain"]

    static let diets = [
        "Plant Based", "Carbo Diet", "Specialized", "Traditional"
    ]

    static let exercises = [
        "Jogging", "Walking", "Hiking", "Skating", "Biking", "Weightlift", "Cardio", "Yoga", "Other"
    ]

    static let commonSupplements = [
        "Whey", "BCAAs", "Vitamin D", "Caffeine", "Omega-3", "Creatine", "Magnesium", "Iron"
    ]

    static let allSupplements = commonSupplements + [
        "Beta-Alanine", "Turmeric", "Curcumin", "Glucosamine", "Calcium",
        "Vitamin A", "Vitamin B", "Vitamin C", "Fiber", "Multivitamin",
        "Glutamine", "Protein"
    ]

    static let sleepOptions: [(title: String, detail: String)] = [
        ("Excellent", ">8 hours"),
        ("Great", "7-8 hours"),
        ("Normal", "6-7 hours"),
        ("Bad", "3-4 hours"),
        ("Insomniac", "<2 hours")
    ]
}
