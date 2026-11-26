import Foundation
import Observation
import UIKit

extension AppStore {

    var isBoostActiveForSandow: Bool {
        myBoost?.active == true || entitlements?.boost.active == true
    }

    /// Chart bars from last loaded Sandow response (empty → zeros for current period).
    var sandowChartScores: [TTSandowDayScore] {
        if let sandowScore {
            return Self.mapSandowPoints(sandowScore.points)
        }
        return Self.zeroSandowScores(for: sandowPeriod)
    }

    /// Loads live Sandow Score. Prefers `GET /me/sandow-score`; falls back to local compose on 404.
    func loadSandowScore(period: SandowScorePeriod? = nil, force: Bool = false) async {
        let target = period ?? sandowPeriod
        if isLoadingSandowScore && !force { return }
        sandowPeriod = target
        isLoadingSandowScore = true
        defer { isLoadingSandowScore = false }

        do {
            let response = try await api.sandowScore(period: target.queryValue)
            sandowScore = response
            return
        } catch let error as AppError where error.isNotFound {
            sandowScore = await composeSandowScoreFallback(period: target)
        } catch let error as AppError where error == .unauthorized {
            // Keep last known; session clear handled elsewhere.
        } catch {
            // Keep previous points while offline; only seed zeros if never loaded.
            if sandowScore == nil {
                sandowScore = await composeSandowScoreFallback(period: target)
            }
        }
    }

    /// Local compose when `/me/sandow-score` is not shipped yet. Never invents random scores.
    func composeSandowScoreFallback(period: SandowScorePeriod) async -> SandowScoreResponse {
        if session?.role == .trainer {
            if isBoostActiveForSandow {
                return await composeTrainerBoostSandow(period: period)
            }
            return composeTrainerRosterSandow(period: period)
        }
        return composeTraineeWorkoutSandow(period: period)
    }

    /// @deprecated Prefer `loadSandowScore` / `sandowChartScores`. Real data only — zeros when empty.
    func weeklySandowScores(forTraineeId traineeId: String? = nil) -> [TTSandowDayScore] {
        let id = traineeId ?? currentTrainee?.id
        let response = composeTraineeWorkoutSandow(period: .week, traineeId: id)
        return Self.mapSandowPoints(response.points)
    }

    private func composeTraineeWorkoutSandow(
        period: SandowScorePeriod,
        traineeId: String? = nil
    ) -> SandowScoreResponse {
        let id = traineeId ?? currentTrainee?.id
        let reports = id.map { formReports(for: $0) } ?? []
        let logs = id.map { self.logs(for: $0) } ?? []
        let points = Self.buildDayPoints(period: period) { dayStart in
            let dayReports = reports.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: dayStart) }
            let dayLogs = logs.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: dayStart) }
            if !dayReports.isEmpty {
                let avg = dayReports.map(\.score).reduce(0, +) / max(dayReports.count, 1)
                return min(100, max(0, avg))
            }
            if !dayLogs.isEmpty {
                return min(100, max(0, 55 + dayLogs.count * 8 + min(dayLogs.map(\.durationMinutes).reduce(0, +) / 10, 20)))
            }
            return 0
        }
        let empty = !points.contains { $0.score > 0 }
        return SandowScoreResponse(
            role: "trainee",
            mode: "workout_performance",
            period: period.queryValue,
            title: "TacTech Score",
            subtitle: "Workout & form performance",
            summaryScore: points.map(\.score).max(),
            emptyCaption: empty ? "Log workouts to build your score" : nil,
            points: points
        )
    }

    private func composeTrainerRosterSandow(period: SandowScorePeriod) -> SandowScoreResponse {
        let clients = currentTrainer.map { trainees(for: $0) } ?? []
        let allLogs = clients.flatMap { logs(for: $0.id) }
        let allReports = clients.flatMap { formReports(for: $0.id) }
        let points = Self.buildDayPoints(period: period) { dayStart in
            let dayReports = allReports.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: dayStart) }
            let dayLogs = allLogs.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: dayStart) }
            if !dayReports.isEmpty {
                let avg = dayReports.map(\.score).reduce(0, +) / max(dayReports.count, 1)
                return min(100, max(0, avg))
            }
            if !dayLogs.isEmpty {
                return min(100, max(0, 50 + dayLogs.count * 6))
            }
            return 0
        }
        let empty = !points.contains { $0.score > 0 }
        return SandowScoreResponse(
            role: "trainer",
            mode: "roster_performance",
            period: period.queryValue,
            title: "TacTech Score",
            subtitle: "Clients performance",
            summaryScore: points.map(\.score).max(),
            boostActive: false,
            traineeCount: clients.count,
            emptyCaption: empty ? "No client activity yet" : nil,
            points: points
        )
    }

    private func composeTrainerBoostSandow(period: SandowScorePeriod) async -> SandowScoreResponse {
        let days = period.dayCount
        do {
            let analytics = try await api.fetchCoachAnalytics(periodDays: days)
            let series = analytics.series ?? []
            let points: [SandowScorePoint]
            if series.isEmpty {
                points = Self.buildDayPoints(period: period) { _ in 0 }
            } else {
                let maxRaw = max(series.map { $0.views + $0.impressions + $0.contacts * 3 }.max() ?? 1, 1)
                points = series.map { day in
                    let raw = day.views + day.impressions + day.contacts * 3
                    let score = Int((Double(raw) / Double(maxRaw) * 100).rounded())
                    let label = Self.shortLabel(forDateKey: day.date, period: period)
                    return SandowScorePoint(
                        date: day.date,
                        label: label,
                        score: min(100, max(0, score)),
                        views: day.views,
                        impressions: day.impressions,
                        contacts: day.contacts
                    )
                }
            }
            let empty = !points.contains { $0.score > 0 }
            return SandowScoreResponse(
                role: "trainer",
                mode: "boost_analytics",
                period: period.queryValue,
                title: "TacTech Score",
                subtitle: "Boost reach",
                summaryScore: points.map(\.score).max(),
                boostActive: true,
                traineeCount: currentTrainer.map { trainees(for: $0).count },
                emptyCaption: empty ? "Boost to see reach" : nil,
                points: points
            )
        } catch {
            let points = Self.buildDayPoints(period: period) { _ in 0 }
            return SandowScoreResponse(
                role: "trainer",
                mode: "boost_analytics",
                period: period.queryValue,
                title: "TacTech Score",
                subtitle: "Boost reach",
                boostActive: true,
                emptyCaption: "Boost to see reach",
                points: points
            )
        }
    }

    private static func buildDayPoints(
        period: SandowScorePeriod,
        scoreForDay: (Date) -> Int
    ) -> [SandowScorePoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dates: [Date]
        switch period {
        case .week:
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))
                ?? today
            dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            dates = (0..<30).reversed().compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today)
            }
        }

        let formatter = Self.sandowLocalDayFormatter

        return dates.map { day in
            let key = formatter.string(from: day)
            let label = shortLabel(forDateKey: key, period: period, date: day)
            return SandowScorePoint(date: key, label: label, score: scoreForDay(day))
        }
    }

    private static let sandowLocalDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let sandowGregorianDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func shortLabel(forDateKey key: String, period: SandowScorePeriod, date: Date? = nil) -> String {
        let calendar = Calendar.current
        let resolved = date ?? sandowLocalDayFormatter.date(from: key) ?? Date()
        switch period {
        case .week:
            return Weekday.from(date: resolved).short
        case .month:
            return "\(calendar.component(.day, from: resolved))"
        }
    }

    private static func mapSandowPoints(_ points: [SandowScorePoint]) -> [TTSandowDayScore] {
        points.map { point in
            let weekday: Weekday? = {
                if let date = sandowGregorianDayFormatter.date(from: point.date) {
                    return Weekday.from(date: date)
                }
                let lower = point.label.lowercased()
                return Weekday.allCases.first {
                    $0.short.lowercased() == lower || $0.rawValue == lower
                }
            }()
            return TTSandowDayScore(
                id: point.id,
                label: point.label.isEmpty ? (weekday?.short ?? point.date) : point.label,
                score: max(0, min(100, point.score)),
                weekday: weekday,
                dateKey: point.date.isEmpty ? nil : point.date
            )
        }
    }

    private static func zeroSandowScores(for period: SandowScorePeriod) -> [TTSandowDayScore] {
        mapSandowPoints(buildDayPoints(period: period) { _ in 0 })
    }

    /// Loads `/me/entitlements`. Failures are silent — never blocks workspace or AI.
    func refreshEntitlements() async {
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            entitlements = try await api.entitlements()
        } catch let error as AppError where error == .unauthorized {
            // Session clear is handled by callers of authenticated workspace loads.
            entitlements = nil
        } catch {
            // Keep last known value; Phase 1 treats missing as inactive.
        }
    }

    /// Loads `/me/ai` (+ mirrors into entitlements.ai when possible). Silent on failure.
    func refreshAIEntitlements() async {
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            let me = try await api.myAI()
            aiEntitlement = me
            // Keep entitlements.ai in sync when we already have a payload.
            if var ents = entitlements {
                ents.ai = EntitlementSlice(
                    active: me.active,
                    plan: me.plan,
                    tier: nil,
                    startsAt: me.startsAt,
                    endsAt: me.endsAt,
                    source: me.source
                )
                entitlements = ents
            } else {
                await refreshEntitlements()
            }
        } catch let error as AppError where error == .unauthorized {
            aiEntitlement = nil
        } catch {
            // Keep last known.
        }
    }

    /// Loads `GET /coach/ai/capabilities` into `aiCapabilities`. Silent on failure.
    func refreshAICapabilities() async {
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            aiCapabilities = try await api.aiCapabilities()
        } catch let error as AppError where error == .unauthorized {
            // Keep fallback.
        } catch {
            // Keep last known / fallback.
        }
    }

    func refreshAfterAIChat() async {
        if session?.role == .trainer {
            plans = (try? await api.trainerPlans()) ?? plans
            let items = (try? await api.trainerTrainees()) ?? []
            if !items.isEmpty { apply(traineeItems: items) }
            await fetchTrainerJoinRequests()
        } else if session?.role == .trainee {
            await refreshAssignedPlanForCurrentTrainee()
        }
    }

    /// Solo trainee: `POST /coach/programs/generate` → upsert assigned plan.
    /// Syncs fitness assessment first so the week matches goals / limits / days.
    /// Returns the plan on success. Throws `aiRequired` / `conflict` / others for UI handling.
    @discardableResult
    func generateAIProgram(horizonDays: Int = 7, notes: String? = nil) async throws -> WorkoutPlan {
        guard session?.role == .trainee, let trainee = currentTrainee else {
            throw AppError.validation("Only trainees can generate an AI week.")
        }
        if trainee.trainerId != nil {
            throw AppError.conflict("You already have a trainer. Use their assigned plan.")
        }

        let assessment = loadSavedFitnessAssessment()
        if assessment == nil && !assessmentCompleted {
            throw AppError.validation("Complete your fitness assessment before generating a week.")
        }

        // Push latest local assessment so backend generate can load it.
        let assessmentBody = assessment.map(AssessmentBody.init)
        if let assessment, let assessmentBody {
            do {
                try await api.submitAssessment(assessmentBody)
                persistAssessment(assessment)
                if var t = currentTrainee {
                    t.goal = assessment.goal
                    t.weightKg = assessment.weightKg
                    t.dailyCalorieTarget = assessment.calorieGoal
                    upsert(t)
                }
                markAssessmentCompleted()
                scheduleCoachMemorySync(force: true)
            } catch {
                // Still send assessment on generate body / notes if sync POST fails.
            }
        }

        let contextNotes = assessment.map(Self.assessmentGenerateNotes)
        let mergedNotes = [notes, contextNotes]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let resolvedHorizon: Int = {
            if let days = assessment?.daysPerWeek, days > 0 {
                return max(horizonDays, min(7, days))
            }
            return horizonDays
        }()

        var plan = try await api.generateAIProgram(
            horizonDays: resolvedHorizon,
            notes: mergedNotes.isEmpty ? nil : mergedNotes,
            assessment: assessmentBody
        )
        if (plan.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            plan.source = "ai"
        }
        upsert(plan)
        assignments.removeAll { $0.traineeId == trainee.id }
        assignments.append(
            PlanAssignment(id: UUID().uuidString, planId: plan.id, traineeId: trainee.id, assignedAt: .now)
        )
        planChangeNotice = "AI week ready"
        return plan
    }

    func loadSavedFitnessAssessment() -> FitnessAssessment? {
        guard let userId = session?.userId,
              let data = UserDefaults.standard.data(forKey: "assessment.payload.\(userId)"),
              let draft = try? JSONDecoder().decode(FitnessAssessment.self, from: data)
        else { return nil }
        return draft
    }

    /// Compact assessment context for generate `notes` (backend + LLM).
    private static func assessmentGenerateNotes(_ a: FitnessAssessment) -> String {
        var parts: [String] = ["Use my fitness assessment"]
        if !a.goal.isEmpty { parts.append("goal \(a.goal)") }
        if !a.gender.isEmpty { parts.append("gender \(a.gender)") }
        parts.append("age \(a.age)")
        parts.append("height \(Int(a.heightCm.rounded())) cm")
        parts.append("weight \(a.weightKg.cleanKg) kg")
        if a.hasTargetWeight == true {
            parts.append("target weight \(a.targetWeightKg.cleanKg) kg")
        } else if a.hasTargetWeight == false {
            parts.append("no target weight")
        }
        if let bmi = a.bmi {
            parts.append("BMI \(String(format: "%.1f", bmi))\(a.bmiCategory.map { " (\($0))" } ?? "")")
        }
        if !a.experienceLevel.isEmpty {
            parts.append("experience \(a.experienceLevel)")
        } else if let exp = a.hasExperience {
            parts.append(exp ? "has training experience" : "beginner / little experience")
        }
        parts.append("fitness level \(a.fitnessLevel)/5")
        if !a.activityLevel.isEmpty { parts.append("daily activity: \(a.activityLevel)") }
        if !a.workoutLocation.isEmpty { parts.append("works out: \(a.workoutLocation)") }
        if !a.equipment.isEmpty {
            parts.append("equipment: \(a.equipment.joined(separator: ", "))")
        }
        parts.append("\(a.daysPerWeek) days/week")
        if !a.workoutDuration.isEmpty { parts.append("time per session: \(a.workoutDuration)") }
        if !a.exercisePreferences.isEmpty {
            parts.append("prefers: \(a.exercisePreferences.joined(separator: ", "))")
        }
        if !a.limitations.isEmpty {
            parts.append("limitations: \(a.limitations.joined(separator: ", "))")
        }
        if !a.diet.isEmpty { parts.append("diet \(a.diet)") }
        if !a.supplementFrequency.isEmpty {
            parts.append("supplements: \(a.supplementFrequency)")
        }
        if !a.supplements.isEmpty {
            parts.append("takes: \(a.supplements.joined(separator: ", "))")
        }
        if !a.sleepHours.isEmpty {
            parts.append("sleep \(a.sleepHours)")
        } else if !a.sleepQuality.isEmpty {
            parts.append("sleep \(a.sleepQuality)")
        }
        if !a.waterIntake.isEmpty { parts.append("water \(a.waterIntake)") }
        if !a.improvementAreas.isEmpty {
            parts.append("wants to improve: \(a.improvementAreas.joined(separator: ", "))")
        }
        parts.append("calorie target \(a.calorieGoal)")
        if !a.concerns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("concerns: \(a.concerns)")
        }
        return parts.joined(separator: "; ")
    }

    /// Trainee may Edit/Delete only AI-sourced plans while solo (no linked trainer).
    func traineeCanEditDeleteAIPlan(_ plan: WorkoutPlan) -> Bool {
        session?.role == .trainee
            && !hasLinkedTrainer
            && plan.isAISource
    }

    /// `PATCH /trainee/ai-plans/{id}` — never hits trainer plan routes.
    func updateAIPlan(_ draft: WorkoutPlan) async throws {
        guard session?.role == .trainee else {
            throw AppError.validation("Only trainees can edit AI plans.")
        }
        guard traineeCanEditDeleteAIPlan(draft) else {
            throw AppError.forbidden("This plan was assigned by your trainer and can’t be edited.")
        }
        var payload = draft
        payload.source = "ai"
        let updated = try await api.updateTraineeAIPlan(id: draft.id, PlanBody(plan: payload))
        if var updated {
            if updated.days.isEmpty { updated.days = draft.days }
            if updated.notes == nil { updated.notes = draft.notes }
            if (updated.source ?? "").isEmpty { updated.source = "ai" }
            upsert(updated)
        } else {
            upsert(payload)
        }
        planChangeNotice = "Plan updated"
    }

    /// `DELETE /trainee/ai-plans/{id}` → clear local assignment so Generate card returns.
    func deleteAIPlan(id: String) async throws {
        guard session?.role == .trainee, let trainee = currentTrainee else {
            throw AppError.validation("Only trainees can delete AI plans.")
        }
        if let plan = plans.first(where: { $0.id == id }), !traineeCanEditDeleteAIPlan(plan) {
            throw AppError.forbidden("This plan was assigned by your trainer and can’t be deleted.")
        }
        try await api.deleteTraineeAIPlan(id: id)
        plans.removeAll { $0.id == id }
        assignments.removeAll { $0.traineeId == trainee.id && $0.planId == id }
        planChangeNotice = "AI plan removed"
    }

    var hasLinkedTrainer: Bool {
        currentTrainee?.trainerId != nil
    }

    var canShowSoloAIGenerate: Bool {
        session?.role == .trainee
            && !hasLinkedTrainer
            && aiCapabilities.structuredPlanJson
            && currentTrainee.flatMap({ assignedPlan(for: $0) }) == nil
    }

    /// Presents AI paywall for trainee and trainer. Returns true if presented / already showing.
    @discardableResult
    func presentAIPaywallIfNeeded(for error: Error) -> Bool {
        guard let app = error as? AppError, app.isAIRequired else { return false }
        guard session != nil else { return false }
        guard !showAIPaywall else { return true }
        showAIPaywall = true
        return true
    }

    /// Present AI paywall from Unlock CTA (both roles).
    func presentAIPaywall() {
        guard session != nil else { return }
        guard !showAIPaywall else { return }
        showAIPaywall = true
    }

    func dismissAIPaywall(unlocked: Bool) {
        showAIPaywall = false
        if unlocked {
            NotificationCenter.default.post(name: .ttAIPaywallUnlocked, object: nil)
        }
    }

    /// Loads trainer Boost status. Silent for non-trainers / failures.
    func refreshMyBoost() async {
        guard session?.role == .trainer else {
            myBoost = nil
            return
        }
        guard TokenStore.accessToken() != nil || TokenStore.refreshToken() != nil else { return }
        do {
            myBoost = try await api.myBoost()
        } catch let error as AppError where error == .unauthorized {
            myBoost = nil
        } catch {
            // Keep last known value.
        }
    }

    /// Trainee contacts a public coach — opens existing human chat via `ttOpenHumanChat`.
    @discardableResult
    func contactCoach(profileId: String, message: String? = nil) async throws -> CoachContactResponse {
        guard session?.role == .trainee else {
            throw AppError.validation("Only trainees can contact coaches.")
        }
        let response = try await api.contactCoach(id: profileId, message: message)
        NotificationCenter.default.post(
            name: .ttOpenHumanChat,
            object: nil,
            userInfo: ["threadId": response.threadId]
        )
        return response
    }

    /// Trainee inquires about a coach package — opens human chat with package context.
    @discardableResult
    func inquireCoachPackage(
        coachProfileId: String,
        packageId: String,
        message: String? = nil
    ) async throws -> PackageInquireResponse {
        guard session?.role == .trainee else {
            throw AppError.validation("Only trainees can inquire about packages.")
        }
        let response = try await api.inquireCoachPackage(
            coachProfileId: coachProfileId,
            packageId: packageId,
            message: message
        )
        NotificationCenter.default.post(
            name: .ttOpenHumanChat,
            object: nil,
            userInfo: ["threadId": response.threadId]
        )
        return response
    }

    enum BoostPurchaseResult: Equatable {
        case confirmed(MeBoostDTO)
        case canceled
        case stillPending
    }

    struct BoostPurchaseOutcome: Equatable {
        var result: BoostPurchaseResult
        /// Soft publish warning from checkout response (non-blocking).
        var warning: String?
    }

    private static let pendingBoostDefaultsKey = "tactech.pendingBoostCheckout"

    /// Creates Boost checkout (Stripe or local wallet), presents pay URL, confirms on return.
    func purchaseBoost(productId: String, provider: String?) async throws -> BoostPurchaseOutcome {
        guard session?.role == .trainer else {
            throw AppError.validation("Only trainers can purchase Boost.")
        }
        let checkout = try await api.createBoostCheckout(productId: productId, provider: provider)
        rememberPendingBoost(from: checkout)
        let trimmedWarning = checkout.warning?.trimmingCharacters(in: .whitespacesAndNewlines)
        let warning = (trimmedWarning?.isEmpty == false) ? trimmedWarning : nil
        guard let url = URL(string: checkout.url) else {
            throw AppError.api("Invalid checkout URL.")
        }

        do {
            let callback = try await BoostCheckoutPresenter.shared.present(checkoutURL: url)
            let result = try await finalizeBoostCallback(callback)
            return BoostPurchaseOutcome(result: result, warning: warning)
        } catch let error as BoostCheckoutPresenter.PresentError where error == .canceled {
            clearPendingBoost()
            return BoostPurchaseOutcome(result: .canceled, warning: warning)
        }
    }

    /// Handles `tactech://billing/boost/…` from `onOpenURL` (Safari / cold start).
    @discardableResult
    func handleOpenURL(_ url: URL) async -> Bool {
        if pendingBoostCheckout == nil {
            restorePendingBoostFromDisk()
        }
        guard let outcome = BoostBillingURL.parse(url) else { return false }
        switch outcome {
        case .cancel:
            clearPendingBoost()
            NotificationCenter.default.post(name: .ttBoostCheckoutCanceled, object: nil)
            return true
        case .stripeSuccess(let sessionId):
            do {
                _ = try await confirmBoostCheckout(
                    checkoutSessionId: sessionId,
                    attemptId: nil,
                    provider: pendingBoostCheckout?.provider ?? "stripe",
                    retryIfInactive: true
                )
                NotificationCenter.default.post(name: .ttBoostCheckoutSucceeded, object: nil)
                NotificationCenter.default.post(name: .ttSandowScoreShouldRefresh, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .ttBoostCheckoutFailed,
                    object: nil,
                    userInfo: ["detail": error.localizedDescription]
                )
            }
            return true
        case .localSuccess(let attemptId):
            do {
                let provider = pendingBoostCheckout?.provider
                _ = try await confirmBoostCheckout(
                    checkoutSessionId: nil,
                    attemptId: attemptId,
                    provider: provider,
                    retryIfInactive: true
                )
                NotificationCenter.default.post(name: .ttBoostCheckoutSucceeded, object: nil)
                NotificationCenter.default.post(name: .ttSandowScoreShouldRefresh, object: nil)
            } catch {
                NotificationCenter.default.post(
                    name: .ttBoostCheckoutFailed,
                    object: nil,
                    userInfo: ["detail": error.localizedDescription]
                )
            }
            return true
        }
    }

    private func finalizeBoostCallback(_ url: URL) async throws -> BoostPurchaseResult {
        guard let outcome = BoostBillingURL.parse(url) else {
            if let pending = pendingBoostCheckout, pending.hasIdentity {
                let boost = try await confirmBoostCheckout(
                    checkoutSessionId: pending.checkoutSessionId,
                    attemptId: pending.attemptId,
                    provider: pending.provider,
                    retryIfInactive: true
                )
                return boost.active ? .confirmed(boost) : .stillPending
            }
            throw AppError.api("Unexpected checkout return.")
        }
        switch outcome {
        case .cancel:
            clearPendingBoost()
            return .canceled
        case .stripeSuccess(let sessionId):
            let boost = try await confirmBoostCheckout(
                checkoutSessionId: sessionId,
                attemptId: nil,
                provider: pendingBoostCheckout?.provider ?? "stripe",
                retryIfInactive: true
            )
            return boost.active ? .confirmed(boost) : .stillPending
        case .localSuccess(let attemptId):
            let boost = try await confirmBoostCheckout(
                checkoutSessionId: nil,
                attemptId: attemptId,
                provider: pendingBoostCheckout?.provider,
                retryIfInactive: true
            )
            return boost.active ? .confirmed(boost) : .stillPending
        }
    }

    /// Confirms Stripe session or local wallet attempt; retries when IPN lags.
    @discardableResult
    func confirmBoostCheckout(
        checkoutSessionId: String? = nil,
        attemptId: String? = nil,
        provider: String? = nil,
        retryIfInactive: Bool = false
    ) async throws -> MeBoostDTO {
        // Legacy call site: `confirmBoostCheckout(sessionId:)`.
        let session = checkoutSessionId
        let attempt = attemptId
        let prov = provider ?? pendingBoostCheckout?.provider

        var lastError: Error?
        let attempts = retryIfInactive ? 3 : 1
        for i in 0..<attempts {
            if i > 0 {
                try? await Task.sleep(for: .milliseconds(900 + i * 300))
            }
            do {
                let boost = try await api.confirmBoostCheckout(
                    checkoutSessionId: session,
                    attemptId: attempt,
                    provider: prov
                )
                myBoost = boost
                if boost.active {
                    clearPendingBoost()
                    await refreshEntitlements()
                    await refreshMyBoost()
                    return myBoost ?? boost
                }
                // Inactive — IPN may still be in flight; keep pending and retry.
                lastError = AppError.api("Boost payment is still processing.")
            } catch {
                lastError = error
                await refreshMyBoost()
                await refreshEntitlements()
                if let boost = myBoost, boost.active {
                    clearPendingBoost()
                    return boost
                }
            }
        }

        await refreshMyBoost()
        await refreshEntitlements()
        if let boost = myBoost, boost.active {
            clearPendingBoost()
            return boost
        }
        throw lastError ?? AppError.api("Could not confirm Boost.")
    }

    /// Compatibility wrapper for Phase 2 Stripe-only call sites.
    @discardableResult
    func confirmBoostCheckout(sessionId: String) async throws -> MeBoostDTO {
        try await confirmBoostCheckout(
            checkoutSessionId: sessionId,
            attemptId: nil,
            provider: "stripe",
            retryIfInactive: true
        )
    }

    func rememberPendingBoost(from checkout: BoostCheckoutResponse) {
        pendingBoostCheckout = PendingBoostCheckout(
            checkoutSessionId: checkout.checkoutSessionId,
            attemptId: checkout.attemptId,
            provider: checkout.provider?.lowercased()
        )
    }

    func clearPendingBoost() {
        pendingBoostCheckout = nil
    }

    func restorePendingBoostFromDisk() {
        pendingBoostCheckout = Self.loadPendingBoost()
    }

    static func persistPendingBoost(_ value: PendingBoostCheckout?) {
        if let value, value.hasIdentity,
           let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: pendingBoostDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingBoostDefaultsKey)
        }
    }

    static func loadPendingBoost() -> PendingBoostCheckout? {
        guard let data = UserDefaults.standard.data(forKey: pendingBoostDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(PendingBoostCheckout.self, from: data)
    }
}
