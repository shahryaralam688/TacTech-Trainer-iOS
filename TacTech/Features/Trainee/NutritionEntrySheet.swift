import AVFoundation
import Charts
import ImageIO
import PhotosUI
import SwiftUI
import Vision

// MARK: - Goal sheet

struct NutritionGoalContent: View {
    @Environment(AppStore.self) private var store
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void

    @State private var value = 2100
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily calorie goal")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Changing it updates your ring and what is left.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .padding(.top, 2).padding(.bottom, 10)
            HStack(spacing: 18) {
                roundButton("−", label: "Lower by 50") { value = max(1200, value - 50) }
                Text("\(value) kcal")
                    .font(TTFont.workSans(34, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 130)
                    .minimumScaleFactor(0.7)
                roundButton("+", label: "Raise by 50") { value = min(4000, value + 50) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            if let errorText {
                Text(verbatim: errorText).font(TTFont.body(13)).foregroundStyle(NutStyle.danger).padding(.bottom, 4)
            }
            nutPanelButton("Save goal", style: .primary, loading: saving) { save() }
                .disabled(saving)
            nutPanelButton("Cancel", style: .ghost) { close(nil) }
                .disabled(saving)
        }
        .onAppear { value = (store.currentTrainee?.dailyCalorieTarget ?? 0) > 0 ? (store.currentTrainee?.dailyCalorieTarget ?? 2100) : 2100 }
    }

    private func roundButton(_ glyph: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph).font(TTFont.workSans(26, weight: .regular))
                .foregroundStyle(TTColor.ink)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        errorText = nil
        let target = value
        Task {
            do {
                try await store.saveDailyCalorieTarget(target)
                saving = false
                close {
                    onSaved(TTToastMessage(text: String(format: String(localized: "Goal saved: %lld kcal"), target), style: .success))
                }
            } catch {
                saving = false
                errorText = error.localizedDescription.isEmpty ? String(localized: "Couldn’t save goal") : error.localizedDescription
            }
        }
    }
}

/// Size steps. The stored `detail` always uses these English tokens so an edit can rebuild the options.
struct NutSize {
    let token: String
    let title: LocalizedStringKey
    let factor: Double
    static let piece = [
        NutSize(token: "Small", title: "Small", factor: 0.85),
        NutSize(token: "Medium", title: "Medium", factor: 1),
        NutSize(token: "Large", title: "Large", factor: 1.15)
    ]
    static let plate = [
        NutSize(token: "Small", title: "Small", factor: 0.75),
        NutSize(token: "Regular", title: "Regular", factor: 1),
        NutSize(token: "Large", title: "Large", factor: 1.3)
    ]
}

struct NutDraft {
    var name: String
    var kind: NutKind
    var mealType: TTMealType
    var notes = ""
    /// Per gram (or ml) values the portion is multiplied with.
    var perUnit: (kcal: Double, p: Double, c: Double, f: Double)
    var status: String        // "eaten" | "planned"
    var time: Date
    var timeTouched = false
    var isCustom = false
    var customKcal = ""
    var customProtein = ""
    var customCarbs = ""
    var customFat = ""
    // drink
    var ml: Double = 250
    // piece
    var count = 1
    // piece / plate size index; nil = keep `storedPortion` (an old entry whose detail can't be read)
    var size: Int? = nil
    var storedPortion: Double?

    // TODO: the backend has no grams-per-piece or grams-per-plate. A medium piece is treated as 100 g and a regular
    // plate as 250 g (the sizes then scale that). A drink is treated as 1 ml = 1 g.
    static let pieceBase = 100.0
    static let plateBase = 250.0

    var portion: Double {
        switch kind {
        case .drink: return ml
        case .piece:
            guard let size else { return storedPortion ?? Self.pieceBase }
            return Double(count) * NutSize.piece[size].factor * Self.pieceBase
        case .plate:
            guard let size else { return storedPortion ?? Self.plateBase }
            return NutSize.plate[size].factor * Self.plateBase
        }
    }

    var detail: String {
        switch kind {
        case .drink: return "\(Int(ml)) ml"
        case .piece:
            guard let size else { return "\(Int(portion.rounded())) g" }
            return "\(count) × \(NutSize.piece[size].token)"
        case .plate:
            guard let size else { return "\(Int(portion.rounded())) g" }
            return "\(NutSize.plate[size].token) portion"
        }
    }

    /// A custom food uses the calories and macros the person typed; empty stays 0 ("— kcal", not counted).
    var macros: MacroEstimate {
        if isCustom {
            return MacroEstimate(
                calories: Int(customKcal.trimmingCharacters(in: .whitespaces)) ?? 0,
                protein: Double(customProtein.trimmingCharacters(in: .whitespaces)) ?? 0,
                carbs: Double(customCarbs.trimmingCharacters(in: .whitespaces)) ?? 0,
                fat: Double(customFat.trimmingCharacters(in: .whitespaces)) ?? 0
            )
        }
        let g = portion
        return MacroEstimate(
            calories: Int((perUnit.kcal * g).rounded()),
            protein: (perUnit.p * g * 10).rounded() / 10,
            carbs: (perUnit.c * g * 10).rounded() / 10,
            fat: (perUnit.f * g * 10).rounded() / 10
        )
    }

    static func new(
        name: String,
        kind: NutKind,
        mealType: TTMealType? = nil,
        perUnit: (kcal: Double, p: Double, c: Double, f: Double),
        custom: Bool,
        time: Date
    ) -> NutDraft {
        var d = NutDraft(
            name: name,
            kind: kind,
            mealType: mealType ?? TTMealType.suggested(at: time),
            perUnit: perUnit,
            status: "eaten",
            time: time,
            isCustom: custom
        )
        d.size = kind == .piece ? 1 : (kind == .plate ? 1 : nil)
        return d
    }

    /// Rebuilds the options of a saved entry from its kind and detail.
    static func from(meal: Meal) -> NutDraft {
        let g = max(meal.portionGrams, 1)
        let kind = NutKind(rawValue: meal.kind ?? "") ?? NutKind.infer(name: meal.name)
        let mealType = TTMealType(rawValue: meal.mealType ?? "") ?? TTMealType.suggested(at: meal.eatenAt)
        var d = NutDraft(
            name: meal.name, kind: kind, mealType: mealType, notes: meal.notes ?? "",
            perUnit: (Double(meal.macros.calories) / g, meal.macros.protein / g, meal.macros.carbs / g, meal.macros.fat / g),
            status: meal.isPlanned ? "planned" : "eaten", time: meal.eatenAt,
            isCustom: meal.source == "custom"
        )
        if d.isCustom {
            if meal.macros.calories > 0 { d.customKcal = String(meal.macros.calories) }
            if meal.macros.protein > 0 { d.customProtein = Self.formatMacroInput(meal.macros.protein) }
            if meal.macros.carbs > 0 { d.customCarbs = Self.formatMacroInput(meal.macros.carbs) }
            if meal.macros.fat > 0 { d.customFat = Self.formatMacroInput(meal.macros.fat) }
        }
        let detail = meal.detail ?? ""
        switch kind {
        case .drink:
            d.ml = meal.portionGrams > 0 ? meal.portionGrams : 250
            if let n = Int(detail.split(separator: " ").first ?? ""), detail.hasSuffix("ml") || detail.hasSuffix("g") { d.ml = Double(n) }
        case .piece:
            let parts = detail.components(separatedBy: " × ")
            if parts.count == 2, let n = Int(parts[0]), (1...6).contains(n),
               let i = NutSize.piece.firstIndex(where: { $0.token == parts[1] }) {
                d.count = n; d.size = i
            } else { d.storedPortion = meal.portionGrams > 0 ? meal.portionGrams : nil }
        case .plate:
            if detail.hasSuffix(" portion"),
               let i = NutSize.plate.firstIndex(where: { $0.token == String(detail.dropLast(" portion".count)) }) {
                d.size = i
            } else { d.storedPortion = meal.portionGrams > 0 ? meal.portionGrams : nil }
        }
        return d
    }

    private static func formatMacroInput(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct NutritionEntryContent: View {
    @Environment(AppStore.self) private var store
    let editing: Meal?
    var initialPhoto: UIImage? = nil
    var initialFood: FoodKnowledge? = nil
    var initialQuery: String? = nil
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void
    let onDelete: (Meal) -> Void

    @State private var query = ""
    @State private var remote: FoodKnowledge?
    @State private var searchTask: Task<Void, Never>?
    @State private var draft: NutDraft?
    /// A frequent meal with its foods opens the Meal Tray directly.
    @State private var trayItems: [NutTrayItem]?
    @State private var activePhoto: UIImage?
    @State private var photoCategory: NutPhotoCategory = .meal
    @State private var showRetakeCamera = false
    @State private var showRetakeLibrary = false
    @State private var retakeLibraryItem: PhotosPickerItem?
    @State private var saving = false
    @State private var errorText: String?
    @FocusState private var searchFocused: Bool

    /// Time the sheet opened ("Now"). Eaten entries can't be later; planned entries start after it.
    @State private var now = Date()

    var body: some View {
        Group {
            if let trayItems {
                NutMealTrayContent(items: trayItems, mealTag: nil, source: "log", heroPhoto: nil, close: close, onSaved: onSaved)
            } else if draft == nil {
                chooser
            } else {
                details
            }
        }
        .onAppear {
            now = Date()
            if activePhoto == nil { activePhoto = initialPhoto }
            if let editing, draft == nil {
                draft = NutDraft.from(meal: editing)
            } else if let initialFood, draft == nil {
                pick(Self.option(from: initialFood))
            } else if let initialQuery, query.isEmpty {
                query = initialQuery
            }
        }
        .sheet(isPresented: $showRetakeCamera) {
            CameraImagePicker(image: $activePhoto)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showRetakeLibrary, selection: $retakeLibraryItem, matching: .images)
        .onChange(of: retakeLibraryItem) { _, item in
            guard let item else { return }
            Task {
                defer { retakeLibraryItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    activePhoto = image
                }
            }
        }
    }

    // MARK: Step 1 — choose

    private struct Option: Identifiable {
        let id: String
        let name: String
        let perUnit: (kcal: Double, p: Double, c: Double, f: Double)
        let kind: NutKind
        let subtitle: String
        var custom = false
    }

    private var options: [Option] {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var foods = store.foodCatalog
        if let remote, !foods.contains(where: { $0.name == remote.name }) { foods.insert(remote, at: 0) }
        if t.isEmpty {
            // Recent: the trainee's own latest entries (real per-gram values), then nothing invented.
            var seen = Set<String>()
            var out: [Option] = []
            for m in store.meals.sorted(by: { $0.eatenAt > $1.eatenAt }) where m.traineeId == store.currentTrainee?.id && m.portionGrams > 0 && m.source != "custom" {
                guard seen.insert(m.name.lowercased()).inserted else { continue }
                out.append(Option(
                    id: "recent-\(m.id)", name: m.name,
                    perUnit: (Double(m.macros.calories) / m.portionGrams, m.macros.protein / m.portionGrams, m.macros.carbs / m.portionGrams, m.macros.fat / m.portionGrams),
                    kind: NutKind(rawValue: m.kind ?? "") ?? NutKind.infer(name: m.name),
                    subtitle: String(format: String(localized: "%lld kcal per 100 g"), Int((Double(m.macros.calories) / m.portionGrams * 100).rounded()))
                ))
                if out.count >= 8 { break }
            }
            if !out.isEmpty { return out }
            return foods.prefix(12).map(Self.option(from:))
        }
        return foods.filter { f in
            f.name.lowercased().contains(t) || f.keywords.contains { $0.lowercased().contains(t) }
        }.map(Self.option(from:))
    }

    private static func option(from f: FoodKnowledge) -> Option {
        Option(
            id: "food-\(f.name)", name: f.name,
            perUnit: (Double(f.per100g.calories) / 100, f.per100g.protein / 100, f.per100g.carbs / 100, f.per100g.fat / 100),
            kind: NutKind.infer(name: f.name, keywords: f.keywords),
            subtitle: String(format: String(localized: "%lld kcal per 100 g"), f.per100g.calories)
        )
    }

    private var chooser: some View {
        let list = options
        let typed = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Text("Add food or drink")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Saved with today's date and time.")
                .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                .padding(.top, 2).padding(.bottom, 10)
            if let activePhoto {
                photoBanner(activePhoto)
                    .padding(.bottom, 12)
            }
            TextField("Search foods and drinks", text: $query)
                .font(TTFont.body(16))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(searchFocused ? NutStyle.orange : Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
                .focused($searchFocused)
                .submitLabel(.search)
                .padding(.vertical, 4)
                .onChange(of: query) { _, value in
                    remote = nil
                    searchTask?.cancel()
                    let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else { return }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled else { return }
                        let found = await store.searchFood(query: q)
                        if !Task.isCancelled && query.trimmingCharacters(in: .whitespacesAndNewlines) == q {
                            remote = found
                        }
                    }
                }
                .accessibilityLabel("Search foods and drinks")
            if !typed, editing == nil, !store.frequentMeals.isEmpty {
                Text("FREQUENT")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(NutStyle.mute)
                    .padding(.top, 12).padding(.bottom, 6).padding(.horizontal, 2)
                ForEach(Array(store.frequentMeals.prefix(5).enumerated()), id: \.element.id) { i, meal in
                    chooserRow(
                        name: meal.name,
                        subtitle: frequentSubtitle(meal),
                        kind: meal.kind,
                        first: i == 0,
                        trailing: "\(Int((meal.calories ?? 0).rounded())) kcal"
                    ) { pickFrequent(meal) }
                }
            }
            Text(typed ? "RESULTS" : (list.first?.id.hasPrefix("recent-") == true ? "RECENT" : "SUGGESTED"))
                .font(TTFont.workSans(12, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(NutStyle.mute)
                .padding(.top, 12).padding(.bottom, 6).padding(.horizontal, 2)
            if list.isEmpty {
                Text("No match. Add it as a custom food in the app.")
                    .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                    .padding(.horizontal, 2).padding(.bottom, 10)
                // TODO: the prototype only shows the text above; without this row a food that isn't in the list
                // could not be logged at all (the old sheet allowed any name).
                let typedName = query.trimmingCharacters(in: .whitespacesAndNewlines)
                chooserRow(name: typedName, subtitle: String(localized: "Custom food"), kind: nil, first: true) {
                    pick(Option(id: "custom", name: typedName, perUnit: (0, 0, 0, 0), kind: NutKind.infer(name: typedName), subtitle: "", custom: true))
                }
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, option in
                    chooserRow(name: option.name, subtitle: option.subtitle, kind: option.kind.rawValue, first: i == 0) { pick(option) }
                }
            }
        }
        .onAppear { searchFocused = false }
    }

    private func photoBanner(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Food photo attached")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                    HStack(spacing: 8) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Retake") { showRetakeCamera = true }
                                .font(TTFont.workSans(12, weight: .semibold))
                                .foregroundStyle(NutStyle.orange)
                                .buttonStyle(.plain)
                        }
                        Button("Library") { showRetakeLibrary = true }
                            .font(TTFont.workSans(12, weight: .semibold))
                            .foregroundStyle(NutStyle.mute)
                            .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(NutPhotoCategory.allCases) { cat in
                    let on = photoCategory == cat
                    Button {
                        photoCategory = cat
                    } label: {
                        Text(cat.title)
                            .font(TTFont.workSans(13, weight: .semibold))
                            .foregroundStyle(on ? .white : TTColor.ink)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? NutStyle.orange : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            nutPanelButton("Continue with photo", style: .primary) {
                continueWithPhoto()
            }
        }
        .padding(12)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func continueWithPhoto() {
        searchFocused = false
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName: String
        switch photoCategory {
        case .meal: defaultName = String(localized: "Meal")
        case .snack: defaultName = String(localized: "Snack")
        case .drink: defaultName = String(localized: "Drink")
        }
        let name = typed.isEmpty ? defaultName : typed
        draft = NutDraft.new(
            name: name,
            kind: photoCategory.kind,
            mealType: photoCategory.defaultMealType(at: now),
            perUnit: (0, 0, 0, 0),
            custom: true,
            time: now
        )
    }

    private func frequentSubtitle(_ meal: FrequentMeal) -> String {
        var parts: [String] = []
        if let detail = meal.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty { parts.append(detail) }
        if let count = meal.count { parts.append(String(format: String(localized: "Logged %lld×"), count)) }
        return parts.joined(separator: " · ")
    }

    /// 1-tap repeat: the foods open in the Meal Tray; a meal without foods opens the entry sheet filled in.
    private func pickFrequent(_ m: FrequentMeal) {
        searchFocused = false
        if let items = m.mealItems, !items.isEmpty {
            trayItems = items.map { NutTrayBuilder.item(from: $0) }
            return
        }
        let meal = Meal(
            id: UUID().uuidString, traineeId: store.currentTrainee?.id ?? "", name: m.name, eatenAt: now,
            portionGrams: max(m.portionGrams ?? 0, 1),
            macros: MacroEstimate(calories: Int((m.calories ?? 0).rounded()), protein: m.proteinG ?? 0, carbs: m.carbsG ?? 0, fat: m.fatG ?? 0),
            source: "log", isEstimate: true, status: "eaten", kind: m.kind, detail: m.detail
        )
        draft = NutDraft.from(meal: meal)
    }

    private func chooserRow(name: String, subtitle: String, kind: String?, first: Bool, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                NutTile(name: name, kind: kind, planned: false, hasPhoto: false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: name).font(TTFont.workSans(15, weight: .semibold)).foregroundStyle(TTColor.ink).lineLimit(1)
                    Text(verbatim: subtitle).font(TTFont.workSans(12, weight: .regular)).foregroundStyle(NutStyle.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let trailing {
                    Text(verbatim: trailing)
                        .font(TTFont.workSans(14, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(TTColor.ink)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if !first { Rectangle().fill(NutStyle.line).frame(height: 1) } }
    }

    private func pick(_ option: Option) {
        searchFocused = false
        let mealType: TTMealType = activePhoto != nil
            ? photoCategory.defaultMealType(at: now)
            : TTMealType.suggested(at: now)
        draft = NutDraft.new(
            name: option.name,
            kind: option.kind,
            mealType: mealType,
            perUnit: option.perUnit,
            custom: option.custom,
            time: now
        )
    }

    // MARK: Step 2 — details (options follow the kind)

    private var details: some View {
        let d = draft!
        let m = d.macros
        let ate = d.status == "eaten"
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let activePhoto {
                    Image(uiImage: activePhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if let photoUrl = editing?.photoUrl {
                    TTMealPhoto(urlString: photoUrl)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    NutTile(name: d.name, kind: d.kind.rawValue, planned: false, hasPhoto: false)
                        .scaleEffect(56.0 / 42.0).frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: d.name.isEmpty ? String(localized: "Meal") : d.name)
                        .font(TTFont.workSans(20, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(2)
                    Text(editing == nil ? "Chosen by you" : "Editing entry")
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(NutStyle.mute)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2).padding(.bottom, 4)

            if d.isCustom && editing == nil {
                customNameField
                kindOptions(d)
            }

            switch d.kind {
            case .drink: drinkOptions(d)
            case .piece: pieceOptions(d)
            case .plate: plateOptions(d)
            }

            mealTypeOptions(d)

            if d.isCustom { customNutrition(d) }

            notesField

            estimate(m)

            HStack(spacing: 0) {
                seg("Ate it", on: ate) { setStatus("eaten") }
                seg("Plan it", on: !ate) { setStatus("planned") }
            }
            .padding(3)
            .background(NutStyle.track)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.vertical, 6)

            HStack {
                Text(verbatim: (sameMinute(d.time, now) ? "\(String(localized: "Now")) · " : "") + d.time.formatted(date: .omitted, time: .shortened))
                    .font(TTFont.workSans(16, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    roundStep("−", label: "15 minutes earlier") { shiftTime(-15, ate: ate, endOfDay: endOfDay) }
                    roundStep("+", label: "15 minutes later") { shiftTime(15, ate: ate, endOfDay: endOfDay) }
                }
            }
            .padding(.vertical, 6)

            if let errorText {
                Text(verbatim: errorText).font(TTFont.body(13)).foregroundStyle(NutStyle.danger).padding(.top, 4)
            }
            nutPanelButton(saving ? "Saving…" : (editing != nil ? "Save changes" : (ate ? "Save" : "Save plan")), style: .primary, loading: saving) { save() }
                .disabled(saving)
                .padding(.top, 10)
            if let editing {
                nutPanelButton("Delete entry", style: .danger) { close { onDelete(editing) } }
                    .disabled(saving)
            } else {
                nutPanelButton("Cancel", style: .ghost) { close(nil) }
                    .disabled(saving)
            }
        }
    }

    private var customNameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("NAME")
            TextField("e.g. Milk, Chicken Bowl, Apple", text: Binding(
                get: { draft?.name ?? "" },
                set: { draft?.name = $0 }
            ))
            .font(TTFont.body(15))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(NutStyle.field)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func kindOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("TYPE")
            chipRow {
                chip(Text("Meal"), on: d.kind == .plate) {
                    draft?.kind = .plate
                    draft?.size = 1
                }
                chip(Text("Snack"), on: d.kind == .piece) {
                    draft?.kind = .piece
                    draft?.size = 1
                    draft?.mealType = .snack
                }
                chip(Text("Drink"), on: d.kind == .drink) {
                    draft?.kind = .drink
                    draft?.size = nil
                }
            }
        }
    }

    private func mealTypeOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("MEAL")
            chipRow {
                ForEach(TTMealType.allCases) { type in
                    chip(Text(type.title), on: d.mealType == type) {
                        draft?.mealType = type
                    }
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("NOTES")
            TextField("Optional details (e.g. low-fat milk, homemade)", text: Binding(
                get: { draft?.notes ?? "" },
                set: { draft?.notes = $0 }
            ))
            .font(TTFont.body(14))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(NutStyle.field)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func drinkOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("AMOUNT")
            chipRow {
                ForEach([("Glass", 250.0), ("Cup", 200.0), ("Bottle", 500.0)], id: \.0) { name, v in
                    chip(Text(LocalizedStringKey(name)) + Text(verbatim: " · \(Int(v)) ml"), on: d.ml == v) { draft?.ml = v }
                }
            }
            HStack(spacing: 12) {
                roundStep("−", label: "Less") { draft?.ml = max(50, d.ml - 50) }
                Text(verbatim: "\(Int(d.ml)) ml")
                    .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 96)
                roundStep("+", label: "More") { draft?.ml = min(1000, d.ml + 50) }
            }
            .padding(.vertical, 6)
        }
    }

    private func pieceOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("HOW MANY")
            HStack(spacing: 12) {
                roundStep("−", label: "Fewer") { draft?.count = max(1, d.count - 1) }
                Text(verbatim: "\(d.count)")
                    .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                    .frame(minWidth: 96)
                roundStep("+", label: "More") { draft?.count = min(6, d.count + 1) }
            }
            .padding(.vertical, 6)
            label("SIZE")
            chipRow {
                ForEach(Array(NutSize.piece.enumerated()), id: \.offset) { i, s in
                    chip(Text(s.title), on: d.size == i) { draft?.size = i }
                }
            }
        }
    }

    private func plateOptions(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label("PORTION")
            chipRow {
                ForEach(Array(NutSize.plate.enumerated()), id: \.offset) { i, s in
                    chip(Text(s.title), on: d.size == i) { draft?.size = i }
                }
            }
        }
    }

    private func customNutrition(_ d: NutDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label("CALORIES & MACROS (OPTIONAL)")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                macroInputField(
                    title: "Calories",
                    unit: "kcal",
                    text: Binding(
                        get: { draft?.customKcal ?? "" },
                        set: { draft?.customKcal = $0.filter(\.isNumber) }
                    ),
                    decimal: false
                )
                macroInputField(
                    title: "Protein",
                    unit: "g",
                    text: Binding(
                        get: { draft?.customProtein ?? "" },
                        set: { draft?.customProtein = sanitizeDecimal($0) }
                    ),
                    decimal: true
                )
                macroInputField(
                    title: "Carbs",
                    unit: "g",
                    text: Binding(
                        get: { draft?.customCarbs ?? "" },
                        set: { draft?.customCarbs = sanitizeDecimal($0) }
                    ),
                    decimal: true
                )
                macroInputField(
                    title: "Fat",
                    unit: "g",
                    text: Binding(
                        get: { draft?.customFat ?? "" },
                        set: { draft?.customFat = sanitizeDecimal($0) }
                    ),
                    decimal: true
                )
            }
        }
    }

    private func macroInputField(title: LocalizedStringKey, unit: String, text: Binding<String>, decimal: Bool) -> some View {
        HStack(spacing: 6) {
            TextField(title, text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(TTFont.workSans(15, weight: .semibold))
            Text(verbatim: unit)
                .font(TTFont.workSans(12, weight: .regular))
                .foregroundStyle(NutStyle.mute)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5)
        )
    }

    private func sanitizeDecimal(_ input: String) -> String {
        var seenDot = false
        return String(input.filter { ch in
            if ch.isNumber { return true }
            if ch == "." && !seenDot { seenDot = true; return true }
            return false
        })
    }

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // Wraps to a second line at large text sizes.
        NutFlow(spacing: 8) { content() }
    }

    private func chip(_ title: Text, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(on ? Color.white : TTColor.ink)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(on ? Color.black : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(on ? Color.black : Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text).font(TTFont.workSans(12, weight: .semibold)).tracking(1.4).foregroundStyle(NutStyle.mute)
            .padding(.top, 12).padding(.bottom, 6).padding(.horizontal, 2)
    }

    private func roundStep(_ glyph: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: glyph).font(TTFont.workSans(22, weight: .regular)).foregroundStyle(TTColor.ink)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func seg(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(TTFont.workSans(15, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color(white: 0.07) : Color(red: 85 / 255, green: 85 / 255, blue: 91 / 255))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: on ? .black.opacity(0.16) : .clear, radius: 1.5, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func estimate(_ m: MacroEstimate) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if m.calories > 0 {
                    Text("\(m.calories) kcal").font(TTFont.workSans(18, weight: .bold)).monospacedDigit()
                } else {
                    Text(verbatim: "— kcal").font(TTFont.workSans(18, weight: .bold))
                }
                Text("Estimate").font(TTFont.workSans(13, weight: .regular).italic()).foregroundStyle(NutStyle.mute)
            }
            Spacer(minLength: 4)
            macroCell("Protein", m.protein)
            macroCell("Carbs", m.carbs)
            macroCell("Fat", m.fat)
        }
        .foregroundStyle(TTColor.ink)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 10).padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    private func macroCell(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(TTFont.workSans(12, weight: .regular)).foregroundStyle(Color(white: 0.27))
            Text(verbatim: "\(value.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(TTFont.workSans(15, weight: .bold)).monospacedDigit()
        }
    }

    private func sameMinute(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, equalTo: b, toGranularity: .minute)
    }

    private func setStatus(_ status: String) {
        guard var d = draft else { return }
        d.status = status
        if status == "planned", d.time <= now { d.time = now.addingTimeInterval(78 * 60) }
        if status == "eaten", d.time > now { d.time = now }
        // Never past the end of today (planned entries are for later today only).
        if let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now), d.time > end { d.time = end }
        d.timeTouched = true
        draft = d
    }

    private func shiftTime(_ minutes: Int, ate: Bool, endOfDay: Date) {
        guard var d = draft else { return }
        var t = d.time.addingTimeInterval(Double(minutes) * 60)
        if ate { t = min(now, t) } else { t = min(endOfDay, max(now.addingTimeInterval(15 * 60), t)) }
        d.time = t
        d.timeTouched = true
        draft = d
    }

    // MARK: Save

    private func save() {
        guard let d = draft, !saving else { return }
        saving = true
        errorText = nil
        let macros = d.macros
        Task {
            do {
                var savedName = d.name
                var savedTime = d.time
                if let editing {
                    var body = UpdateMealBody(portionGrams: d.portion, macros: macros, status: d.status, kind: d.kind.rawValue, detail: d.detail)
                    if d.timeTouched || d.status == "planned" { body.eatenAt = d.time }
                    let updated = try await store.updateMeal(editing, changes: body)
                    savedName = updated.name; savedTime = updated.eatenAt
                } else {
                    let trimmedName = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = trimmedName.isEmpty ? String(localized: "Meal") : trimmedName
                    let trimmedNotes = d.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let meal = Meal(
                        id: UUID().uuidString, traineeId: store.currentTrainee?.id ?? "", name: finalName,
                        eatenAt: d.time, portionGrams: d.portion, macros: macros,
                        source: d.isCustom ? "custom" : "log", isEstimate: true,
                        mealType: d.mealType.rawValue,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                        status: d.status, kind: d.kind.rawValue, detail: d.detail
                    )
                    // "Eaten now" leaves the time to the server; a chosen or planned time is sent.
                    try await store.saveMeal(meal, photo: activePhoto, sendsEatenAt: d.status == "planned" || d.timeTouched)
                    savedName = finalName
                }
                saving = false
                let time = savedTime.formatted(date: .omitted, time: .shortened)
                let text = d.status == "planned"
                    ? String(format: String(localized: "%@ planned · %@"), savedName, time)
                    : String(format: String(localized: "%@ saved · %@"), savedName, time)
                close {
                    onSaved(TTToastMessage(text: text, style: .success))
                    UIAccessibility.post(notification: .announcement, argument: text)
                }
            } catch {
                // Inputs stay as they are so the person can try again.
                saving = false
                errorText = error.localizedDescription.isEmpty ? String(localized: "Couldn’t save entry") : error.localizedDescription
            }
        }
    }
}

// MARK: - Compatibility: other screens open the add sheet as a normal sheet (centre "+" menu)

struct ManualMealView: View {
    @Environment(\.dismiss) private var dismiss
    let day: Date
    var prefillName: String? = nil
    var initialPhoto: UIImage? = nil
    var onSaved: ((TTToastMessage) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255))
                .frame(width: 40, height: 5).padding(.top, 8).padding(.bottom, 10)
            ScrollView {
                NutritionEntryContent(
                    editing: nil,
                    initialPhoto: initialPhoto,
                    initialQuery: prefillName,
                    close: { after in dismiss(); after?() },
                    onSaved: { toast in onSaved?(toast) },
                    onDelete: { _ in }
                )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}
