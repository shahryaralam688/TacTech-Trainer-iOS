import AVFoundation
import Charts
import ImageIO
import PhotosUI
import SwiftUI
import Vision

enum NutPhotoCategory: String, CaseIterable, Identifiable {
    case meal, snack, drink
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .meal: "Meal"
        case .snack: "Snack"
        case .drink: "Drink"
        }
    }

    var kind: NutKind {
        switch self {
        case .meal: .plate
        case .snack: .piece
        case .drink: .drink
        }
    }

    func defaultMealType(at date: Date) -> TTMealType {
        switch self {
        case .snack:
            return .snack
        case .meal, .drink:
            let suggested = TTMealType.suggested(at: date)
            return suggested == .snack ? .lunch : suggested
        }
    }
}

// MARK: - Meal photos: capture, AI disclosure, barcode and the meal tray

enum NutTrust: String {
    case verifiedLabel = "verified_label"
    case databaseMatch = "database_match"
    case aiEstimate = "ai_estimate"

    init(raw: String?) { self = NutTrust(rawValue: raw ?? "") ?? .aiEstimate }

    var title: LocalizedStringKey {
        switch self {
        case .verifiedLabel: "Verified Label"
        case .databaseMatch: "Database Match"
        case .aiEstimate: "AI Estimate"
        }
    }

    var tint: Color {
        switch self {
        case .verifiedLabel: Color(red: 22 / 255, green: 101 / 255, blue: 52 / 255)
        case .databaseMatch: Color(red: 30 / 255, green: 64 / 255, blue: 175 / 255)
        case .aiEstimate: Color(red: 194 / 255, green: 65 / 255, blue: 12 / 255)
        }
    }
}

struct NutModifierOption {
    let token: String
    let title: LocalizedStringKey
    /// How the nutrition changes when this option is chosen (relative to the neutral option).
    let apply: (NutNutrition) -> NutNutrition
}

enum NutModifierProfile: String {
    case curryOil = "curry_oil"
    case teaSugar = "tea_sugar"
    case milkType = "milk_type"

    var neutralIndex: Int { self == .curryOil ? 1 : 0 }

    var options: [NutModifierOption] {
        switch self {
        case .curryOil:
            return [
                NutModifierOption(token: "Kam Oil", title: "Kam Oil") { n in
                    var r = n; r.f = n.f * 0.85; r.kcal = n.kcal - n.f * 0.15 * 9; return r
                },
                NutModifierOption(token: "Normal", title: "Normal") { $0 },
                NutModifierOption(token: "Oily", title: "Oily") { n in
                    var r = n; r.f = n.f * 1.25; r.kcal = n.kcal + n.f * 0.25 * 9; return r
                }
            ]
        case .teaSugar:
            return [
                NutModifierOption(token: "No Sugar", title: "No Sugar") { $0 },
                NutModifierOption(token: "With Sugar", title: "With Sugar") { n in
                    var r = n; r.kcal = n.kcal + 32; r.c = n.c + 8; return r
                }
            ]
        case .milkType:
            // TODO: the backend gives no numbers for milk types. These ratios follow the prototype's example
            // values (whole 61 / semi-skimmed 46 / skimmed 34 kcal per 100 ml; fat 3.3 / 1.6 / 0.1 g).
            return [
                NutModifierOption(token: "Whole", title: "Whole") { $0 },
                NutModifierOption(token: "Semi-skimmed", title: "Semi-skimmed") { n in
                    var r = n; r.kcal = n.kcal * 0.75; r.f = n.f * 0.48; return r
                },
                NutModifierOption(token: "Skimmed", title: "Skimmed") { n in
                    var r = n; r.kcal = n.kcal * 0.56; r.f = n.f * 0.03; return r
                }
            ]
        }
    }

    /// `base` was delivered with option `initial` already included; moving to `selected` changes it by the difference.
    func adjust(_ n: NutNutrition, selected: Int, initial: Int) -> NutNutrition {
        let opts = options
        guard opts.indices.contains(selected), opts.indices.contains(initial) else { return n }
        let a = opts[selected].apply(n)
        let b = opts[initial].apply(n)
        return NutNutrition(
            kcal: max(0, n.kcal + a.kcal - b.kcal),
            p: max(0, n.p + a.p - b.p),
            c: max(0, n.c + a.c - b.c),
            f: max(0, n.f + a.f - b.f),
            fiber: n.fiber
        )
    }
}

/// One food in the meal tray. All portion scaling runs locally (no extra backend calls).
struct NutTrayItem: Identifiable {
    let id = UUID()
    var name: String
    var searchKey: String?
    var category: NutKind
    var baseGrams: Double
    /// Nutrition for `baseGrams`, as delivered.
    var base: NutNutrition
    var aiPortionLabel: String?
    var trust: NutTrust
    var confidence: Double?
    var alternatives: [String] = []
    var profile: NutModifierProfile?
    var initialModifier = 0
    var modifier = 0
    var plateSize = 1
    var pieceSize = 1
    var count = 1
    var ml = 250.0
    var portionTouched = false
    var expanded = false

    static let plateFactors: [Double] = [0.7, 1.0, 1.4]
    static let pieceFactors: [Double] = [0.85, 1.0, 1.15]
    static let plateTokens = ["Small", "Regular", "Large"]
    static let pieceTokens = ["Small", "Medium", "Large"]

    var grams: Double {
        switch category {
        case .drink: return ml
        case .piece: return baseGrams * Double(count) * Self.pieceFactors[pieceSize]
        case .plate: return baseGrams * Self.plateFactors[plateSize]
        }
    }

    var nutrition: NutNutrition {
        var n = base.scaled(baseGrams > 0 ? grams / baseGrams : 1)
        if let profile { n = profile.adjust(n, selected: modifier, initial: initialModifier) }
        return n
    }

    var needsReview: Bool { (confidence ?? 1) < 0.85 }

    var modifierLabel: String? { profile.map { $0.options[modifier].token } }

    private var useOwnLabel: Bool { portionTouched || (aiPortionLabel ?? "").isEmpty }

    /// English token stored with the meal (an edit can read it back).
    var portionLabelForSave: String {
        switch category {
        case .drink: return "\(Int(ml.rounded())) ml"
        case .piece: return useOwnLabel ? "\(count) × \(Self.pieceTokens[pieceSize])" : (aiPortionLabel ?? "")
        case .plate: return useOwnLabel ? Self.plateTokens[plateSize] : (aiPortionLabel ?? "")
        }
    }

    /// "~200 g" (or "250 ml" for a drink): the weight, written once.
    var weightText: String {
        let g = Int(grams.rounded())
        return category == .drink ? "\(g) ml" : "~\(g) g"
    }

    /// A label from the analysis, with any weight it already contains ("200g", "(~200 g)") removed.
    private func labelWithoutWeight(_ label: String) -> String {
        let stripped = label.replacingOccurrences(
            of: "[\\(\\[]?\\s*~?\\d+([.,]\\d+)?\\s*(g|gr|grams?|ml)\\b\\s*[\\)\\]]?",
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return stripped.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—,;:()[]"))
    }

    /// Localized summary for the collapsed card: "Regular · ~250 g". The weight appears once, never repeated.
    var portionSummary: String {
        func loc(_ token: String) -> String { String(localized: String.LocalizationValue(token)) }
        let label: String
        switch category {
        case .drink: return weightText
        case .piece: label = useOwnLabel ? "\(count) × \(loc(Self.pieceTokens[pieceSize]))" : labelWithoutWeight(aiPortionLabel ?? "")
        case .plate: label = useOwnLabel ? loc(Self.plateTokens[plateSize]) : labelWithoutWeight(aiPortionLabel ?? "")
        }
        return label.isEmpty ? weightText : "\(label) · \(weightText)"
    }

    var itemBody: MealItemBody {
        let n = nutrition
        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        return MealItemBody(
            name: name, searchKey: searchKey, category: category.rawValue, grams: r1(grams),
            portionLabel: portionLabelForSave.isEmpty ? nil : portionLabelForSave,
            modifierLabel: modifierLabel,
            calories: Int(n.kcal.rounded()), proteinG: r1(n.p), carbsG: r1(n.c), fatG: r1(n.f),
            fiberG: n.fiber > 0 ? r1(n.fiber) : nil,
            trustSource: trust.rawValue, confidence: confidence
        )
    }
}

enum NutTrayBuilder {
    static func item(from a: AnalyzedMealItem) -> NutTrayItem {
        let category = NutKind(rawValue: a.category ?? "") ?? .plate
        let grams = max(a.grams ?? 0, 1)
        let name = (a.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var item = NutTrayItem(
            name: name.isEmpty ? String(localized: "Food") : name,
            searchKey: a.searchKey,
            category: category,
            baseGrams: grams,
            base: NutNutrition(kcal: a.calories ?? 0, p: a.proteinG ?? 0, c: a.carbsG ?? 0, f: a.fatG ?? 0, fiber: a.fiberG ?? 0),
            aiPortionLabel: a.portionLabel,
            trust: NutTrust(raw: a.trustSource),
            confidence: a.confidence,
            alternatives: Array((a.alternatives ?? []).prefix(3))
        )
        if category == .drink { item.ml = grams }
        if let raw = a.modifierProfile, let profile = NutModifierProfile(rawValue: raw) {
            item.profile = profile
            let label = (a.modifierLabel ?? "").lowercased()
            let index = profile.options.firstIndex { !label.isEmpty && label.contains($0.token.lowercased()) } ?? profile.neutralIndex
            item.initialModifier = index
            item.modifier = index
        }
        return item
    }

    /// Barcode: per-100 g values scaled to the serving.
    static func item(from b: BarcodeMealItem) -> NutTrayItem? {
        let name = (b.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let serving = max(b.servingGrams ?? 100, 1)
        let k = serving / 100
        var item = NutTrayItem(
            name: name,
            searchKey: b.barcode,
            category: NutKind(rawValue: b.category ?? "") ?? .plate,
            baseGrams: serving,
            base: NutNutrition(kcal: (b.caloriesPer100g ?? 0) * k, p: (b.proteinPer100g ?? 0) * k, c: (b.carbsPer100g ?? 0) * k, f: (b.fatPer100g ?? 0) * k),
            aiPortionLabel: String(localized: "Serving"),
            trust: .verifiedLabel,
            confidence: nil
        )
        if item.category == .drink { item.ml = serving }
        return item
    }

    /// A food picked from the list ("+ Add missing item", or an alternative that exists locally).
    static func item(from f: FoodKnowledge, grams overrideGrams: Double? = nil) -> NutTrayItem {
        let category = NutKind.infer(name: f.name, keywords: f.keywords)
        let grams = overrideGrams ?? (category == .piece ? NutDraft.pieceBase : (category == .drink ? 250 : NutDraft.plateBase))
        let k = grams / 100
        var item = NutTrayItem(
            name: f.name,
            searchKey: f.name.lowercased(),
            category: category,
            baseGrams: grams,
            base: NutNutrition(kcal: Double(f.per100g.calories) * k, p: f.per100g.protein * k, c: f.per100g.carbs * k, f: f.per100g.fat * k),
            aiPortionLabel: nil,
            trust: .databaseMatch,
            confidence: nil
        )
        if category == .drink { item.ml = grams }
        return item
    }
}

private func nutTrayChip(_ title: Text, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        title
            .font(TTFont.workSans(14, weight: .medium))
            .foregroundStyle(on ? Color.white : TTColor.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(on ? Color.black : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(on ? Color.black : Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
}

private func nutTrayRoundButton(_ glyph: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(verbatim: glyph).font(TTFont.workSans(22, weight: .regular)).foregroundStyle(TTColor.ink)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(Color(red: 212 / 255, green: 212 / 255, blue: 216 / 255), lineWidth: 1))
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
}

/// One item card: collapsed by default, tap to adjust the portion.
struct NutTrayCard: View {
    @Binding var item: NutTrayItem
    let onRemove: () -> Void
    let onAlternative: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let n = item.nutrition
        let kcal = Int(n.kcal.rounded())
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { item.expanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: item.name)
                                .font(TTFont.workSans(16, weight: .semibold))
                                .foregroundStyle(TTColor.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(verbatim: item.portionSummary)
                                .font(TTFont.workSans(13, weight: .regular))
                                .foregroundStyle(NutStyle.mute)
                            Text(item.trust.title)
                                .font(TTFont.workSans(11, weight: .semibold))
                                .foregroundStyle(item.trust.tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(item.trust.tint.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(kcal) kcal")
                                .font(TTFont.workSans(15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(TTColor.ink)
                            if !item.expanded {
                                Text("Tap to adjust")
                                    .font(TTFont.workSans(11, weight: .regular))
                                    .foregroundStyle(NutStyle.mute)
                            }
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NutStyle.mute)
                            .rotationEffect(.degrees(item.expanded ? 180 : 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: item.expanded)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(item.name), \(item.portionSummary), \(kcal) kcal"))
                .accessibilityHint(Text("Adjust portion"))

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(NutStyle.mute)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(item.name)"))
            }

            if item.needsReview, !item.alternatives.isEmpty {
                NutFlow(spacing: 8) {
                    ForEach(item.alternatives, id: \.self) { alt in
                        nutTrayChip(Text("Not it?") + Text(verbatim: " \(alt)"), on: false) { onAlternative(alt) }
                    }
                }
            }

            if item.expanded { controls }
        }
        .padding(12)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(item.needsReview ? NutStyle.orange : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item.category {
            case .plate:
                NutFlow(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        nutTrayChip(
                            Text(LocalizedStringKey(NutTrayItem.plateTokens[i])) + Text(verbatim: " · " + String(format: "%.1f×", NutTrayItem.plateFactors[i])),
                            on: item.plateSize == i
                        ) { item.plateSize = i; item.portionTouched = true }
                    }
                }
            case .piece:
                HStack(spacing: 12) {
                    nutTrayRoundButton("−", label: "Fewer") { item.count = max(1, item.count - 1); item.portionTouched = true }
                    Text(verbatim: "\(item.count)")
                        .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                        .frame(minWidth: 64)
                    nutTrayRoundButton("+", label: "More") { item.count = min(6, item.count + 1); item.portionTouched = true }
                }
                NutFlow(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        nutTrayChip(Text(LocalizedStringKey(NutTrayItem.pieceTokens[i])), on: item.pieceSize == i) {
                            item.pieceSize = i; item.portionTouched = true
                        }
                    }
                }
            case .drink:
                NutFlow(spacing: 8) {
                    ForEach([("Glass", 250.0), ("Cup", 200.0), ("Bottle", 500.0)], id: \.0) { name, v in
                        nutTrayChip(Text(LocalizedStringKey(name)) + Text(verbatim: " \(Int(v))"), on: item.ml == v) {
                            item.ml = v; item.portionTouched = true
                        }
                    }
                }
                HStack(spacing: 12) {
                    nutTrayRoundButton("−", label: "Less") { item.ml = max(50, item.ml - 50); item.portionTouched = true }
                    Text(verbatim: "\(Int(item.ml)) ml")
                        .font(TTFont.workSans(20, weight: .semibold)).monospacedDigit()
                        .frame(minWidth: 96)
                    nutTrayRoundButton("+", label: "More") { item.ml = min(1000, item.ml + 50); item.portionTouched = true }
                }
            }

            if let profile = item.profile {
                NutFlow(spacing: 8) {
                    ForEach(Array(profile.options.enumerated()), id: \.offset) { i, option in
                        nutTrayChip(Text(option.title), on: item.modifier == i) { item.modifier = i }
                    }
                }
            }
        }
    }
}

/// Review screen: live totals, one card per food, status, time and save.
struct NutMealTrayContent: View {
    @Environment(AppStore.self) private var store
    let source: String
    let heroPhoto: UIImage?
    let close: (_ after: (() -> Void)?) -> Void
    let onSaved: (TTToastMessage) -> Void

    @State private var items: [NutTrayItem]
    @State private var status = "eaten"
    @State private var now: Date
    @State private var time: Date
    @State private var timeTouched = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var addingItem = false
    @State private var query = ""
    @State private var remote: FoodKnowledge?
    @State private var mealTag: String?
    @State private var showFix = false
    @State private var fixText = ""
    @State private var refining = false
    @State private var fixMessage: String?

    init(
        items: [NutTrayItem], mealTag: String?, source: String, heroPhoto: UIImage?,
        close: @escaping (_ after: (() -> Void)?) -> Void, onSaved: @escaping (TTToastMessage) -> Void
    ) {
        _items = State(initialValue: items)
        let opened = Date()
        _now = State(initialValue: opened)
        _time = State(initialValue: opened)
        _mealTag = State(initialValue: mealTag)
        self.source = source
        self.heroPhoto = heroPhoto
        self.close = close
        self.onSaved = onSaved
    }

    private var totals: NutNutrition {
        items.reduce(NutNutrition()) { acc, item in
            let n = item.nutrition
            return NutNutrition(kcal: acc.kcal + n.kcal, p: acc.p + n.p, c: acc.c + n.c, f: acc.f + n.f, fiber: acc.fiber + n.fiber)
        }
    }

    private var goal: Int { store.currentTrainee?.dailyCalorieTarget ?? 0 }

    private var eatenKcalToday: Int {
        guard let id = store.currentTrainee?.id else { return 0 }
        return store.meals(for: id, on: Date()).filter { !$0.isPlanned }.reduce(0) { $0 + $1.macros.calories }
    }

    private var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Review your meal")
                .font(TTFont.workSans(20, weight: .bold)).foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)

            summaryCard

            VStack(spacing: 10) {
                ForEach($items) { $item in
                    NutTrayCard(
                        item: $item,
                        onRemove: { remove(item.id) },
                        onAlternative: { alt in applyAlternative(item.id, alt) }
                    )
                }
            }
            .padding(.top, 12)

            if items.isEmpty {
                Text("Add an item to save this meal.")
                    .font(TTFont.body(14)).foregroundStyle(NutStyle.mute)
                    .padding(.top, 8)
            }

            addMissingItem

            HStack(spacing: 0) {
                seg("Ate it", on: status == "eaten") { setStatus("eaten") }
                seg("Plan it", on: status == "planned") { setStatus("planned") }
            }
            .padding(3)
            .background(NutStyle.track)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.top, 14).padding(.bottom, 6)

            HStack {
                Text(verbatim: (Calendar.current.isDate(time, equalTo: now, toGranularity: .minute) ? "\(String(localized: "Now")) · " : "")
                     + time.formatted(date: .omitted, time: .shortened))
                    .font(TTFont.workSans(16, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    nutTrayRoundButton("−", label: "15 minutes earlier") { shiftTime(-15) }
                    nutTrayRoundButton("+", label: "15 minutes later") { shiftTime(15) }
                }
            }
            .padding(.vertical, 6)

            if let errorText {
                Text(verbatim: errorText).font(TTFont.body(13)).foregroundStyle(NutStyle.danger).padding(.top, 4)
            }

            nutPanelButton(saving ? "Saving…" : "Save meal", style: .primary, loading: saving) { save() }
                .disabled(saving || items.isEmpty)
                .opacity(items.isEmpty ? 0.4 : 1)
                .padding(.top, 10)
            nutPanelButton("Cancel", style: .ghost) { close(nil) }
                .disabled(saving)
                .padding(.bottom, 12)
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let t = totals
        let kcal = Int(t.kcal.rounded())
        let left = goal - eatenKcalToday - kcal
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(kcal) kcal")
                    .font(TTFont.workSans(30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(TTColor.ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
                Spacer(minLength: 4)
                if let tag = mealTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
                    Text(verbatim: tag)
                        .font(TTFont.workSans(12, weight: .semibold))
                        .foregroundStyle(NutStyle.accentText)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(NutStyle.orange.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                macroCell("Protein", t.p)
                macroCell("Carbs", t.c)
                macroCell("Fat", t.f)
            }
            if goal > 0 {
                Text("\(max(0, left)) kcal left after this meal")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(left < 0 ? NutStyle.danger : NutStyle.mute)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func macroCell(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(TTFont.workSans(12, weight: .regular)).foregroundStyle(Color(white: 0.27))
            Text(verbatim: "\(value.formatted(.number.precision(.fractionLength(0...1)))) g")
                .font(TTFont.workSans(15, weight: .bold)).monospacedDigit().foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Add missing item

    private var results: [FoodKnowledge] {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var foods = store.foodCatalog
        if let remote, !foods.contains(where: { $0.name == remote.name }) { foods.insert(remote, at: 0) }
        guard !t.isEmpty else { return Array(foods.prefix(6)) }
        return foods.filter { f in
            f.name.lowercased().contains(t) || f.keywords.contains { $0.lowercased().contains(t) }
        }
    }

    private var addMissingItem: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    addingItem.toggle()
                    if addingItem { showFix = false }
                } label: {
                    Text("+ Add missing item")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(NutStyle.accentText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Button {
                    showFix.toggle()
                    if showFix { addingItem = false }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                        Text("Fix with AI").font(TTFont.workSans(15, weight: .semibold))
                    }
                    .foregroundStyle(NutStyle.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showFix ? .isSelected : [])
            }
            if addingItem { searchBlock }
            if showFix { fixBlock }
        }
        .padding(.top, 6)
    }

    private var searchBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search foods and drinks", text: $query)
                .font(TTFont.body(16))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255), lineWidth: 1.5))
                .onChange(of: query) { _, value in
                    remote = nil
                    let q = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else { return }
                    Task {
                        let found = await store.searchFood(query: q)
                        if query.trimmingCharacters(in: .whitespacesAndNewlines) == q { remote = found }
                    }
                }
            ForEach(results, id: \.name) { food in
                Button {
                    items.append(NutTrayBuilder.item(from: food))
                    addingItem = false; query = ""; remote = nil
                } label: {
                    HStack {
                        Text(verbatim: food.name).font(TTFont.workSans(15, weight: .semibold)).foregroundStyle(TTColor.ink)
                        Spacer(minLength: 4)
                        Text(verbatim: String(format: String(localized: "%lld kcal per 100 g"), food.per100g.calories))
                            .font(TTFont.workSans(12, weight: .regular)).foregroundStyle(NutStyle.mute)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    /// "Fix with AI": a short instruction, sent with the tray's current items.
    private var fixBlock: some View {
        let trimmed = fixText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("e.g. It's mutton not chicken, add 1 roti", text: $fixText, axis: .vertical)
                    .lineLimit(1...3)
                    .font(TTFont.body(15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(NutStyle.field)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(refining)
                    .accessibilityLabel(Text("Fix with AI"))
                Button { refine() } label: {
                    HStack(spacing: 6) {
                        if refining { ProgressView().tint(.white) }
                        Text("Update").font(TTFont.workSans(15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.black)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(refining || trimmed.isEmpty)
                .opacity(trimmed.isEmpty && !refining ? 0.4 : 1)
            }
            if let fixMessage {
                Text(verbatim: fixMessage)
                    .font(TTFont.body(13)).foregroundStyle(NutStyle.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    private func refine() {
        let instruction = fixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refining, !instruction.isEmpty else { return }
        refining = true
        fixMessage = nil
        let bodies = items.map(\.itemBody)
        let fallback = String(localized: "Couldn’t update right now — you can still edit items below.")
        Task {
            do {
                let response = try await store.refineMeal(items: bodies, instruction: instruction)
                let refined = (response.items ?? []).map { NutTrayBuilder.item(from: $0) }
                if (response.isFood ?? true), !refined.isEmpty {
                    // Only the items change: Ate it | Plan it and the chosen time stay as they are.
                    items = refined
                    if let tag = response.mealTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty { mealTag = tag }
                    fixText = ""
                    showFix = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    let message = (response.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    fixMessage = message.isEmpty ? fallback : message
                }
            } catch {
                fixMessage = fallback
            }
            refining = false
        }
    }

    // MARK: Actions

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// "Not it?" — rename, and use the local food list for numbers when there is a match (no backend call).
    private func applyAlternative(_ id: UUID, _ alt: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        item.name = alt
        item.searchKey = alt.lowercased()
        item.confidence = 1
        item.alternatives = []
        if let food = store.lookupFood(query: alt) {
            let grams = item.grams
            let k = grams / 100
            item.base = NutNutrition(kcal: Double(food.per100g.calories) * k, p: food.per100g.protein * k, c: food.per100g.carbs * k, f: food.per100g.fat * k)
            item.baseGrams = max(grams, 1)
            item.trust = .databaseMatch
            item.profile = nil
        }
        items[index] = item
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

    private func setStatus(_ newStatus: String) {
        status = newStatus
        if newStatus == "planned", time <= now { time = now.addingTimeInterval(78 * 60) }
        if newStatus == "eaten", time > now { time = now }
        if time > endOfDay { time = endOfDay }
        timeTouched = true
    }

    private func shiftTime(_ minutes: Int) {
        var t = time.addingTimeInterval(Double(minutes) * 60)
        if status == "eaten" { t = min(now, t) } else { t = min(endOfDay, max(now.addingTimeInterval(15 * 60), t)) }
        time = t
        timeTouched = true
    }

    private func save() {
        guard !saving, !items.isEmpty else { return }
        saving = true
        errorText = nil
        let t = totals
        func r1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
        let names = items.map(\.name).joined(separator: ", ")
        let name = names.count > 60 ? String(names.prefix(57)) + "…" : names
        // Same kind of text as manual entries ("~200 g", "250 ml"); several items: "3 items". The meal tag stays in the tray.
        let detail = items.count == 1
            ? items[0].weightText
            : String(format: String(localized: "%lld items"), items.count)
        let meal = Meal(
            id: UUID().uuidString,
            traineeId: store.currentTrainee?.id ?? "",
            name: name,
            eatenAt: time,
            portionGrams: max(1, items.reduce(0) { $0 + $1.grams }),
            macros: MacroEstimate(calories: Int(t.kcal.rounded()), protein: r1(t.p), carbs: r1(t.c), fat: r1(t.f)),
            source: source,
            isEstimate: items.contains { $0.trust != .verifiedLabel },
            status: status,
            kind: items.count == 1 ? items[0].category.rawValue : NutKind.plate.rawValue,
            detail: detail.isEmpty ? nil : detail
        )
        let bodies = items.map(\.itemBody)
        let hero = heroPhoto
        let sendTime = status == "planned" || timeTouched
        Task {
            do {
                // Uploads the first photo (if any), then saves the meal with its items; the Today list refreshes.
                try await store.saveMeal(meal, photo: hero, sendsEatenAt: sendTime, items: bodies)
                saving = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let timeText = time.formatted(date: .omitted, time: .shortened)
                let text = status == "planned"
                    ? String(format: String(localized: "%@ planned · %@"), name, timeText)
                    : String(format: String(localized: "%@ saved · %@"), name, timeText)
                close {
                    onSaved(TTToastMessage(text: text, style: .success))
                    UIAccessibility.post(notification: .announcement, argument: text)
                }
            } catch {
                // Everything stays as it is so the person can try again.
                saving = false
                errorText = error.localizedDescription.isEmpty ? String(localized: "Couldn’t save entry") : error.localizedDescription
            }
        }
    }
}
