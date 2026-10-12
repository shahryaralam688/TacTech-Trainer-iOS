import SwiftUI

// MARK: - Trainee Workout Hub (Sandow / TacTech system design)

struct WorkoutHubView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When presented as a sheet from Home, show a back control.
    var showsCloseChrome: Bool = false

    @State private var selectedDay = Date()
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

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
                            if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
                                planOverviewCard(plan)
                                TTHomeWeekDatePicker(selected: $selectedDay, accent: orange)
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
            }
            .background(charcoal.ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .ttSyncRootTabBarWithNavigationDepth()
            .task {
                await store.refreshAssignedPlanForCurrentTrainee()
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR PLAN")
                .font(TTFont.caption(11))
                .fontWeight(.bold)
                .tracking(0.8)
                .foregroundStyle(orange)

            Text(plan.title)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)

            Text("\(plan.level) · \(plan.focus)")
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)

            Text(plan.scheduleLine)
                .font(TTFont.caption(12))
                .foregroundStyle(orange)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = plan.notes, !notes.isEmpty {
                Text(notes)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
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
        return VStack(alignment: .leading, spacing: 10) {
            Text(day == nil ? "NO SESSION THIS DAY" : "THIS SESSION")
                .font(TTFont.caption(11))
                .fontWeight(.bold)
                .tracking(0.8)
                .foregroundStyle(orange)

            Text(day?.title ?? plan.title)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)

            if let day {
                Text("\(day.weekday.title) · \(day.timeLabel) · \(day.durationMinutes) min · \(day.location ?? "Gym")")
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)

                if !day.focus.isEmpty {
                    Text(day.focus)
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }

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
            } else {
                Text(next.map { "Rest day. Next is \($0.weekday.title) at \($0.timeLabel)." } ?? plan.focus)
                    .font(TTFont.body(14))
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
        } else if !plan.exercises.isEmpty {
            // Rest day — still show the program library as a stacked deck.
            exercisesSection(hubExercises(in: plan))
            if let notes = plan.notes, !notes.isEmpty {
                labeledCard("Trainer notes", notes)
            }
        } else if let notes = plan.notes, !notes.isEmpty {
            labeledCard("Trainer notes", notes)
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
        NavigationLink {
            LiveFormCorrectionView(initialExerciseId: currentExercises(in: plan).first?.exerciseId)
        } label: {
            HStack(spacing: TTCardTokens.listSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: TTCardTokens.thumbCorner, style: .continuous)
                        .fill(orange.opacity(0.12))
                    TTIcon(icon: .camera1, filled: true, size: 18)
                        .foregroundStyle(orange)
                }
                .frame(width: TTCardTokens.thumbSize, height: TTCardTokens.thumbSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Live form correction")
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("Use the camera for real-time cues")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                }

                Spacer(minLength: 8)

                TTIcon(icon: .chevronRight, size: 14)
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(TTCardTokens.padding)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .barbellDiagonal, filled: true, size: 28)
                .foregroundStyle(orange)
            Text("No workout assigned")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text("Your trainer will attach a plan with days, times, and weights.")
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
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let prescription: WorkoutExercise

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = TTColor.actionOrange

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

                    NavigationLink {
                        LiveFormCorrectionView(initialExerciseId: exercise.id)
                    } label: {
                        HStack(spacing: 10) {
                            TTIcon(icon: .camera1, filled: true, size: 16)
                            Text("Open live form AI")
                                .font(TTFont.workSans(15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
        }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
    }
}

// MARK: - Active workout

struct ActiveWorkoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    var day: PlanDay?
    @State private var elapsed = 0
    @State private var timerRunning = false
    @State private var logs: [WorkoutSetLog] = []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = TTColor.actionOrange

    private var exercises: [WorkoutExercise] {
        day?.exercises ?? plan.exercises
    }

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(title: day?.title ?? plan.title) {
                dismiss()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.map { "\($0.weekday.title) · \($0.timeLabel)" } ?? "Session")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                            Text(timeString)
                                .font(TTFont.workSans(34, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                        }
                        Spacer()
                        Button(timerRunning ? "Pause" : "Start") {
                            timerRunning.toggle()
                        }
                        .font(TTFont.workSans(14, weight: .bold))
                        .foregroundStyle(orange)
                    }
                    .padding(16)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))

                    if let notes = day?.coachNotes, !notes.isEmpty {
                        Text(notes)
                            .font(TTFont.body(14))
                            .foregroundStyle(TTColor.inkMuted)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardFill)
                            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
                    }

                    TTStackedSections(
                        data: exercises,
                        stackOffset: TTStackedTokens.stackOffset,
                        withDramaEffect: true,
                        paneGap: TTSpace.md,
                        scrollRunway: TTStackedTokens.defaultRunway
                    ) { item in
                        if let exercise = store.exercise(id: item.exerciseId) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(exercise.name)
                                    .font(TTFont.workSans(16, weight: .bold))
                                Text(item.prescriptionLine)
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(TTColor.inkMuted)
                                if let notes = item.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(TTFont.caption(12))
                                        .foregroundStyle(TTColor.inkMuted)
                                }
                                ForEach(item.workingSets) { set in
                                    setRow(exercise: exercise, item: item, set: set)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardFill)
                            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
                            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
                        }
                    }

                    Button {
                        guard let trainee = store.currentTrainee else { return }
                        Task {
                            try? await store.saveWorkoutLog(
                                WorkoutLog(
                                    id: UUID().uuidString,
                                    traineeId: trainee.id,
                                    planId: plan.id,
                                    completedAt: .now,
                                    durationMinutes: max(elapsed / 60, 1),
                                    sets: logs
                                )
                            )
                            dismiss()
                        }
                    } label: {
                        Text("Finish workout")
                            .font(TTFont.workSans(16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
        }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .onReceive(timer) { _ in
            if timerRunning { elapsed += 1 }
        }
        .onAppear { timerRunning = true }
    }

    private var timeString: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private func setRow(exercise: Exercise, item: WorkoutExercise, set: PrescribedSet) -> some View {
        let existing = logs.first { $0.exerciseId == exercise.id && $0.setNumber == set.setNumber }
        return HStack {
            Text("Set \(set.setNumber)")
                .font(TTFont.workSans(14, weight: .semibold))
            Spacer()
            Text("\(set.reps) reps · \(set.weightKg.map { "\($0.cleanKg) kg" } ?? "BW")")
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.inkMuted)
            Button(existing == nil ? "Log" : "Done") {
                if existing == nil {
                    logs.append(
                        WorkoutSetLog(
                            id: UUID().uuidString,
                            exerciseId: exercise.id,
                            setNumber: set.setNumber,
                            reps: set.reps,
                            weightKg: set.weightKg ?? item.recommendedWeightKg ?? 0
                        )
                    )
                }
            }
            .font(TTFont.caption(13))
            .fontWeight(.bold)
            .foregroundStyle(existing == nil ? orange : TTColor.success)
        }
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
