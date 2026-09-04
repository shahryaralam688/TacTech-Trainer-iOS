import SwiftUI

// MARK: - Domain catalogs (Plans / Trainees / Foods)

extension TTSearchCatalog {
    static func workoutPlans(
        plans: [WorkoutPlan],
        trainerId: String
    ) -> TTSearchCatalog {
        let tints: [Color] = [
            TTColor.actionOrange,
            TTColor.info,
            TTColor.brand,
            TTColor.success,
            TTColor.energy
        ]

        let items: [TTSearchItem] = plans.enumerated().map { index, plan in
            TTSearchItem(
                id: plan.id,
                title: plan.title,
                subtitle: plan.focus,
                categoryId: plan.focus.lowercased(),
                categoryName: plan.focus,
                meta: "\(plan.durationMinutes) min",
                tags: [plan.level, plan.focus] + plan.scheduledDays.map(\.title),
                icon: .barbellDiagonal,
                tint: tints[index % tints.count]
            )
        }

        let focusGroups = Dictionary(grouping: plans, by: \.focus)
        let categories: [TTSearchCategory] = focusGroups.keys.sorted().enumerated().map { index, focus in
            TTSearchCategory(
                id: focus.lowercased(),
                name: focus,
                count: focusGroups[focus]?.count ?? 0,
                icon: .folder,
                tint: tints[index % tints.count]
            )
        }

        let popular = Array(plans.sorted { $0.allExercises.count > $1.allExercises.count }.prefix(6)).enumerated().map { index, plan in
            TTSearchItem(
                id: plan.id,
                title: plan.title,
                subtitle: plan.level,
                categoryId: plan.focus.lowercased(),
                categoryName: plan.focus,
                meta: "\(plan.daysPerWeek)×/wk",
                tags: [plan.level, plan.focus],
                icon: .fire1,
                tint: tints[index % tints.count]
            )
        }

        let best = Array(plans.sorted { $0.durationMinutes > $1.durationMinutes }.prefix(5)).enumerated().map { index, plan in
            TTSearchItem(
                id: plan.id,
                title: plan.title,
                subtitle: "\(plan.allExercises.count) moves",
                categoryName: plan.focus,
                meta: plan.level,
                tags: [plan.focus],
                icon: .trophy1,
                tint: tints[index % tints.count]
            )
        }

        let recommend = Array(plans.filter { $0.level.lowercased().contains("begin") || $0.level.lowercased().contains("inter") }.prefix(5))
        let recommendItems = (recommend.isEmpty ? Array(plans.prefix(3)) : recommend).enumerated().map { index, plan in
            TTSearchItem(
                id: plan.id,
                title: plan.title,
                subtitle: plan.focus,
                categoryName: plan.focus,
                meta: "\(plan.durationMinutes) min",
                tags: [plan.level],
                icon: .starFull,
                tint: tints[index % tints.count]
            )
        }

        let offer: TTSearchOffer? = plans.isEmpty
            ? TTSearchOffer(
                id: "create-plan",
                title: "Build your first plan",
                subtitle: "Create a weekly program athletes can follow.",
                cta: "Create",
                icon: .plus
            )
            : TTSearchOffer(
                id: "featured-plan",
                title: plans[0].title,
                subtitle: plans[0].focus,
                cta: "Open",
                icon: .gift
            )

        return TTSearchCatalog(
            scopeId: "plans.\(trainerId)",
            items: items,
            categories: categories,
            suggestedItems: Array(items.prefix(5)),
            popularItems: popular.isEmpty ? Array(items.prefix(5)) : popular,
            offer: offer,
            bestSell: best,
            recommendations: recommendItems,
            copy: .plans
        )
    }

    static func trainees(
        trainees: [TraineeProfile],
        names: [String: String],
        plansByTrainee: [String: String],
        activeIds: Set<String>,
        trainerId: String,
        inviteCode: String?
    ) -> TTSearchCatalog {
        let tints: [Color] = [
            TTColor.actionOrange,
            TTColor.info,
            TTColor.brand,
            TTColor.success,
            TTColor.energy
        ]

        let items: [TTSearchItem] = trainees.enumerated().map { index, trainee in
            let name = names[trainee.id] ?? "Athlete"
            return TTSearchItem(
                id: trainee.id,
                title: name,
                subtitle: plansByTrainee[trainee.id] ?? trainee.goal,
                categoryId: trainee.goal.lowercased(),
                categoryName: trainee.goal,
                meta: activeIds.contains(trainee.id) ? "Active" : "Idle",
                tags: [trainee.goal, name],
                icon: .user,
                tint: tints[index % tints.count]
            )
        }

        let goalGroups = Dictionary(grouping: trainees, by: \.goal)
        let categories: [TTSearchCategory] = goalGroups.keys.sorted().enumerated().map { index, goal in
            TTSearchCategory(
                id: goal.lowercased(),
                name: goal.isEmpty ? "General" : goal,
                count: goalGroups[goal]?.count ?? 0,
                icon: .flag1,
                tint: tints[index % tints.count]
            )
        }

        let active = trainees.filter { activeIds.contains($0.id) }
        let popular = (active.isEmpty ? trainees : active).prefix(6).enumerated().map { index, trainee in
            let name = names[trainee.id] ?? "Athlete"
            return TTSearchItem(
                id: trainee.id,
                title: name,
                subtitle: trainee.goal,
                categoryId: trainee.goal.lowercased(),
                categoryName: trainee.goal,
                meta: "Active",
                tags: [trainee.goal, name],
                icon: .fire1,
                tint: tints[index % tints.count]
            )
        }

        let needsPlan = trainees.filter { plansByTrainee[$0.id] == nil }
        let recommend = (needsPlan.isEmpty ? Array(trainees.prefix(3)) : Array(needsPlan.prefix(5))).enumerated().map { index, trainee in
            let name = names[trainee.id] ?? "Athlete"
            return TTSearchItem(
                id: trainee.id,
                title: name,
                subtitle: "Needs a plan",
                categoryName: trainee.goal,
                tags: [trainee.goal],
                icon: .starFull,
                tint: tints[index % tints.count]
            )
        }

        let offer: TTSearchOffer? = inviteCode.map {
            TTSearchOffer(
                id: "invite",
                title: "Invite code \($0)",
                subtitle: "Share so athletes can join your roster.",
                cta: "Copy",
                icon: .link4
            )
        }

        return TTSearchCatalog(
            scopeId: "trainees.\(trainerId)",
            items: items,
            categories: categories,
            suggestedItems: Array(items.prefix(5)),
            popularItems: Array(popular),
            offer: offer,
            bestSell: Array(popular.prefix(5)),
            recommendations: recommend,
            copy: .trainees
        )
    }

    static func foods(
        catalog: [FoodKnowledge],
        categories: [(id: String, name: String, count: Int, icon: SandowIcon)],
        scopeId: String,
        offerTitle: String? = nil,
        offerSubtitle: String? = nil
    ) -> TTSearchCatalog {
        let tints: [Color] = [
            TTColor.actionOrange,
            TTColor.info,
            TTColor.success,
            TTColor.protein,
            TTColor.calorie
        ]

        let items: [TTSearchItem] = catalog.enumerated().map { index, food in
            TTSearchItem(
                id: food.name,
                title: food.name,
                subtitle: "\(food.per100g.calories) kcal / 100g",
                categoryId: nil,
                categoryName: food.keywords.first,
                meta: "\(Int(food.per100g.protein))g P",
                tags: food.keywords,
                icon: .forkKnife,
                tint: tints[index % tints.count]
            )
        }

        let cats: [TTSearchCategory] = categories.enumerated().map { index, cat in
            TTSearchCategory(
                id: cat.id,
                name: cat.name,
                count: cat.count,
                icon: cat.icon,
                tint: tints[index % tints.count]
            )
        }

        let popular = Array(
            catalog.sorted { $0.per100g.protein > $1.per100g.protein }.prefix(6)
        ).enumerated().map { index, food in
            TTSearchItem(
                id: food.name,
                title: food.name,
                subtitle: "High protein",
                meta: "\(food.per100g.calories) kcal",
                tags: food.keywords,
                icon: .fire1,
                tint: tints[index % tints.count]
            )
        }

        let best = Array(
            catalog.sorted { $0.per100g.calories > $1.per100g.calories }.prefix(5)
        ).enumerated().map { index, food in
            TTSearchItem(
                id: food.name,
                title: food.name,
                subtitle: "Energy pick",
                meta: "\(food.per100g.calories) kcal",
                tags: food.keywords,
                icon: .trophy1,
                tint: tints[index % tints.count]
            )
        }

        let recommend = Array(
            catalog.filter { $0.per100g.protein >= 15 }.prefix(5)
        ).enumerated().map { index, food in
            TTSearchItem(
                id: food.name,
                title: food.name,
                subtitle: "Recommended",
                meta: "\(Int(food.per100g.protein))g P",
                tags: food.keywords,
                icon: .starFull,
                tint: tints[index % tints.count]
            )
        }

        let offer: TTSearchOffer? = {
            guard let title = offerTitle else { return nil }
            return TTSearchOffer(
                id: "food-offer",
                title: title,
                subtitle: offerSubtitle ?? "From your nutrition plan",
                cta: "Add",
                icon: .gift
            )
        }()

        return TTSearchCatalog(
            scopeId: "foods.\(scopeId)",
            items: items,
            categories: cats,
            suggestedItems: Array(items.prefix(5)),
            popularItems: popular,
            offer: offer,
            bestSell: best,
            recommendations: recommend.isEmpty ? Array(items.prefix(3)) : recommend,
            copy: .foods
        )
    }
}
