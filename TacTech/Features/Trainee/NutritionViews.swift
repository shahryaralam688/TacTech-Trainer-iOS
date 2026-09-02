import SwiftUI

struct NutritionView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()
    @State private var showManual = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TTScreenHeader(eyebrow: "Fuel the work", title: "Nutrition")
                    TTWeekStrip(selected: $selectedDay)
                    rings
                    HStack(spacing: 12) {
                        NavigationLink {
                            FoodScannerView()
                        } label: {
                            compactAction("Scan food", "camera.fill")
                        }
                        Button {
                            showManual = true
                        } label: {
                            compactAction("Log meal", "plus")
                        }
                    }
                    mealsList
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showManual) {
                ManualMealView(day: selectedDay)
            }
        }
    }

    private var rings: some View {
        let target = Double(store.currentTrainee?.dailyCalorieTarget ?? 2200)
        let macros = store.currentTrainee.map { store.dailyMacros(for: $0.id, on: selectedDay) } ?? MacroEstimate(calories: 0, protein: 0, carbs: 0, fat: 0)
        return HStack(spacing: 16) {
            ZStack {
                TTProgressRing(progress: Double(macros.calories) / max(target, 1), tint: TTColor.calorie, size: 110)
                VStack(spacing: 2) {
                    Text("\(macros.calories)")
                        .font(TTFont.title(20))
                    Text("kcal")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                macroLine("Protein", macros.protein, 140, TTColor.protein)
                macroLine("Carbs", macros.carbs, 220, TTColor.carbs)
                macroLine("Fat", macros.fat, 70, TTColor.fat)
                Text("Values from scans are estimates.")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .ttCard()
    }

    private func macroLine(_ title: String, _ value: Double, _ goal: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(TTFont.caption(12))
                Spacer()
                Text("\(Int(value)) / \(Int(goal))g")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }
            ProgressView(value: min(value / goal, 1))
                .tint(tint)
        }
    }

    private func compactAction(_ title: String, _ icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
                .font(TTFont.heading(14))
        }
        .foregroundStyle(TTColor.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(TTColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous)
                .stroke(TTColor.line, lineWidth: 1)
        )
    }

    private var mealsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Meals")
            if let trainee = store.currentTrainee {
                let items = store.meals(for: trainee.id, on: selectedDay)
                if items.isEmpty {
                    TTEmptyState(icon: "fork.knife", title: "Nothing logged", message: "Scan a meal or add one manually.")
                        .ttCard()
                } else {
                    ForEach(items) { meal in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.name)
                                    .font(TTFont.heading(15))
                                Text("\(meal.isEstimate ? "Estimate · " : "")\(Int(meal.portionGrams)) g · \(meal.source)")
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(TTColor.inkMuted)
                            }
                            Spacer()
                            Text("\(meal.macros.calories)")
                                .font(TTFont.heading(16))
                                .foregroundStyle(TTColor.calorie)
                        }
                        .ttCard()
                    }
                }
            }
        }
    }
}

struct ManualMealView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var name = ""
    @State private var grams = 200.0
    @State private var selectedFood: FoodKnowledge?

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Food name", text: $name)
                        .onChange(of: name) { _, value in
                            selectedFood = store.lookupFood(query: value)
                        }
                    Slider(value: $grams, in: 50...600, step: 10) {
                        Text("Portion")
                    } minimumValueLabel: {
                        Text("50")
                    } maximumValueLabel: {
                        Text("600")
                    }
                    Text("\(Int(grams)) g")
                }
                if let food = selectedFood {
                    Section("Estimate per portion") {
                        Text(food.name)
                        Text("\(scaled(food).calories) kcal")
                        Text("P \(Int(scaled(food).protein)) · C \(Int(scaled(food).carbs)) · F \(Int(scaled(food).fat))")
                    }
                }
            }
            .navigationTitle("Log meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let trainee = store.currentTrainee else { return }
                        let food = selectedFood ?? FoodKnowledge(name: name, keywords: [], per100g: .init(calories: 120, protein: 8, carbs: 10, fat: 5))
                        store.saveMeal(
                            Meal(
                                id: UUID().uuidString,
                                traineeId: trainee.id,
                                name: food.name,
                                eatenAt: day,
                                portionGrams: grams,
                                macros: scaled(food),
                                source: "log",
                                isEstimate: true
                            )
                        )
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func scaled(_ food: FoodKnowledge) -> MacroEstimate {
        let factor = grams / 100
        return MacroEstimate(
            calories: Int(Double(food.per100g.calories) * factor),
            protein: food.per100g.protein * factor,
            carbs: food.per100g.carbs * factor,
            fat: food.per100g.fat * factor
        )
    }
}
