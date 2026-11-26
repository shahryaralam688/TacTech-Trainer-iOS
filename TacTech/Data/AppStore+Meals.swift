import Foundation
import Observation
import UIKit

extension AppStore {

    /// Saves a meal. With a `photo`, it is resized (JPEG, longest side 1600 px, at most 5 MB) and uploaded first;
    /// the meal is then saved with the returned `photoUrl`. Any failure is thrown (nothing is saved on upload failure).
    func saveMeal(_ meal: Meal, photo: UIImage? = nil, sendsEatenAt: Bool = true, items: [MealItemBody]? = nil) async throws {
        var meal = meal
        var uploadedURL: String?
        if let photo {
            let jpeg = await Task.detached(priority: .userInitiated) {
                CoachImageEncoder.jpegData(from: photo)
            }.value
            guard let jpeg else {
                throw AppError.validation(String(localized: "Couldn’t prepare this photo."))
            }
            if jpeg.count > 5 * 1024 * 1024 {
                throw AppError.validation("Photo must be 5 MB or smaller.")
            }
            let response = try await api.uploadMealPhoto(fileData: jpeg)
            uploadedURL = response.photoUrl
            meal.photoUrl = response.photoUrl
        }
        let created = try await api.createMeal(
            MealBody(
                name: meal.name,
                // Without a time the server uses its own clock (an "eaten now" entry can't be "in the future").
                eatenAt: sendsEatenAt ? meal.eatenAt : nil,
                portionGrams: meal.portionGrams,
                macros: meal.macros,
                source: meal.source,
                isEstimate: meal.isEstimate,
                mealType: meal.mealType,
                notes: meal.notes,
                photoUrl: meal.photoUrl,
                status: meal.status,
                kind: meal.kind,
                detail: meal.detail,
                items: items
            )
        )
        if let photo, let uploadedURL, let key = TTMealPhoto.resolvedURL(uploadedURL) {
            Task { await TTRemoteImageCache.shared.store(photo, for: key) }
        }
        upsert(created ?? meal)
        Task { await refreshFrequentMeals() }
        if let trainee = currentTrainee {
            await refreshDay(for: trainee.id, on: meal.eatenAt)
        }
    }

    /// Sends 1–5 meal photos for AI analysis. Each image is re-drawn at most 1024 px on the long edge (this also drops
    /// EXIF/GPS) and compressed to roughly 150–250 KB, off the main actor. Throws on network/server errors.
    func analyzeMealPhotos(_ images: [UIImage], hint: String? = nil) async throws -> MealPhotosAnalysis {
        let jpegs = await Task.detached(priority: .userInitiated) {
            images.compactMap { AppStore.analysisJPEG($0) }
        }.value
        guard !jpegs.isEmpty else {
            throw AppError.validation(String(localized: "Couldn’t prepare this photo."))
        }
        return try await api.analyzeMealPhotos(jpegs: jpegs, hint: hint)
    }

    /// "Fix with AI": sends the tray's current items and the person's instruction; returns the updated items.
    func refineMeal(items: [MealItemBody], instruction: String) async throws -> MealPhotosAnalysis {
        try await api.refineMeal(RefineMealBody(items: items, instruction: instruction))
    }

    func parseNutritionLabel(ocrText: String, productName: String? = nil) async throws -> BarcodeLookupResponse {
        try await api.parseNutritionLabel(ocrText: ocrText, productName: productName)
    }

    /// Quiet refresh of the frequent-meals list (keeps the old list when the call fails).
    func refreshFrequentMeals(limit: Int = 8) async {
        guard session?.role == .trainee else { return }
        if let list = try? await api.frequentMeals(limit: limit) { frequentMeals = list }
    }

    func lookupBarcode(_ code: String) async throws -> BarcodeLookupResponse {
        try await api.lookupBarcode(code)
    }

    nonisolated static func analysisJPEG(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1024
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let factor = min(1, maxSide / longest)
        let target = CGSize(width: max(1, (size.width * factor).rounded()), height: max(1, (size.height * factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let redrawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        var quality: CGFloat = 0.7
        var data = redrawn.jpegData(compressionQuality: quality)
        while let current = data, current.count > 250 * 1024, quality > 0.35 {
            quality -= 0.1
            data = redrawn.jpegData(compressionQuality: quality)
        }
        return data
    }

    /// Fetches read-only meal summary (`GET /trainee/meals/summary?period=day|week|month&tz=...`).
    func fetchMealSummary(period: String) async -> MealSummaryResponse? {
        try? await api.traineeMealSummary(period: period)
    }

    /// Uploads a meal photo (`POST /trainee/meals/photo`) and runs AI analysis (`POST /trainee/meals/analyze`).
    /// If upload or analysis fails (or returns unclear/null), returns whatever succeeded without throwing.
    func uploadAndAnalyzeMealPhoto(_ photo: UIImage) async -> (photoUrl: String?, analysis: MealAnalyzeResponse?) {
        let jpeg = await Task.detached(priority: .userInitiated) {
            CoachImageEncoder.jpegData(from: photo)
        }.value
        guard let jpeg, jpeg.count <= 5 * 1024 * 1024 else {
            return (nil, nil)
        }
        guard let upload = try? await api.uploadMealPhoto(fileData: jpeg) else {
            return (nil, nil)
        }
        if let key = TTMealPhoto.resolvedURL(upload.photoUrl) {
            Task { await TTRemoteImageCache.shared.store(photo, for: key) }
        }
        let analysis = try? await api.analyzeMealPhoto(photoUrl: upload.photoUrl)
        return (upload.photoUrl, analysis)
    }

    /// Deletes one of the trainee's own meals (`DELETE /trainee/meals/{id}`). Throws on failure; the list is untouched then.
    func deleteMeal(_ meal: Meal) async throws {
        try await api.deleteMeal(id: meal.id)
        meals.removeAll { $0.id == meal.id }
        macrosByKey.removeValue(forKey: macroKey(meal.traineeId, on: meal.eatenAt))
    }

    /// PATCH /trainee/meals/{id}. Throws on failure; the local list is updated from the server's answer.
    @discardableResult
    func updateMeal(_ meal: Meal, changes: UpdateMealBody) async throws -> Meal {
        let updated = try await api.updateMeal(id: meal.id, body: changes)
        var local = meal
        if let updated {
            local = updated
        } else {
            if let v = changes.eatenAt { local.eatenAt = v }
            if let v = changes.portionGrams { local.portionGrams = v }
            if let v = changes.macros { local.macros = v }
            if let v = changes.status { local.status = v }
            if let v = changes.detail { local.detail = v }
        }
        upsert(local)
        macrosByKey.removeValue(forKey: macroKey(meal.traineeId, on: meal.eatenAt))
        macrosByKey.removeValue(forKey: macroKey(local.traineeId, on: local.eatenAt))
        return local
    }

    /// Saves the daily calorie goal on the server (PATCH /me/trainee) and updates the local profile.
    func saveDailyCalorieTarget(_ value: Int) async throws {
        let updated = try await api.updateDailyCalorieTarget(value)
        if var trainee = currentTrainee {
            trainee.dailyCalorieTarget = updated?.dailyCalorieTarget ?? value
            upsert(trainee)
        }
    }

    /// Local calorie goal update for the nutrition home slider.
    func updateDailyCalorieTarget(_ value: Int) {
        guard var trainee = currentTrainee else { return }
        trainee.dailyCalorieTarget = max(1200, min(value, 5000))
        upsert(trainee)
    }

    func meals(for traineeId: String, on date: Date) -> [Meal] {
        meals.filter { $0.traineeId == traineeId && Calendar.current.isDate($0.eatenAt, inSameDayAs: date) }
            .sorted { $0.eatenAt > $1.eatenAt }
    }

    func dailyMacros(for traineeId: String, on date: Date) -> MacroEstimate {
        if let cached = macrosByKey[macroKey(traineeId, on: date)] {
            return cached
        }
        // Planned entries (later today) are not eaten yet.
        return meals(for: traineeId, on: date).filter { !$0.isPlanned }.reduce(MacroEstimate(calories: 0, protein: 0, carbs: 0, fat: 0)) { partial, meal in
            MacroEstimate(
                calories: partial.calories + meal.macros.calories,
                protein: partial.protein + meal.macros.protein,
                carbs: partial.carbs + meal.macros.carbs,
                fat: partial.fat + meal.macros.fat
            )
        }
    }

    func lookupFood(query: String) -> FoodKnowledge? {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return nil }
        return foodCatalog.first { item in
            item.name.lowercased().contains(needle) || item.keywords.contains { $0.contains(needle) || needle.contains($0) }
        }
    }

    func searchFood(query: String) async -> FoodKnowledge? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return lookupFood(query: query) }
        if let remote = try? await api.lookupFood(query: query) {
            if !foodCatalog.contains(where: { $0.name == remote.name }) {
                foodCatalog.insert(remote, at: 0)
            }
            return remote
        }
        return lookupFood(query: query)
    }

    /// Returns whether the day's meals loaded (callers may ignore it). Errors are still swallowed as before.
    @discardableResult
    func refreshDay(for traineeId: String, on date: Date, failFast: Bool = false) async -> Bool {
        let api = failFast ? launchAPI : self.api
        do {
            if session?.role == .trainer {
                let remoteMeals = try await api.trainerMeals(traineeId: traineeId, on: date)
                replaceMeals(remoteMeals, traineeId: traineeId, on: date)
                if let macros = try? await api.trainerMacros(traineeId: traineeId, on: date) {
                    macrosByKey[macroKey(traineeId, on: date)] = macros
                }
            } else if currentTrainee?.id == traineeId {
                let cal = Calendar.current
                let dayStart = cal.startOfDay(for: date)
                let dayEnd = (cal.date(byAdding: .day, value: 1, to: dayStart) ?? date).addingTimeInterval(-0.001)
                let remoteMeals = try await api.traineeMeals(from: dayStart, to: dayEnd)
                replaceMeals(remoteMeals, traineeId: traineeId, window: dayStart...dayEnd)
                if let macros = try? await api.traineeMacros(on: date) {
                    macrosByKey[macroKey(traineeId, on: date)] = macros
                }
            }
            scheduleSaveOfflineSnapshot()
            return true
        } catch {
            if let error = error as? AppError, error == .unauthorized {
                clearLocalSession()
            }
            return false
        }
    }
}
