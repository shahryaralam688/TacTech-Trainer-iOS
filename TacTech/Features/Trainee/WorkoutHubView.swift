import SwiftUI

// MARK: - Trainee Workout Hub (Sandow / TacTech system design)

struct WorkoutHubView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When presented as a sheet from Home, show a back control.
    var showsCloseChrome: Bool = false

    @State private var selectedDay = Date()
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()
    @State private var showEditAIPlan = false
    @State private var showDeleteAIConfirm = false
    @State private var isMutatingAIPlan = false
    @State private var hubToast: TTToastMessage?
    @State private var editingPlan: WorkoutPlan?
    @State private var showAssessmentReview = false

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = TTColor.actionOrange
    private let scrollSpace = "traineeWorkout"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TTHomeScrollCollapseProbe(model: scrollCollapse, space: scrollSpace)

                        VStack(alignment: .leading, spacing: 14) {
                            if let notice = store.planChangeNotice {
                                planChangeNoticeChip(notice)
                            }
                            if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
                                planOverviewCard(plan)
                                TTHomeWeekDatePicker(selected: $selectedDay, accent: orange,
                                                    sessionDayKeys: sessionDayKeySet(plan))
                                sessionHero(plan)
                                sessionDetail(plan)
                                liveFormCard(plan)
                            } else {
                                emptyCard
                            }
                        }
                        .padding(.horizontal, TTSpace.screen)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                }
                .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
                .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
                .refreshable {
                    await store.refreshAssignedPlanForCurrentTrainee()
                }
            }
            .background(charcoal.ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .ttSyncRootTabBarWithNavigationDepth()
            .ttToast($hubToast, bottomInset: 28)
            .task {
                await store.refreshAssignedPlanForCurrentTrainee()
            }
            .sheet(isPresented: $showEditAIPlan) {
                if let editingPlan {
                    CreatePlanView(editingPlan: editingPlan)
                        .ttModalSheetPresentation()
                }
            }
            .confirmationDialog(
                "Delete this AI plan?",
                isPresented: $showDeleteAIConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete plan", role: .destructive) {
                    Task { await deleteAIPlan() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your AI week. You can generate a new one anytime.")
            }
            .sheet(isPresented: $showAssessmentReview) {
                AssessmentReviewSheet(assessment: store.loadSavedFitnessAssessment()) {
                    hubToast = TTToastMessage(text: "AI week ready", style: .success)
                }
                .ttModalSheetPresentation()
            }
        }
    }

    private func planChangeNoticeChip(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(orange)
            Text(text)
                .font(TTFont.workSans(13, weight: .semibold))
                .foregroundStyle(TTColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                store.planChangeNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TTColor.inkSubtle)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if showsCloseChrome {
            TTDarkPageHeader(
                title: "Workout",
                collapseProgress: scrollCollapse.progress
            ) {
                dismiss()
            }
        } else {
            workoutTabHeader
        }
    }

    private var headerSubtitle: String {
        if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
            return plan.scheduleLine
        }
        return "Follow the plan"
    }

    private var workoutTabHeader: some View {
        let p = min(1, max(0, scrollCollapse.progress))
        let expand = 1 - p
        let compactHeight: CGFloat = 64
        let headerHeight = compactHeight + (TTDarkPageHeader.cardHeight - compactHeight) * expand

        return VStack(alignment: .leading, spacing: 10 * expand) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4 * expand) {
                    Text("Workout")
                        .font(TTFont.workSans(28 - 8 * p, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(headerSubtitle)
                        .font(TTFont.textSM(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .opacity(Double(expand))
                        .frame(height: 18 * expand, alignment: .top)
                        .clipped()
                }

                Spacer(minLength: 8)

                if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
                    NavigationLink {
                        LiveFormCorrectionView(
                            initialExerciseId: currentExercises(in: plan).first?.exerciseId
                        )
                    } label: {
                        TTIcon(icon: .camera1, filled: true, size: 18 - 2 * p)
                            .foregroundStyle(.white)
                            .frame(width: 44 - 4 * p, height: 44 - 4 * p)
                            .background(orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14 - 2 * p, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, TTSpace.screen)
        .padding(.top, 14 - 4 * p)
        .padding(.bottom, 20 - 8 * p)
        .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .bottomLeading)
        .background {
            Rectangle()
                .fill(charcoal)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Plan / session

    private func planOverviewCard(_ plan: WorkoutPlan) -> some View {
        let canMutateAI = store.traineeCanEditDeleteAIPlan(plan)

        return VStack(alignment: .leading, spacing: 10) {
            // Title first — most important piece of information
            HStack(alignment: .top, spacing: 8) {
                Text(plan.title)
                    .font(TTFont.workSans(20, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                // Compact pill badge — doesn't compete with the title
                if canMutateAI {
                    Text("AI")
                        .font(TTFont.workSans(10, weight: .bold))
                        .foregroundStyle(orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(orange.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.top, 3)
                } else {
                    Text("Trainer")
                        .font(TTFont.workSans(10, weight: .semibold))
                        .foregroundStyle(TTColor.inkSubtle)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.93))
                        .clipShape(Capsule())
                        .padding(.top, 3)
                }
            }

            Text("\(plan.level) · \(plan.focus)")
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)

            // Smart schedule — avoid repeating "Time TBD" N times
            Text(scheduleDisplay(for: plan))
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = plan.notes, !notes.isEmpty {
                Text(notes)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }

            if canMutateAI {
                aiPlanActions(plan)
            } else if plan.isAISource && store.hasLinkedTrainer {
                // Friction B: explain why the AI controls disappeared instead of going silent.
                aiPausedExplainer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    /// Shows weekday names only when times are all TBD — avoids "Mon Time TBD · Mon Time TBD…"
    private func scheduleDisplay(for plan: WorkoutPlan) -> String {
        let scheduled = plan.scheduledDays
        if scheduled.isEmpty { return "\(plan.daysPerWeek)× per week" }
        let allTBD = scheduled.allSatisfy { $0.startTime == nil }
        if allTBD {
            return scheduled.map { $0.weekday.short }.joined(separator: " · ")
        }
        return plan.scheduleLine
    }

    /// Day keys (yyyy-M-d) for all days in the plan that have a session.
    private func sessionDayKeySet(_ plan: WorkoutPlan) -> Set<String> {
        let cal = Calendar.current
        // Build keys for the next 28 days that have a session
        let today = cal.startOfDay(for: Date())
        var keys = Set<String>()
        for offset in -7...28 {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            if plan.session(on: date) != nil {
                let c = cal.dateComponents([.year, .month, .day], from: date)
                keys.insert("\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)")
            }
        }
        return keys
    }

    /// Friction B: inline, neutral explainer for an AI plan whose controls are paused
    /// because a coach is now linked. Read-only ≠ un-trainable — the session still starts.
    private var aiPausedExplainer: some View {
        let coachName = store.currentTrainee
            .flatMap { store.trainer(for: $0)?.userId }
            .flatMap { id in store.users.first { $0.id == id }?.name }?
            .components(separatedBy: " ").first ?? "Your coach"

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TTColor.info)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(coachName) guides your training")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                Text("Your AI plan controls are paused while a coach guides you. They return if you leave your coach.")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.info.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 4)
    }

    private func aiPlanActions(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    editingPlan = plan
                    showEditAIPlan = true
                } label: {
                    Text("Edit")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isMutatingAIPlan)

                Button {
                    showAssessmentReview = true
                } label: {
                    Text("Regenerate")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isMutatingAIPlan)
            }

            // Delete demoted to text link — extra distance from other CTAs prevents fat-finger deletion
            Button {
                editingPlan = plan
                showDeleteAIConfirm = true
            } label: {
                Text("Delete this plan")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(Color(red: 0.72, green: 0.15, blue: 0.15).opacity(isMutatingAIPlan ? 0.4 : 1))
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(isMutatingAIPlan)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 4)
    }

    @MainActor
    private func deleteAIPlan() async {
        guard let plan = editingPlan ?? store.currentTrainee.flatMap({ store.assignedPlan(for: $0) }) else { return }
        isMutatingAIPlan = true
        defer { isMutatingAIPlan = false }
        do {
            try await store.deleteAIPlan(id: plan.id)
            editingPlan = nil
            hubToast = TTToastMessage(text: "AI plan removed", style: .success)
        } catch let error as AppError where error.isForbidden {
            hubToast = TTToastMessage(text: error.localizedDescription, style: .error)
        } catch let error as AppError where error.isAIRequired {
            _ = store.presentAIPaywallIfNeeded(for: error)
        } catch {
            hubToast = TTToastMessage(text: error.localizedDescription, style: .error)
        }
    }



    /// "Today", "Tomorrow", "Yesterday", or the weekday name.
    private func relativeDayLabel(for weekday: Weekday) -> String {
        let todayIdx = Weekday.from(date: selectedDay).sortIndex
        let targetIdx = weekday.sortIndex
        switch (targetIdx - todayIdx + 7) % 7 {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 6: return "Yesterday"
        default: return weekday.title
        }
    }

    private func session(in plan: WorkoutPlan) -> PlanDay? {
        plan.session(on: selectedDay)
    }

    private func currentExercises(in plan: WorkoutPlan) -> [WorkoutExercise] {
        session(in: plan)?.exercises ?? plan.exercises
    }

    private func hubExercises(in plan: WorkoutPlan) -> [HubExerciseItem] {
        currentExercises(in: plan).compactMap { item in
            guard let exercise = store.exercise(id: item.exerciseId) else { return nil }
            return HubExerciseItem(id: item.id, exercise: exercise, prescription: item)
        }
    }

    private func sessionHero(_ plan: WorkoutPlan) -> some View {
        let day = session(in: plan)
        let next = plan.nextSession(from: selectedDay)
        let isPast = selectedDay < Calendar.current.startOfDay(for: Date())
        let isRestDay = day == nil

        return VStack(alignment: .leading, spacing: 10) {
            // Label: calm gray for rest days, orange only for active sessions
            Text(isRestDay ? "REST DAY" : (isPast ? "PAST SESSION" : "TODAY'S SESSION"))
                .font(TTFont.caption(11))
                .fontWeight(.bold)
                .tracking(0.8)
                .foregroundStyle(isRestDay || isPast ? TTColor.inkSubtle : orange)

            Text(day?.title ?? plan.title)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)

            if let day {
                Text("\(relativeDayLabel(for: day.weekday)) · \(day.timeLabel) · \(day.durationMinutes) min · \(day.location ?? "Gym")")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)

                if !day.focus.isEmpty {
                    Text(day.focus)
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }

                if isPast {
                    // Past date — session already over, don't offer to start it
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TTColor.inkSubtle)
                        Text("This session has passed")
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                    .padding(.top, 2)
                } else {
                    NavigationLink {
                        ActiveWorkoutView(plan: plan, day: day)
                    } label: {
                        Text("Start session")
                            .font(TTFont.workSans(15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            } else {
                Text(next.map { "Next session: \(relativeDayLabel(for: $0.weekday)) · \($0.focus)" } ?? plan.focus)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    @ViewBuilder
    private func sessionDetail(_ plan: WorkoutPlan) -> some View {
        if let day = session(in: plan) {
            if let notes = day.coachNotes, !notes.isEmpty {
                labeledCard("How to do this workout", notes)
            }
            if let warmup = day.warmup, !warmup.isEmpty {
                labeledCard("Warm-up", warmup)
            }

            exercisesSection(hubExercises(in: plan))

            if let cooldown = day.cooldown, !cooldown.isEmpty {
                labeledCard("Cool-down", cooldown)
            }
        } else {
            // Rest day — show recovery info, not the exercise list
            let next = plan.nextSession(from: selectedDay)
            VStack(alignment: .leading, spacing: 8) {
                Text("REST DAY")
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .tracking(0.8)
                    .foregroundStyle(TTColor.inkSubtle)
                Text("Recovery is where the gains happen.")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                if let next {
                    Text("Next session: \(relativeDayLabel(for: next.weekday)) · \(next.timeLabel) · \(next.focus)")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Text("Today: stretch, walk, or sleep early. 💤")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            if let notes = plan.notes, !notes.isEmpty {
                labeledCard("Trainer notes", notes)
            }
        }
    }

    private func exercisesSection(_ items: [HubExerciseItem]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: TTCardTokens.listSpacing) {
                    Text("Exercises")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)

                    TTStackedSections(
                        data: items,
                        stackOffset: TTStackedTokens.stackOffset,
                        withDramaEffect: true,
                        paneGap: TTSpace.md,
                        scrollRunway: TTStackedTokens.defaultRunway,
                        coordinateSpaceName: scrollSpace
                    ) { row in
                        NavigationLink {
                            ExerciseDetailView(exercise: row.exercise, prescription: row.prescription)
                        } label: {
                            exerciseRow(row.exercise, row.prescription)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func labeledCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .fontWeight(.bold)
                .foregroundStyle(TTColor.inkSubtle)
            Text(body)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TTCardTokens.padding)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.listCorner, style: .continuous))
    }

    private func exerciseRow(_ exercise: Exercise, _ item: WorkoutExercise) -> some View {
        HStack(spacing: TTCardTokens.listSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: TTCardTokens.thumbCorner, style: .continuous)
                    .fill(orange.opacity(0.12))
                TTIcon(icon: .kettlebell, filled: true, size: 18)
                    .foregroundStyle(orange)
            }
            .frame(width: TTCardTokens.thumbSize, height: TTCardTokens.thumbSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(TTFont.workSans(TTCardTokens.titleSize + 1, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text(item.prescriptionLine)
                    .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
            }

            Spacer(minLength: 8)

            TTIcon(icon: .chevronRight, size: 14)
                .foregroundStyle(TTColor.inkSubtle)
        }
        .padding(TTCardTokens.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
    }

    private func liveFormCard(_ plan: WorkoutPlan) -> some View {
        let enabled = store.aiCapabilities.visionPose
        let row = HStack(spacing: TTCardTokens.listSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: TTCardTokens.thumbCorner, style: .continuous)
                    .fill(enabled ? orange.opacity(0.12) : Color(white: 0.9))
                TTIcon(icon: .camera1, filled: true, size: 18)
                    .foregroundStyle(enabled ? orange : TTColor.inkSubtle)
            }
            .frame(width: TTCardTokens.thumbSize, height: TTCardTokens.thumbSize)

            VStack(alignment: .leading, spacing: 3) {
                Text("Live form correction")
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(enabled ? TTColor.ink : TTColor.inkMuted)
                if enabled {
                    Text("Use the camera for real-time cues")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                } else {
                    // "Coming soon" badge instead of a dead subtitle that looks like a bug
                    Text("Coming soon")
                        .font(TTFont.workSans(10, weight: .bold))
                        .foregroundStyle(TTColor.inkSubtle)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(white: 0.91))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 8)

            // Chevron only when tappable — no chevron on disabled rows
            if enabled {
                TTIcon(icon: .chevronRight, size: 14)
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .padding(TTCardTokens.padding)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .opacity(enabled ? 1 : 0.65)

        return Group {
            if enabled {
                NavigationLink {
                    LiveFormCorrectionView(initialExerciseId: currentExercises(in: plan).first?.exerciseId)
                } label: { row }
                .buttonStyle(.plain)
            } else {
                row // non-interactive, clearly disabled
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .barbellDiagonal, filled: true, size: 28)
                .foregroundStyle(orange)
            Text("No workout assigned")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(
                store.canShowSoloAIGenerate
                    ? "Generate my week from Home to build an AI plan, or link a trainer."
                    : "Your trainer will attach a plan with days, times, and weights."
            )
            .font(TTFont.body(14))
            .foregroundStyle(TTColor.inkMuted)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }
}

private struct HubExerciseItem: Identifiable {
    let id: String
    let exercise: Exercise
    let prescription: WorkoutExercise
}

// MARK: - Exercise detail

struct ExerciseDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let prescription: WorkoutExercise

    @State private var showFormStudio = false
    @State private var formStudioToast: TTToastMessage?

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = TTColor.actionOrange

    private var formStudioSession: FormStudioExerciseMap.DemoSession? {
        FormStudioExerciseMap.demoSession(for: exercise)
    }

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(title: exercise.name) {
                dismiss()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.muscleGroup.uppercased())
                            .font(TTFont.caption(11))
                            .fontWeight(.bold)
                            .foregroundStyle(orange)
                        Text(prescription.prescriptionLine)
                            .font(TTFont.workSans(15, weight: .medium))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Prescribed sets")
                            .font(TTFont.workSans(15, weight: .bold))
                        ForEach(prescription.workingSets) { set in
                            HStack {
                                Text("Set \(set.setNumber)")
                                    .font(TTFont.workSans(14, weight: .semibold))
                                Spacer()
                                Text("\(set.reps) reps")
                                Text(set.weightKg.map { "\($0.cleanKg) kg" } ?? "bodyweight")
                                if let rpe = set.rpe {
                                    Text("RPE \(rpe.cleanKg)")
                                }
                            }
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.inkMuted)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))

                    if let notes = prescription.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How to perform")
                                .font(TTFont.workSans(15, weight: .bold))
                            Text(notes)
                                .font(TTFont.body(15))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cues")
                            .font(TTFont.workSans(15, weight: .bold))
                        ForEach(exercise.cues, id: \.self) { cue in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(orange).frame(width: 6, height: 6).padding(.top, 7)
                                Text(cue)
                                    .font(TTFont.body(15))
                                    .foregroundStyle(TTColor.ink)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))

                    formCoachActions
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
        }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .ttToast($formStudioToast, bottomInset: 28)
        .overlay(alignment: .top) {
            if let notice = store.planChangeNotice {
                Text(notice)
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(orange.opacity(0.14))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { store.beginTraineeSessionUI() }
        .onDisappear { store.endTraineeSessionUI() }
        .fullScreenCover(isPresented: $showFormStudio) {
            if let formStudioSession {
                FormStudioDemoView(session: formStudioSession) { message in
                    showFormStudio = false
                    formStudioToast = TTToastMessage(
                        text: message.isEmpty ? "Couldn't load 3D demo" : message,
                        style: .error
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var formCoachActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Form coaching")
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(TTColor.ink)

            if let formStudioSession {
                Button {
                    showFormStudio = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(orange.opacity(0.12))
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(orange)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("3D Form Demo")
                                .font(TTFont.workSans(15, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                            Text(
                                formStudioSession.subtitle
                                    ?? "Watch a 3D coach demonstrate form"
                            )
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        TTIcon(icon: .chevronRight, size: 14)
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open 3D form demonstration")
            } else {
                #if DEBUG
                if exercise.form3d?.enabled == true {
                    Text("3D demo enabled but no animationUrl / bundled clip (DEBUG)")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                } else if FormStudioExerciseMap.mappedIdIgnoringBundle(for: exercise) != nil {
                    Text("3D demo — awaiting backend form3d or Mixamo clip (DEBUG)")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }
                #endif
            }

            NavigationLink {
                LiveFormCorrectionView(initialExerciseId: exercise.id)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(orange.opacity(0.12))
                        TTIcon(icon: .camera1, filled: true, size: 16)
                            .foregroundStyle(orange)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Form")
                            .font(TTFont.workSans(15, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Text("Camera AI checks your form in real time")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer(minLength: 8)
                    TTIcon(icon: .chevronRight, size: 14)
                        .foregroundStyle(TTColor.inkSubtle)
                }
                .padding(14)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open live form AI")
        }
    }
}

// MARK: - Active workout (overview launcher)

struct ActiveWorkoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    var day: PlanDay?
    @State private var logs: [WorkoutSetLog] = []
    @State private var showGuided = false
    @State private var guidedStartIndex = 0
    @State private var guidedElapsed = 0
    @State private var showComplete = false
    /// Server-side session id — set once session is started or resumed.
    @State private var sessionId: String?
    @State private var sessionError: String?
    @State private var isStartingSession = false

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = TTColor.actionOrange

    private var exercises: [WorkoutExercise] { day?.exercises ?? plan.exercises }
    private var completedExerciseCount: Int { Set(logs.map(\.exerciseId)).count }

    private static func relativeDay(_ weekday: Weekday) -> String {
        let todayIdx = Weekday.from(date: Date()).sortIndex
        let targetIdx = weekday.sortIndex
        switch (targetIdx - todayIdx + 7) % 7 {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 6: return "Yesterday"
        default: return weekday.title
        }
    }

    private var activeExerciseIndex: Int {
        for (i, item) in exercises.enumerated() {
            let allDone = item.workingSets.allSatisfy { set in
                logs.contains { $0.exerciseId == item.exerciseId && $0.setNumber == set.setNumber }
            }
            if !allDone { return i }
        }
        return exercises.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(title: day?.title ?? plan.title) { dismiss() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {

                    // Progress summary card
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.map { "\(Self.relativeDay($0.weekday)) · \($0.timeLabel)" } ?? "Session")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                            Text("\(completedExerciseCount) of \(exercises.count) done")
                                .font(TTFont.workSans(22, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                        }
                        Spacer()
                        ZStack {
                            Circle().stroke(Color(white: 0.88), lineWidth: 3).frame(width: 52, height: 52)
                            Circle().trim(from: 0, to: exercises.isEmpty ? 0 : CGFloat(completedExerciseCount) / CGFloat(exercises.count))
                                .stroke(orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 52, height: 52)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.4), value: completedExerciseCount)
                            Text("\(exercises.isEmpty ? 0 : Int(Double(completedExerciseCount) / Double(exercises.count) * 100))%")
                                .font(TTFont.workSans(12, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                        }
                    }
                    .padding(16)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))

                    // Coach notes
                    if let notes = day?.coachNotes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(orange)
                            Text(notes)
                                .font(TTFont.body(13))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        .padding(14)
                        .background(orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Start / Continue button
                    Button {
                        guidedStartIndex = activeExerciseIndex
                        showGuided = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: completedExerciseCount == 0 ? "play.fill" : "arrow.right.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text(completedExerciseCount == 0 ? "Start Workout" : "Continue Workout")
                                .font(TTFont.workSans(16, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: orange.opacity(0.35), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)

                    // Exercise list header
                    Text("Today's exercises")
                        .font(TTFont.workSans(11, weight: .bold))
                        .foregroundStyle(TTColor.inkMuted)
                        .kerning(0.8)
                        .textCase(.uppercase)
                        .padding(.top, 4)

                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, item in
                        if let exercise = store.exercise(id: item.exerciseId) {
                            let isDone = item.workingSets.allSatisfy { set in
                                logs.contains { $0.exerciseId == item.exerciseId && $0.setNumber == set.setNumber }
                            }
                            let isActive = index == activeExerciseIndex && !isDone
                            overviewRow(exercise: exercise, item: item, index: index, isActive: isActive, isDone: isDone)
                        }
                    }
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
        }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .task { await ensureSession() }
        .fullScreenCover(isPresented: $showGuided) {
            GuidedWorkoutFlow(
                exercises: exercises,
                planTitle: plan.title,
                startIndex: guidedStartIndex,
                sessionId: sessionId,
                logs: $logs
            ) { elapsed in
                guidedElapsed = elapsed
                showGuided = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showComplete = true
                }
            }
        }
        .sheet(isPresented: $showComplete) {
            WorkoutCompleteSheet(
                duration: guidedElapsed,
                exercisesCount: completedExerciseCount,
                setsCount: logs.count
            ) {
                Task {
                    if let sid = sessionId {
                        // Session API path: complete via backend, which saves the log server-side.
                        try? await store.completeWorkoutSession(sessionId: sid, durationMinutes: max(guidedElapsed / 60, 1))
                        sessionId = nil
                    } else {
                        // Fallback: save a local log when session API was unavailable.
                        guard let trainee = store.currentTrainee else { dismiss(); return }
                        try? await store.saveWorkoutLog(
                            WorkoutLog(
                                id: UUID().uuidString,
                                traineeId: trainee.id,
                                planId: plan.id,
                                completedAt: .now,
                                durationMinutes: max(guidedElapsed / 60, 1),
                                sets: logs
                            )
                        )
                    }
                    dismiss()
                }
            }
        }
    }

    /// Starts a fresh session or resumes the active one if it belongs to this plan/day.
    private func ensureSession() async {
        guard sessionId == nil, !isStartingSession else { return }
        isStartingSession = true
        defer { isStartingSession = false }

        // Check if there is already an active session for this plan.
        if let existing = store.activeWorkoutSession, existing.planId == plan.id {
            logs = existing.sets
            sessionId = existing.id
            return
        }

        // Fetch from server in case the app was relaunched.
        await store.refreshActiveSession()
        if let existing = store.activeWorkoutSession, existing.planId == plan.id {
            logs = existing.sets
            sessionId = existing.id
            return
        }

        // No matching active session — start one (best-effort; if it fails, workout continues locally).
        do {
            let session = try await store.startWorkoutSession(planId: plan.id, dayId: day?.id)
            sessionId = session.id
        } catch {
            sessionError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func overviewRow(exercise: Exercise, item: WorkoutExercise, index: Int, isActive: Bool, isDone: Bool) -> some View {
        Button {
            guidedStartIndex = index
            showGuided = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isDone ? orange : isActive ? orange.opacity(0.15) : Color(white: 0.88))
                        .frame(width: 36, height: 36)
                    if isDone {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)").font(TTFont.workSans(14, weight: .bold))
                            .foregroundStyle(isActive ? orange : Color(white: 0.55))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(TTFont.workSans(15, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isDone ? TTColor.inkMuted : TTColor.ink)
                    HStack(spacing: 6) {
                        Text(item.prescriptionLine).font(TTFont.caption(12))
                            .foregroundStyle(isActive ? orange : TTColor.inkMuted)
                        Text("·").font(TTFont.caption(12)).foregroundStyle(TTColor.inkMuted)
                        Text(exercise.muscleGroup).font(TTFont.caption(12)).foregroundStyle(TTColor.inkMuted)
                    }
                }
                Spacer()
                Image(systemName: isDone ? "checkmark.circle.fill" : isActive ? "play.circle.fill" : "chevron.right")
                    .font(.system(size: isDone || isActive ? 22 : 13, weight: .semibold))
                    .foregroundStyle(isDone ? orange.opacity(0.5) : isActive ? orange : Color(white: 0.75))
            }
            .padding(14)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous)
                .stroke(isActive ? orange.opacity(0.3) : Color.clear, lineWidth: 1.5))
            .opacity(isDone ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isDone)
    }
}

// MARK: - Guided workout flow (one set at a time)

struct GuidedWorkoutFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let exercises: [WorkoutExercise]
    let planTitle: String
    let startIndex: Int
    /// Nil when session API was unavailable; sets are still logged locally.
    let sessionId: String?
    @Binding var logs: [WorkoutSetLog]
    let onFinish: (Int) -> Void

    enum Phase { case exercise, rest }

    @State private var exerciseIndex: Int
    @State private var setIndex = 0
    @State private var phase: Phase = .exercise
    @State private var restSeconds = 0
    @State private var elapsed = 0
    @State private var timerRunning = false
    @State private var showExitConfirm = false  // C3
    @State private var isSavingSet = false
    @State private var saveError: String? = nil
    @State private var pendingSet: PendingSetInfo? = nil

    private struct PendingSetInfo {
        var sessionId: String
        var exerciseId: String
        var setNumber: Int
        var reps: Int
        var weightKg: Double
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let orange = TTColor.actionOrange
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    init(exercises: [WorkoutExercise], planTitle: String, startIndex: Int, sessionId: String?, logs: Binding<[WorkoutSetLog]>, onFinish: @escaping (Int) -> Void) {
        self.exercises = exercises
        self.planTitle = planTitle
        self.startIndex = startIndex
        self.sessionId = sessionId
        self._logs = logs
        self.onFinish = onFinish
        self._exerciseIndex = State(initialValue: startIndex)
        // C2: resume at the first set not yet in logs for the starting exercise
        let currentLogs = logs.wrappedValue
        if exercises.indices.contains(startIndex) {
            let item = exercises[startIndex]
            let loggedSetNumbers = Set(currentLogs.filter { $0.exerciseId == item.exerciseId }.map { $0.setNumber })
            let resumeSet = item.workingSets.firstIndex { !loggedSetNumbers.contains($0.setNumber) } ?? 0
            self._setIndex = State(initialValue: resumeSet)
        } else {
            self._setIndex = State(initialValue: 0)
        }
    }

    private var currentItem: WorkoutExercise? {
        exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil
    }
    private var currentExercise: Exercise? {
        currentItem.flatMap { store.exercise(id: $0.exerciseId) }
    }
    private var currentSet: PrescribedSet? {
        guard let item = currentItem, item.workingSets.indices.contains(setIndex) else { return nil }
        return item.workingSets[setIndex]
    }
    private var totalSets: Int { currentItem?.workingSets.count ?? 0 }
    private var isLastSet: Bool { setIndex >= totalSets - 1 }
    private var isLastExercise: Bool { exerciseIndex >= exercises.count - 1 }

    // What comes after the current rest
    private var upNextExercise: Exercise? {
        if isLastSet {
            let ni = exerciseIndex + 1
            guard exercises.indices.contains(ni) else { return nil }
            return store.exercise(id: exercises[ni].exerciseId)
        }
        return currentExercise
    }
    private var upNextSet: PrescribedSet? {
        if isLastSet {
            let ni = exerciseIndex + 1
            guard exercises.indices.contains(ni) else { return nil }
            return exercises[ni].workingSets.first
        }
        guard let item = currentItem, item.workingSets.indices.contains(setIndex + 1) else { return nil }
        return item.workingSets[setIndex + 1]
    }

    private var overallProgress: Double {
        let total = exercises.reduce(0) { $0 + $1.workingSets.count }
        guard total > 0 else { return 0 }
        return Double(logs.count) / Double(total)
    }
    private var timeString: String { String(format: "%02d:%02d", elapsed / 60, elapsed % 60) }
    private var restString: String { String(format: "%d:%02d", restSeconds / 60, restSeconds % 60) }

    private func logSet() {
        guard let item = currentItem, let set = currentSet else { return }
        // C2: prevent re-logging a set already recorded (e.g. after leave-and-re-enter)
        guard !logs.contains(where: { $0.exerciseId == item.exerciseId && $0.setNumber == set.setNumber }) else {
            doAdvance()
            return
        }
        if !timerRunning { timerRunning = true }
        let weightKg = set.weightKg ?? item.recommendedWeightKg ?? 0
        let localLog = WorkoutSetLog(
            id: UUID().uuidString,
            exerciseId: item.exerciseId,
            setNumber: set.setNumber,
            reps: set.reps,
            weightKg: weightKg
        )
        logs.append(localLog)

        guard let sid = sessionId else {
            // No session active — no backend to confirm; advance immediately.
            doAdvance()
            return
        }

        let info = PendingSetInfo(
            sessionId: sid,
            exerciseId: item.exerciseId,
            setNumber: set.setNumber,
            reps: set.reps,
            weightKg: weightKg
        )
        pendingSet = info
        isSavingSet = true
        saveError = nil
        Task { await commitSet(info) }
    }

    private func commitSet(_ info: PendingSetInfo) async {
        do {
            _ = try await store.logSet(
                sessionId: info.sessionId,
                exerciseId: info.exerciseId,
                setNumber: info.setNumber,
                reps: info.reps,
                weightKg: info.weightKg
            )
            pendingSet = nil
            isSavingSet = false
            doAdvance()
        } catch {
            isSavingSet = false
            saveError = "Couldn't save set — check your connection."
        }
    }

    private func retryPendingSet() {
        guard let info = pendingSet else { return }
        isSavingSet = true
        saveError = nil
        Task { await commitSet(info) }
    }

    private func doAdvance() {
        if isLastSet && isLastExercise {
            onFinish(elapsed)
            dismiss()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .rest }
            restSeconds = 90
        }
    }

    private func advanceAfterRest() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if isLastSet {
                exerciseIndex += 1
                setIndex = 0
            } else {
                setIndex += 1
            }
            phase = .exercise
        }
    }
    var body: some View {
        ZStack {
            charcoal.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Minimal header ───────────────────────────────────────
                HStack {
                    Button { showExitConfirm = true } label: {  // C3: confirm before leaving
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(timerRunning ? timeString : "– : –")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(timerRunning ? .white : .white.opacity(0.3))
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Spacer()
                    Text("\(exerciseIndex + 1) / \(exercises.count)")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Overall progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                        Capsule().fill(orange)
                            .frame(width: geo.size.width * overallProgress, height: 3)
                            .animation(.easeInOut(duration: 0.5), value: overallProgress)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, TTSpace.screen)
                .padding(.bottom, 16)

                // ── Phase content ────────────────────────────────────────
                ZStack {
                    if phase == .exercise {
                        exerciseScreen
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        restScreen
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.85), value: phase == .exercise)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ttHideSystemNavigationBar()
        .sensoryFeedback(.success, trigger: logs.count)
        .onAppear { timerRunning = true }
        .onReceive(timer) { _ in
            if timerRunning { elapsed += 1 }
            if restSeconds > 0 {
                restSeconds -= 1
                if restSeconds == 0 { advanceAfterRest() }
            }
        }
        // C3: exit confirmation — timer, rest countdown and progress are not reset on Cancel
        .confirmationDialog("Leave workout?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("Leave workout", role: .destructive) { dismiss() }
            Button("Stay in workout", role: .cancel) {}
        } message: {
            Text("Sets you've completed are saved. Your timer will reset if you return.")
        }
    }

    // ── Exercise screen ──────────────────────────────────────────────────
    @ViewBuilder
    private var exerciseScreen: some View {
        if let exercise = currentExercise, let set = currentSet {
            VStack(spacing: 0) {
                Spacer()

                // Exercise name + muscle group
                VStack(spacing: 10) {
                    Text(exercise.name)
                        .font(TTFont.workSans(34, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TTSpace.screen)

                    HStack(spacing: 8) {
                        label(exercise.muscleGroup)
                        label(exercise.equipment)
                    }
                }

                Spacer()

                // Set target — big and clear
                VStack(spacing: 6) {
                    Text("Set \(setIndex + 1) of \(totalSets)")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))

                    Text("\(set.reps)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text("reps")
                        .font(TTFont.workSans(18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))

                    if let kg = set.weightKg {
                        Text("\(kg.cleanKg) kg")
                            .font(TTFont.workSans(24, weight: .bold))
                            .foregroundStyle(orange)
                            .padding(.top, 4)
                    }
                }

                Spacer()

                // Trainer note (compact)
                if let notes = currentItem?.notes, !notes.isEmpty {
                    Text(notes)
                        .font(TTFont.body(13))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TTSpace.screen)
                        .padding(.bottom, 12)
                }

                // Done button
                VStack(spacing: 12) {
                    Button { logSet() } label: {
                        ZStack {
                            Text("Done")
                                .font(TTFont.workSans(20, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(isSavingSet ? 0 : 1)
                            if isSavingSet {
                                ProgressView().tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(isSavingSet ? orange.opacity(0.55) : orange)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: orange.opacity(0.4), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingSet)

                    if let err = saveError {
                        VStack(spacing: 6) {
                            Text(err)
                                .font(TTFont.caption(13))
                                .foregroundStyle(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                            Button("Retry") { retryPendingSet() }
                                .font(TTFont.workSans(15, weight: .semibold))
                                .foregroundStyle(orange)
                        }
                    }
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.bottom, 48)
            }
        }
    }

    // ── Rest screen ──────────────────────────────────────────────────────
    @ViewBuilder
    private var restScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Rest")
                .font(TTFont.workSans(20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(restString)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .monospacedDigit()
                .padding(.top, 4)

            Spacer()

            // Up next preview
            if let nextEx = upNextExercise, let nextSet = upNextSet {
                VStack(spacing: 6) {
                    Text("UP NEXT")
                        .font(TTFont.workSans(10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .kerning(1.2)
                    Text(isLastSet ? nextEx.name : nextEx.name)
                        .font(TTFont.workSans(18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("Set \(isLastSet ? 1 : setIndex + 2) · \(nextSet.reps) reps\(nextSet.weightKg.map { " · \($0.cleanKg) kg" } ?? "")")
                        .font(TTFont.caption(13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 32)
            }

            // Skip button
            Button { advanceAfterRest() } label: {
                Text("Skip rest")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TTSpace.screen)
            .padding(.bottom, 48)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(TTFont.workSans(12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Workout complete sheet

private struct WorkoutCompleteSheet: View {
    let duration: Int
    let exercisesCount: Int
    let setsCount: Int
    let onDone: () -> Void

    @Environment(\.dismiss) private var sheetDismiss
    private let orange = TTColor.actionOrange

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(white: 0.82))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(orange.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Text("🏆")
                        .font(.system(size: 52))
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Workout Complete!")
                        .font(TTFont.workSans(26, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text(motivationLine)
                        .font(TTFont.workSans(14, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 0) {
                    statBox(value: durationString, label: "Duration")
                    Divider().frame(height: 44)
                    statBox(value: "\(exercisesCount)", label: "Exercises")
                    Divider().frame(height: 44)
                    statBox(value: "\(setsCount)", label: "Sets")
                }
                .padding(.vertical, 16)
                .background(Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    sheetDismiss()
                    onDone()
                } label: {
                    Text("Done — back to home")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)  // C1: prevent swipe-dismiss bypassing log save
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(label)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationString: String {
        let mins = duration / 60
        if mins == 0 { return "\(duration)s" }
        return "\(mins)m"
    }

    private var motivationLine: String {
        let lines = [
            "Every rep counts. You showed up.",
            "That's another session in the bank.",
            "Consistency beats intensity every time.",
            "Your future self will thank you.",
            "One workout at a time. Keep going."
        ]
        return lines[abs(setsCount) % lines.count]
    }
}

#Preview("Workout Hub") {
    WorkoutHubView()
        .ttPreviewTrainee()
}

#Preview("Active Workout") {
    NavigationStack {
        ActiveWorkoutView(plan: TTPreview.samplePlan, day: TTPreview.samplePlan.session(on: .now))
            .ttPreviewTrainee()
    }
}
