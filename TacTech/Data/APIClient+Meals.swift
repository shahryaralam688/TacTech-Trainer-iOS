import Foundation

struct FoodLookupDTO: Codable {
    var name: String
    var keywords: [String]?
    var per100g: MacroEstimate

    func asFood() -> FoodKnowledge {
        FoodKnowledge(name: name, keywords: keywords ?? [], per100g: per100g)
    }
}

struct MealBody: Encodable {
    var name: String
    var eatenAt: Date?
    var portionGrams: Double
    var macros: MacroEstimate
    var source: String
    var isEstimate: Bool
    var mealType: String? = nil
    var notes: String? = nil
    var photoUrl: String? = nil
    var status: String? = nil
    var kind: String? = nil
    var detail: String? = nil
    var tz: String? = TimeZone.current.identifier
    /// Optional: the foods of a photo-analysed meal. Single-item callers leave it nil.
    var items: [MealItemBody]? = nil
}

/// PATCH /trainee/meals/{id}: only the fields that are set are sent.
struct UpdateMealBody: Encodable {
    var eatenAt: Date? = nil
    var portionGrams: Double? = nil
    var macros: MacroEstimate? = nil
    var status: String? = nil
    var kind: String? = nil
    var detail: String? = nil
    var tz: String? = TimeZone.current.identifier
}

struct UpdateTraineeGoalBody: Encodable {
    var dailyCalorieTarget: Int
}

struct MealPhotoUploadResponse: Decodable {
    var photoUrl: String
}

struct MealAnalyzeBody: Encodable {
    var photoUrl: String
    var tz: String? = TimeZone.current.identifier
}

struct MealAnalyzeAlternative: Decodable, Hashable {
    var name: String
    var kind: String?
    var portionGrams: Double?
    var macros: MacroEstimate?
}

/// One food found in the photos (`POST /trainee/meals/analyze`, multipart field `files`).
struct AnalyzedMealItem: Decodable, Hashable {
    var name: String?
    var searchKey: String?
    /// "plate" | "piece" | "drink"
    var category: String?
    var grams: Double?
    var portionLabel: String?
    var modifierLabel: String?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var fiberG: Double?
    /// "verified_label" | "database_match" | "ai_estimate"
    var trustSource: String?
    var confidence: Double?
    /// "curry_oil" | "tea_sugar" | "milk_type" | nil
    var modifierProfile: String?
    var alternatives: [String]?
    var suggestedModifiers: [String]?
}

struct MealPhotosAnalysis: Decodable {
    var isFood: Bool?
    var message: String?
    var mealTag: String?
    var items: [AnalyzedMealItem]?
}

/// `GET /trainee/meals/barcode/{code}` (`caloriesPer100g`, `proteinPer100g`, …, `barcode`) and
/// `POST /trainee/meals/parse-label` (`kcalPer100G`, `proteinPer100G`, …). Both spellings of every key decode.
struct BarcodeMealItem: Decodable, Hashable {
    var name: String?
    var caloriesPer100g: Double?
    var proteinPer100g: Double?
    var carbsPer100g: Double?
    var fatPer100g: Double?
    var servingGrams: Double?
    var category: String?
    var trustSource: String?
    var barcode: String?

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func double(_ names: [String]) -> Double? {
            for name in names {
                if let key = AnyKey(stringValue: name), let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
            }
            return nil
        }
        func string(_ names: [String]) -> String? {
            for name in names {
                if let key = AnyKey(stringValue: name), let value = try? c.decodeIfPresent(String.self, forKey: key) { return value }
            }
            return nil
        }
        name = string(["name"])
        caloriesPer100g = double(["caloriesPer100g", "caloriesPer100G", "kcalPer100g", "kcalPer100G"])
        proteinPer100g = double(["proteinPer100g", "proteinPer100G"])
        carbsPer100g = double(["carbsPer100g", "carbsPer100G"])
        fatPer100g = double(["fatPer100g", "fatPer100G"])
        servingGrams = double(["servingGrams"])
        category = string(["category"])
        trustSource = string(["trustSource"])
        barcode = string(["barcode"])
    }
}

struct BarcodeLookupResponse: Decodable {
    var found: Bool?
    var item: BarcodeMealItem?
}

/// `POST /trainee/meals/refine`: the tray as it is now, plus what the person wants changed.
/// TODO: the item keys are assumed to match `MealItemBody` (same as a saved meal's items).
typealias RefineMealItemBody = MealItemBody

struct RefineMealBody: Encodable {
    var items: [RefineMealItemBody]
    var instruction: String
}

struct ParseLabelBody: Encodable {
    var ocrText: String
    var productName: String?
}

/// `GET /trainee/meals/frequent`: meals eaten at least twice in the last 30 days.
struct FrequentMeal: Decodable, Identifiable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var count: Int?
    var calories: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var kind: String?
    var detail: String?
    var portionGrams: Double?
    /// The foods of the latest such meal (same keys as an analysed item).
    var mealItems: [AnalyzedMealItem]?
}

struct FrequentMealsResponse: Decodable {
    var items: [FrequentMeal]?
}

/// One item of a saved meal (`POST /trainee/meals` → `items`).
struct MealItemBody: Encodable {
    var name: String
    var searchKey: String?
    var category: String
    var grams: Double
    var portionLabel: String?
    var modifierLabel: String?
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var trustSource: String
    var confidence: Double?
}

struct MealAnalyzeResponse: Decodable {
    var name: String?
    var kind: String?
    var portionGrams: Double?
    var macros: MacroEstimate?
    var confidence: Double?
    var alternatives: [MealAnalyzeAlternative]?
}

struct MealSummaryBucket: Decodable, Identifiable, Hashable {
    var id: String { label + "-" + (title ?? "") }
    var label: String
    var title: String?
    var daysLogged: Int?
    var avgCalories: Int?
    var totalCalories: Int?
    var daysOverGoal: Int?
    var avgProtein: Double?
    var avgCarbs: Double?
    var avgFat: Double?
    var meals: [Meal]?
}

struct MealSummaryResponse: Decodable {
    var period: String?
    var goal: Int?
    var buckets: [MealSummaryBucket]?
}

extension APIClient {

    func trainerMeals(traineeId: String, on date: Date) async throws -> [Meal] {
        try await sendArray("/trainer/trainees/\(traineeId)/meals?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)")
    }

    func trainerMacros(traineeId: String, on date: Date) async throws -> MacroEstimate {
        try await send(path: "/trainer/trainees/\(traineeId)/macros?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)", method: .get)
    }

    func traineeMeals(on date: Date) async throws -> [Meal] {
        try await sendArray("/trainee/meals?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)")
    }

    /// Meals between two dates.
    func traineeMeals(from: Date, to: Date) async throws -> [Meal] {
        try await sendArray("/trainee/meals?from=\(APIConfig.dateQuery(from))&to=\(APIConfig.dateQuery(to))&tz=\(encodedTZ)")
    }

    func traineeMealSummary(period: String) async throws -> MealSummaryResponse {
        try await send(path: "/trainee/meals/summary?period=\(period)&tz=\(encodedTZ)", method: .get)
    }

    func createMeal(_ body: MealBody) async throws -> Meal? {
        try await sendOptional(path: "/trainee/meals", method: .post, body: body)
    }

    /// Multipart "file" (JPEG/PNG up to 5 MB) → `{photoUrl}`.
    func uploadMealPhoto(fileData: Data, filename: String = "meal.jpg", mimeType: String = "image/jpeg") async throws -> MealPhotoUploadResponse {
        try await sendMultipart(
            path: "/trainee/meals/photo",
            fields: [.file(name: "file", filename: filename, mimeType: mimeType, data: fileData)]
        )
    }

    /// 1–5 small JPEGs under the multipart field `files`.
    /// `hint` is an optional one-line note from the person (trimmed, at most 200 characters, omitted when empty).
    func analyzeMealPhotos(jpegs: [Data], hint: String? = nil) async throws -> MealPhotosAnalysis {
        var fields = jpegs.enumerated().map { index, data -> MultipartFormField in
            .file(name: "files", filename: "meal\(index + 1).jpg", mimeType: "image/jpeg", data: data)
        }
        let note = String((hint ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if !note.isEmpty { fields.append(.text(name: "hint", value: note)) }
        return try await sendMultipart(path: "/trainee/meals/analyze", fields: fields)
    }

    /// Returns the same shape as the photo analysis (`isFood`, `message`, `mealTag`, `items`).
    func refineMeal(_ body: RefineMealBody) async throws -> MealPhotosAnalysis {
        try await send(path: "/trainee/meals/refine", method: .post, body: body)
    }

    /// On-device OCR text of a nutrition label (10–3000 characters) → per-100 g values.
    func parseNutritionLabel(ocrText: String, productName: String? = nil) async throws -> BarcodeLookupResponse {
        let text = String(ocrText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3000))
        let name = productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await send(
            path: "/trainee/meals/parse-label", method: .post,
            body: ParseLabelBody(ocrText: text, productName: (name?.isEmpty == false) ? name : nil)
        )
    }

    func frequentMeals(limit: Int = 8) async throws -> [FrequentMeal] {
        let response: FrequentMealsResponse = try await send(path: "/trainee/meals/frequent?limit=\(limit)", method: .get)
        return response.items ?? []
    }

    func lookupBarcode(_ code: String) async throws -> BarcodeLookupResponse {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        return try await send(path: "/trainee/meals/barcode/\(encoded)", method: .get)
    }

    func analyzeMealPhoto(photoUrl: String) async throws -> MealAnalyzeResponse? {
        try await sendOptional(path: "/trainee/meals/analyze", method: .post, body: MealAnalyzeBody(photoUrl: photoUrl))
    }

    func updateMeal(id: String, body: UpdateMealBody) async throws -> Meal? {
        try await sendOptional(path: "/trainee/meals/\(id)", method: .patch, body: body)
    }

    /// PATCH /me/trainee (daily calorie target).
    func updateDailyCalorieTarget(_ value: Int) async throws -> TraineeProfile? {
        try await sendOptional(path: "/me/trainee", method: .patch, body: UpdateTraineeGoalBody(dailyCalorieTarget: value))
    }

    func deleteMeal(id: String) async throws {
        try await sendVoid(path: "/trainee/meals/\(id)", method: .delete, body: EmptyBody())
    }

    func traineeMacros(on date: Date) async throws -> MacroEstimate {
        try await send(path: "/trainee/macros?on=\(APIConfig.dateQuery(date))&tz=\(encodedTZ)", method: .get)
    }

    func lookupFood(query: String) async throws -> FoodKnowledge? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let path = "/food/lookup?q=\(encoded)"
        if let one = try? await send(path: path, method: .get) as FoodLookupDTO {
            return one.asFood()
        }
        let many: [FoodLookupDTO] = (try? await sendArray(path)) ?? []
        return many.first?.asFood()
    }
}
