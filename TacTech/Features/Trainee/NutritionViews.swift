import SwiftUI

// MARK: - Nutrition Home (food database + meal tracker)

struct NutritionView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()
    @State private var showManual = false
    @State private var showProfile = false
    @State private var searchText = ""
    @State private var selectedCategory: FoodCategory = .meat
    @State private var calorieDraft: Double = 2100
    @State private var suggestionMessage: String?

    private let orange = TTColor.actionOrange
    private let blue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let canvas = Color(white: 0.97)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                nutritionHeader

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        browseCategory
                        morningRoutine
                        calorieGoal
                        suggestedMeal
                        browseMeals
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
            }
            .background(canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showManual) {
                ManualMealView(day: selectedDay)
            }
            .sheet(isPresented: $showProfile) {
                TraineeProfileView(showsBack: true)
            }
            .onAppear {
                calorieDraft = Double(store.currentTrainee?.dailyCalorieTarget ?? 2100)
            }
            .task(id: selectedDay) {
                if let trainee = store.currentTrainee {
                    await store.refreshDay(for: trainee.id, on: selectedDay)
                }
            }
            .overlay(alignment: .bottom) {
                if let suggestionMessage {
                    Text(suggestionMessage)
                        .font(TTFont.textSM(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Header

    private var nutritionHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Button { showProfile = true } label: {
                    avatarView
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text(formattedDate)
                        .font(TTFont.textSM(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.55))

                    Text("Hello, \(firstName)!")
                        .font(TTFont.headingLG(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 8) {
                        statusChip(
                            icon: .fire1,
                            text: "\(caloriesToday)kcal",
                            tint: orange
                        )
                        statusChip(
                            icon: .forkKnife,
                            text: hungerLabel,
                            tint: blue
                        )
                    }
                }

                Spacer(minLength: 8)

                Button { showProfile = true } label: {
                    ZStack(alignment: .topTrailing) {
                        TTIcon(icon: .bell1, size: 18)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if mealCountToday > 0 {
                            Text("\(min(mealCountToday, 9))")
                                .font(TTFont.text2XS(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color(red: 0.9, green: 0.2, blue: 0.25))
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Search our food database...")
                        .foregroundStyle(Color.white.opacity(0.45))
                )
                .font(TTFont.textLG(.medium))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

                NavigationLink {
                    FoodScannerView()
                } label: {
                    TTIcon(icon: .magnifyingGlass, size: 18)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            charcoal
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 36,
                        bottomTrailingRadius: 36,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
                .ignoresSafeArea(edges: .top)
        }
    }

    private var avatarView: some View {
        Group {
            if let asset = TTAvatarCatalog.saved(for: store.session?.userId) {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 58, height: 58)
                    Text(String(firstName.prefix(1)).uppercased())
                        .font(TTFont.headingSM(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
        )
    }

    private func statusChip(icon: SandowIcon, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            TTIcon(icon: icon, filled: true, size: 12)
                .foregroundStyle(tint)
            Text(text)
                .font(TTFont.textSM(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Browse Category

    private var browseCategory: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Browse Category", trailing: "See All") {
                searchText = ""
                selectedCategory = .all
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FoodCategory.allCases) { category in
                        let on = selectedCategory == category
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = category
                            }
                        } label: {
                            HStack(spacing: 8) {
                                TTIcon(icon: category.icon, filled: on, size: 16)
                                Text(category.title)
                                    .font(TTFont.textMD(.semibold))
                            }
                            .foregroundStyle(on ? .white : Color(white: 0.25))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(on ? blue : Color(white: 0.93))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Morning Routine

    private var morningRoutine: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Morning Routine", trailing: "See All") {
                showManual = true
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if morningItems.isEmpty {
                        morningCard(
                            title: "Log breakfast",
                            calories: 0,
                            protein: 0,
                            empty: true
                        )
                    } else {
                        ForEach(morningItems.prefix(6)) { meal in
                            morningCard(
                                title: meal.name,
                                calories: meal.macros.calories,
                                protein: Int(meal.macros.protein.rounded()),
                                empty: false
                            )
                        }
                    }
                }
            }
        }
    }

    private func morningCard(title: String, calories: Int, protein: Int, empty: Bool) -> some View {
        Button { showManual = true } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(orange)
                            .frame(width: 36, height: 36)
                        TTIcon(icon: .forkKnife, filled: true, size: 16)
                            .foregroundStyle(.white)
                    }

                    Text(title)
                        .font(TTFont.textLG(.bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        if empty {
                            Text("Add your first meal")
                                .font(TTFont.textSM(.medium))
                                .foregroundStyle(Color(white: 0.45))
                        } else {
                            Label("\(calories)kcal", systemImage: "flame.fill")
                                .font(TTFont.textSM(.medium))
                                .foregroundStyle(Color(white: 0.45))
                            Label("\(protein)g protein", systemImage: "bolt.fill")
                                .font(TTFont.textSM(.medium))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }
                }
                .padding(16)
                .frame(width: 150, alignment: .leading)

                Image("OnboardingNutrition")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 140)
                    .clipped()
            }
            .frame(height: 140)
            .background(Color(white: 0.93))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calorie Goal

    private var calorieGoal: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Calorie Goal")
                    .font(TTFont.headingSM(.bold))
                    .foregroundStyle(.black)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text("\(Int(calorieDraft)) kcal")
                        .font(TTFont.headingXL(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        store.updateDailyCalorieTarget(Int(calorieDraft))
                        flash("Goal saved")
                    } label: {
                        TTIcon(icon: .gear1, size: 16)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.22))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    Slider(value: $calorieDraft, in: 1200...4000, step: 50) {
                        Text("Goal")
                    } onEditingChanged: { editing in
                        if !editing {
                            store.updateDailyCalorieTarget(Int(calorieDraft))
                        }
                    }
                    .tint(.white)

                    HStack {
                        Text("1200")
                        Spacer()
                        Text("4000")
                    }
                    .font(TTFont.textXS(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(orange)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: orange.opacity(0.35), radius: 16, y: 8)
        }
    }

    // MARK: - Suggested meal (catalog-based, not fake AI)

    private var suggestedMeal: some View {
        let food = featuredSuggestion

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Suggested Meal", trailing: "See All") {
                selectedCategory = .all
                searchText = ""
            }

            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(suggestionTag(for: food))
                            .font(TTFont.textXS(.bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())

                        Text(food.name)
                            .font(TTFont.headingMD(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            suggestionStat(icon: "flame.fill", text: "\(food.per100g.calories)kcal")
                            suggestionStat(icon: "clock", text: "30min")
                            suggestionStat(icon: "fork.knife", text: "\(Int(food.per100g.protein))g protein")
                            suggestionStat(icon: "plus", text: suggestionTag(for: food))
                        }

                        Button {
                            addCatalogMeal(food)
                        } label: {
                            Text("Add Meal +")
                                .font(TTFont.textMD(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear.frame(width: 110)
                }
                .background(charcoal)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                Image("OnboardingNutrition")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 2))
                    .offset(x: 18)
                    .padding(.trailing, 8)
            }
            .padding(.trailing, 12)
        }
    }

    private func suggestionStat(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(TTFont.textSM(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    // MARK: - Browse Meals

    private var browseMeals: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Browse Meals")
                    .font(TTFont.headingSM(.bold))
                    .foregroundStyle(.black)
                Spacer()
                HStack(spacing: 6) {
                    Text(selectedCategory == .all && searchText.isEmpty ? "Most Popular" : "Filtered")
                        .font(TTFont.textMD(.medium))
                        .foregroundStyle(Color(white: 0.45))
                    TTIcon(icon: .wifiFull, size: 14)
                        .foregroundStyle(orange)
                }
            }

            if filteredFoods.isEmpty {
                Text("No foods match this filter. Try another category or search.")
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredFoods.prefix(8), id: \.name) { food in
                        Button {
                            addCatalogMeal(food)
                        } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(food.name)
                                        .font(TTFont.textLG(.bold))
                                        .foregroundStyle(.black)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)

                                    HStack(spacing: 12) {
                                        Label("\(food.per100g.calories)kcal", systemImage: "flame.fill")
                                        Label(String(format: "%.1f", popularityScore(food)), systemImage: "star.fill")
                                        Label("\(Int(food.per100g.protein))g", systemImage: "clock")
                                    }
                                    .font(TTFont.textSM(.medium))
                                    .foregroundStyle(Color(white: 0.45))
                                }

                                Spacer(minLength: 0)

                                Image("OnboardingNutrition")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .padding(14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Shared chrome

    private func sectionHeader(
        _ title: String,
        trailing: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(TTFont.headingSM(.bold))
                .foregroundStyle(.black)
            Spacer()
            Button(trailing, action: action)
                .font(TTFont.textMD(.semibold))
                .foregroundStyle(orange)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Data

    private var firstName: String {
        store.currentUser?.name.components(separatedBy: " ").first ?? "Athlete"
    }

    private var formattedDate: String {
        selectedDay.formatted(.dateTime.month(.abbreviated).day().year()).uppercased()
    }

    private var todayMeals: [Meal] {
        guard let trainee = store.currentTrainee else { return [] }
        return store.meals(for: trainee.id, on: selectedDay)
    }

    private var mealCountToday: Int { todayMeals.count }

    private var caloriesToday: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        return store.dailyMacros(for: trainee.id, on: selectedDay).calories
    }

    private var hungerLabel: String {
        let target = store.currentTrainee?.dailyCalorieTarget ?? 2100
        let remaining = target - caloriesToday
        if remaining <= 0 { return "Full" }
        if remaining < 400 { return "Almost" }
        return "Hungry"
    }

    private var morningItems: [Meal] {
        let cal = Calendar.current
        return todayMeals.filter { meal in
            let hour = cal.component(.hour, from: meal.eatenAt)
            return hour < 12
        }
    }

    private var filteredFoods: [FoodKnowledge] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.foodCatalog.filter { food in
            let matchesCategory = selectedCategory.matches(food)
            let matchesQuery = query.isEmpty
                || food.name.lowercased().contains(query)
                || food.keywords.contains { $0.lowercased().contains(query) }
            return matchesCategory && matchesQuery
        }
        .sorted { popularityScore($0) > popularityScore($1) }
    }

    private var featuredSuggestion: FoodKnowledge {
        filteredFoods.max(by: { $0.per100g.protein < $1.per100g.protein })
            ?? store.foodCatalog.first
            ?? FoodKnowledge(
                name: "Protein Bowl",
                keywords: ["protein"],
                per100g: .init(calories: 165, protein: 25, carbs: 10, fat: 5)
            )
    }

    private func popularityScore(_ food: FoodKnowledge) -> Double {
        // Lightweight ranking from macros — not a fake rating API.
        min(5.0, 3.2 + food.per100g.protein / 20)
    }

    private func suggestionTag(for food: FoodKnowledge) -> String {
        if food.per100g.protein >= 20 { return "Protein-Rich" }
        if food.per100g.carbs >= 20 { return "Energy" }
        if food.per100g.fat >= 12 { return "Healthy Fats" }
        return "Balanced"
    }

    private func addCatalogMeal(_ food: FoodKnowledge) {
        guard let trainee = store.currentTrainee else { return }
        let portion: Double = 220
        let factor = portion / 100
        let macros = MacroEstimate(
            calories: Int(Double(food.per100g.calories) * factor),
            protein: food.per100g.protein * factor,
            carbs: food.per100g.carbs * factor,
            fat: food.per100g.fat * factor
        )
        Task {
            try? await store.saveMeal(
                Meal(
                    id: UUID().uuidString,
                    traineeId: trainee.id,
                    name: food.name,
                    eatenAt: selectedDay,
                    portionGrams: portion,
                    macros: macros,
                    source: "catalog",
                    isEstimate: true
                )
            )
            flash("Added \(food.name)")
        }
    }

    private func flash(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            suggestionMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                suggestionMessage = nil
            }
        }
    }
}

// MARK: - Categories

private enum FoodCategory: String, CaseIterable, Identifiable {
    case vegetable, fruit, dining, meat, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vegetable: "Vegetable"
        case .fruit: "Fruit"
        case .dining: "Dining"
        case .meat: "Meat"
        case .all: "All"
        }
    }

    var icon: SandowIcon {
        switch self {
        case .vegetable: .leaf
        case .fruit: .apple
        case .dining: .forkKnife
        case .meat: .heart
        case .all: .magnifyingGlass
        }
    }

    func matches(_ food: FoodKnowledge) -> Bool {
        let blob = ([food.name] + food.keywords).joined(separator: " ").lowercased()
        switch self {
        case .all:
            return true
        case .vegetable:
            return blob.contains("broccoli") || blob.contains("veg") || blob.contains("salad") || blob.contains("lettuce")
        case .fruit:
            return blob.contains("fruit") || blob.contains("banana") || blob.contains("apple") || blob.contains("avocado")
        case .dining:
            return blob.contains("pasta") || blob.contains("pizza") || blob.contains("rice") || blob.contains("bowl") || blob.contains("shake") || blob.contains("yogurt") || blob.contains("oatmeal") || blob.contains("egg")
        case .meat:
            return blob.contains("chicken") || blob.contains("salmon") || blob.contains("fish") || blob.contains("burger") || blob.contains("poultry") || blob.contains("meat")
        }
    }
}

// MARK: - Manual meal (unchanged flow)

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
                            Task {
                                if let remote = await store.searchFood(query: value) {
                                    selectedFood = remote
                                }
                            }
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
                        let food = selectedFood ?? FoodKnowledge(
                            name: name,
                            keywords: [],
                            per100g: .init(calories: 120, protein: 8, carbs: 10, fat: 5)
                        )
                        Task {
                            try? await store.saveMeal(
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
                        }
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

#Preview("Nutrition Home") {
    NutritionView()
        .ttPreviewTrainee()
}

#Preview("Manual Meal") {
    NavigationStack {
        ManualMealView(day: .now)
            .ttPreviewTrainee()
    }
}
