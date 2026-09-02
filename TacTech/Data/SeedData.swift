import Foundation

enum SeedData {
    static let foodCatalog: [FoodKnowledge] = [
        FoodKnowledge(name: "Grilled Chicken Bowl", keywords: ["chicken", "poultry", "grilled"], per100g: .init(calories: 165, protein: 31, carbs: 0, fat: 3.6)),
        FoodKnowledge(name: "Salmon", keywords: ["salmon", "fish"], per100g: .init(calories: 208, protein: 20, carbs: 0, fat: 13)),
        FoodKnowledge(name: "Brown Rice", keywords: ["rice", "grain"], per100g: .init(calories: 123, protein: 2.7, carbs: 26, fat: 1)),
        FoodKnowledge(name: "Avocado", keywords: ["avocado"], per100g: .init(calories: 160, protein: 2, carbs: 9, fat: 15)),
        FoodKnowledge(name: "Greek Yogurt", keywords: ["yogurt", "yoghurt", "dairy"], per100g: .init(calories: 97, protein: 9, carbs: 3.6, fat: 5)),
        FoodKnowledge(name: "Banana", keywords: ["banana", "fruit"], per100g: .init(calories: 89, protein: 1.1, carbs: 23, fat: 0.3)),
        FoodKnowledge(name: "Oatmeal", keywords: ["oat", "oatmeal", "porridge"], per100g: .init(calories: 68, protein: 2.4, carbs: 12, fat: 1.4)),
        FoodKnowledge(name: "Egg", keywords: ["egg"], per100g: .init(calories: 155, protein: 13, carbs: 1.1, fat: 11)),
        FoodKnowledge(name: "Broccoli", keywords: ["broccoli", "vegetable", "veggie"], per100g: .init(calories: 34, protein: 2.8, carbs: 7, fat: 0.4)),
        FoodKnowledge(name: "Protein Shake", keywords: ["shake", "protein", "whey"], per100g: .init(calories: 80, protein: 15, carbs: 4, fat: 1.5)),
        FoodKnowledge(name: "Pizza", keywords: ["pizza"], per100g: .init(calories: 266, protein: 11, carbs: 33, fat: 10)),
        FoodKnowledge(name: "Salad", keywords: ["salad", "greens", "lettuce"], per100g: .init(calories: 45, protein: 2, carbs: 6, fat: 2)),
        FoodKnowledge(name: "Burger", keywords: ["burger", "hamburger"], per100g: .init(calories: 295, protein: 17, carbs: 24, fat: 14)),
        FoodKnowledge(name: "Pasta", keywords: ["pasta", "spaghetti", "noodle"], per100g: .init(calories: 131, protein: 5, carbs: 25, fat: 1.1)),
        FoodKnowledge(name: "Apple", keywords: ["apple"], per100g: .init(calories: 52, protein: 0.3, carbs: 14, fat: 0.2))
    ]

    static func make() -> Snapshot {
        let now = Date()

        let trainerUser = User(id: "user-trainer-maya", name: "Maya Cole", email: "trainer@tactech.app", password: "trainer123", role: .trainer, createdAt: now.addingTimeInterval(-86400 * 120))
        let jordan = User(id: "user-jordan", name: "Jordan Hale", email: "trainee@tactech.app", password: "trainee123", role: .trainee, createdAt: now.addingTimeInterval(-86400 * 40))
        let priya = User(id: "user-priya", name: "Priya Shah", email: "priya@tactech.app", password: "trainee123", role: .trainee, createdAt: now.addingTimeInterval(-86400 * 28))
        let marcus = User(id: "user-marcus", name: "Marcus Webb", email: "marcus@tactech.app", password: "trainee123", role: .trainee, createdAt: now.addingTimeInterval(-86400 * 18))
        let elena = User(id: "user-elena", name: "Elena Voss", email: "elena@tactech.app", password: "trainee123", role: .trainee, createdAt: now.addingTimeInterval(-86400 * 10))

        let trainer = TrainerProfile(
            id: "trainer-maya",
            userId: trainerUser.id,
            inviteCode: "TACT-MAYA",
            specialty: "Strength, hypertrophy & movement quality",
            yearsExperience: 8,
            bio: "Former collegiate athlete. I coach progressive strength with clean technique and sustainable nutrition."
        )

        let trainees = [
            TraineeProfile(id: "trainee-jordan", userId: jordan.id, trainerId: trainer.id, goal: "Build lean muscle", heightCm: 178, weightKg: 76, dailyCalorieTarget: 2400),
            TraineeProfile(id: "trainee-priya", userId: priya.id, trainerId: trainer.id, goal: "Improve endurance", heightCm: 164, weightKg: 61, dailyCalorieTarget: 1900),
            TraineeProfile(id: "trainee-marcus", userId: marcus.id, trainerId: trainer.id, goal: "Lose fat, keep strength", heightCm: 183, weightKg: 92, dailyCalorieTarget: 2200),
            TraineeProfile(id: "trainee-elena", userId: elena.id, trainerId: trainer.id, goal: "Rehab & mobility", heightCm: 170, weightKg: 64, dailyCalorieTarget: 2000)
        ]

        let exercises: [Exercise] = [
            Exercise(id: "ex-squat", name: "Barbell Squat", muscleGroup: "Legs", equipment: "Barbell", difficulty: "Intermediate", cues: ["Brace your core", "Knees track over toes", "Sit between the hips", "Stand tall at the top"], icon: "figure.strengthtraining.traditional"),
            Exercise(id: "ex-rdl", name: "Romanian Deadlift", muscleGroup: "Posterior", equipment: "Barbell", difficulty: "Intermediate", cues: ["Soft knees", "Hinge from the hips", "Keep the bar close", "Flat back"], icon: "figure.strengthtraining.functional"),
            Exercise(id: "ex-pushup", name: "Push Up", muscleGroup: "Chest", equipment: "Bodyweight", difficulty: "Beginner", cues: ["Hands under shoulders", "Ribs down", "Full lockout", "Control the descent"], icon: "figure.core.training"),
            Exercise(id: "ex-ohp", name: "Overhead Press", muscleGroup: "Shoulders", equipment: "Barbell", difficulty: "Intermediate", cues: ["Glutes tight", "Press up and slightly back", "Don’t flare ribs"], icon: "figure.boxing"),
            Exercise(id: "ex-row", name: "Bent Over Row", muscleGroup: "Back", equipment: "Dumbbell", difficulty: "Intermediate", cues: ["Hinge and hold", "Pull to the hip", "Squeeze the shoulder blades"], icon: "figure.indoor.rowing"),
            Exercise(id: "ex-lunge", name: "Walking Lunge", muscleGroup: "Legs", equipment: "Dumbbell", difficulty: "Beginner", cues: ["Long stride", "Front knee stacked", "Stay tall"], icon: "figure.walk"),
            Exercise(id: "ex-plank", name: "Plank", muscleGroup: "Core", equipment: "Bodyweight", difficulty: "Beginner", cues: ["Squeeze glutes", "Neutral neck", "Don’t sag the hips"], icon: "figure.yoga"),
            Exercise(id: "ex-hiphinge", name: "Hip Hinge Drill", muscleGroup: "Posterior", equipment: "Bodyweight", difficulty: "Beginner", cues: ["Push hips back", "Soft knees", "Long spine"], icon: "figure.flexibility"),
            Exercise(id: "ex-hiit", name: "Bike Sprint", muscleGroup: "Conditioning", equipment: "Bike", difficulty: "Advanced", cues: ["Smooth cadence", "Upright torso", "Recover with control"], icon: "bicycle")
        ]

        func we(_ exerciseId: String, sets: Int, reps: Int, rest: Int, kg: Double?) -> WorkoutExercise {
            WorkoutExercise(id: UUID().uuidString, exerciseId: exerciseId, sets: sets, reps: reps, restSeconds: rest, recommendedWeightKg: kg)
        }

        let push = WorkoutPlan(
            id: "plan-push",
            trainerId: trainer.id,
            title: "Push Hypertrophy",
            focus: "Chest · Shoulders · Triceps",
            durationMinutes: 45,
            level: "Intermediate",
            daysPerWeek: 3,
            exercises: [
                we("ex-pushup", sets: 4, reps: 12, rest: 60, kg: nil),
                we("ex-ohp", sets: 4, reps: 8, rest: 90, kg: 30),
                we("ex-plank", sets: 3, reps: 40, rest: 45, kg: nil)
            ]
        )
        let lower = WorkoutPlan(
            id: "plan-lower",
            trainerId: trainer.id,
            title: "Lower Body Strength",
            focus: "Quads · Glutes · Hamstrings",
            durationMinutes: 55,
            level: "Intermediate",
            daysPerWeek: 3,
            exercises: [
                we("ex-squat", sets: 5, reps: 5, rest: 150, kg: 70),
                we("ex-rdl", sets: 4, reps: 8, rest: 120, kg: 60),
                we("ex-lunge", sets: 3, reps: 10, rest: 75, kg: 16)
            ]
        )
        let engine = WorkoutPlan(
            id: "plan-engine",
            trainerId: trainer.id,
            title: "Engine Builder",
            focus: "Conditioning · Work capacity",
            durationMinutes: 35,
            level: "Advanced",
            daysPerWeek: 2,
            exercises: [
                we("ex-hiit", sets: 8, reps: 30, rest: 45, kg: nil),
                we("ex-pushup", sets: 3, reps: 15, rest: 40, kg: nil),
                we("ex-plank", sets: 3, reps: 45, rest: 30, kg: nil)
            ]
        )
        let restore = WorkoutPlan(
            id: "plan-restore",
            trainerId: trainer.id,
            title: "Restore & Move",
            focus: "Mobility · Control",
            durationMinutes: 30,
            level: "Beginner",
            daysPerWeek: 4,
            exercises: [
                we("ex-hiphinge", sets: 3, reps: 10, rest: 40, kg: nil),
                we("ex-lunge", sets: 3, reps: 8, rest: 45, kg: nil),
                we("ex-plank", sets: 3, reps: 30, rest: 30, kg: nil)
            ]
        )

        let assignments = [
            PlanAssignment(id: "as-jordan", planId: lower.id, traineeId: "trainee-jordan", assignedAt: now.addingTimeInterval(-86400 * 12)),
            PlanAssignment(id: "as-priya", planId: engine.id, traineeId: "trainee-priya", assignedAt: now.addingTimeInterval(-86400 * 8)),
            PlanAssignment(id: "as-marcus", planId: push.id, traineeId: "trainee-marcus", assignedAt: now.addingTimeInterval(-86400 * 6)),
            PlanAssignment(id: "as-elena", planId: restore.id, traineeId: "trainee-elena", assignedAt: now.addingTimeInterval(-86400 * 4))
        ]

        let logs = [
            WorkoutLog(id: "log-1", traineeId: "trainee-jordan", planId: lower.id, completedAt: now.addingTimeInterval(-86400 * 2), durationMinutes: 52, sets: [
                WorkoutSetLog(id: "s1", exerciseId: "ex-squat", setNumber: 1, reps: 5, weightKg: 70),
                WorkoutSetLog(id: "s2", exerciseId: "ex-squat", setNumber: 2, reps: 5, weightKg: 72.5)
            ]),
            WorkoutLog(id: "log-2", traineeId: "trainee-priya", planId: engine.id, completedAt: now.addingTimeInterval(-86400), durationMinutes: 34, sets: [
                WorkoutSetLog(id: "s3", exerciseId: "ex-hiit", setNumber: 1, reps: 30, weightKg: 0)
            ]),
            WorkoutLog(id: "log-3", traineeId: "trainee-marcus", planId: push.id, completedAt: now.addingTimeInterval(-86400 * 3), durationMinutes: 41, sets: [
                WorkoutSetLog(id: "s4", exerciseId: "ex-ohp", setNumber: 1, reps: 8, weightKg: 32)
            ])
        ]

        let meals = [
            Meal(id: "m1", traineeId: "trainee-jordan", name: "Greek Yogurt + Banana", eatenAt: now.addingTimeInterval(-3600 * 4), portionGrams: 250, macros: .init(calories: 310, protein: 24, carbs: 38, fat: 7), source: "log", isEstimate: false),
            Meal(id: "m2", traineeId: "trainee-jordan", name: "Grilled Chicken Bowl", eatenAt: now.addingTimeInterval(-3600 * 1), portionGrams: 320, macros: .init(calories: 540, protein: 48, carbs: 42, fat: 16), source: "scan", isEstimate: true),
            Meal(id: "m3", traineeId: "trainee-priya", name: "Oatmeal", eatenAt: now.addingTimeInterval(-3600 * 5), portionGrams: 200, macros: .init(calories: 280, protein: 11, carbs: 46, fat: 6), source: "log", isEstimate: false)
        ]

        let feedback = [
            TrainerFeedback(id: "fb1", trainerId: trainer.id, traineeId: "trainee-jordan", message: "Squat depth looked much better this week. Keep the brace before you descend.", createdAt: now.addingTimeInterval(-86400), relatedExerciseId: "ex-squat"),
            TrainerFeedback(id: "fb2", trainerId: trainer.id, traineeId: "trainee-priya", message: "Great engine session. Next time recover at 70% instead of stopping completely.", createdAt: now.addingTimeInterval(-7200), relatedExerciseId: "ex-hiit")
        ]

        let reports = [
            FormReport(id: "fr1", traineeId: "trainee-jordan", exerciseId: "ex-squat", createdAt: now.addingTimeInterval(-5400), score: 82, cues: ["Go a little deeper", "Knees aligned"], repCount: 8),
            FormReport(id: "fr2", traineeId: "trainee-marcus", exerciseId: "ex-pushup", createdAt: now.addingTimeInterval(-86400 * 1), score: 74, cues: ["Keep your back straight", "Slow down"], repCount: 12)
        ]

        return Snapshot(
            session: nil,
            users: [trainerUser, jordan, priya, marcus, elena],
            trainers: [trainer],
            trainees: trainees,
            exercises: exercises,
            plans: [push, lower, engine, restore],
            assignments: assignments,
            workoutLogs: logs,
            meals: meals,
            feedback: feedback,
            formReports: reports
        )
    }
}
