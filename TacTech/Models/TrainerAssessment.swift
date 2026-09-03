import Foundation

struct TrainerAssessment: Codable, Hashable {
    var coachingFocus: String = ""
    var yearsExperience: Int = 3
    var certifications: [String] = []
    var specialty: String = ""
    var clientTypes: [String] = []
    var maxClients: Int = 10
    var sessionStyle: String = ""
    var daysPerWeek: Int = 5
    var trainingModes: [String] = []
    var gender: String = ""
    var bio: String = ""
    var philosophy: String = ""
}

enum TrainerAssessmentCatalog {
    static let coachingFocus: [(title: String, subtitle: String)] = [
        ("Strength", "Power & lifts"),
        ("Fat Loss", "Body recomposition"),
        ("Hypertrophy", "Muscle building"),
        ("Endurance", "Conditioning"),
        ("Rehab", "Return to train"),
        ("General Fitness", "All-round coaching")
    ]

    static let certifications = [
        "CSCS", "NASM", "ACE", "ISSA", "CrossFit L1", "Precision Nutrition", "None", "Other"
    ]

    static let specialties = [
        "Powerlifting", "Bodybuilding", "CrossFit", "Sports Performance",
        "Senior Fitness", "Youth Athletes", "Online Coaching", "General PT"
    ]

    static let clientTypes = [
        "Beginners", "Intermediate", "Advanced Athletes", "Online Clients", "In-person Clients"
    ]

    static let sessionStyles: [(title: String, subtitle: String)] = [
        ("1:1 Coaching", "Personal sessions"),
        ("Small Group", "2–6 athletes"),
        ("Online Plans", "Remote programming"),
        ("Hybrid", "Gym + online")
    ]

    static let trainingModes = [
        "Commercial Gym", "Home Gym", "Outdoor", "Online Only"
    ]

    /// Slider steps 1…5 map to these capacity values.
    static let capacityOptions = [5, 10, 15, 20, 30]

    static func capacityIndex(for maxClients: Int) -> Int {
        if let idx = capacityOptions.firstIndex(of: maxClients) { return idx + 1 }
        let nearest = capacityOptions.enumerated().min {
            abs($0.element - maxClients) < abs($1.element - maxClients)
        }?.offset ?? 1
        return nearest + 1
    }

    static func maxClients(forSliderValue value: Int) -> Int {
        let index = min(max(value, 1), capacityOptions.count) - 1
        return capacityOptions[index]
    }
}
