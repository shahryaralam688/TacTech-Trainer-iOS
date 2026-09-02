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
}
