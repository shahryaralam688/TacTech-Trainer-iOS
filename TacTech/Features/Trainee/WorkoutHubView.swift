import SwiftUI

struct WorkoutHubView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TTScreenHeader(eyebrow: "Follow the plan", title: "Workout")
                    if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
                        TTWeekStrip(selected: $selectedDay)
                        sessionHero(plan)
                        sessionDetail(plan)
                        NavigationLink {
                            LiveFormCorrectionView(initialExerciseId: currentExercises(in: plan).first?.exerciseId)
                        } label: {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                    .foregroundStyle(TTColor.brand)
                                    .frame(width: 44, height: 44)
                                    .background(TTColor.brandSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Live form correction")
                                        .font(TTFont.heading(16))
                                        .foregroundStyle(TTColor.ink)
                                    Text("Use the camera for real-time cues")
                                        .font(TTFont.caption(12))
                                        .foregroundStyle(TTColor.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(TTColor.inkSubtle)
                            }
                            .ttCard()
                        }
                        .buttonStyle(.plain)
                    } else {
                        TTEmptyState(icon: "dumbbell", title: "No workout assigned", message: "Your trainer will attach a plan with days, times, and weights.")
                            .ttCard()
                    }
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func session(in plan: WorkoutPlan) -> PlanDay? {
        plan.session(on: selectedDay)
    }

    private func currentExercises(in plan: WorkoutPlan) -> [WorkoutExercise] {
        session(in: plan)?.exercises ?? plan.exercises
    }

    private func sessionHero(_ plan: WorkoutPlan) -> some View {
        let day = session(in: plan)
        let next = plan.nextSession(from: selectedDay)
        return VStack(alignment: .leading, spacing: 10) {
            Text(day == nil ? "NO SESSION THIS DAY" : "THIS SESSION")
                .font(TTFont.caption(11))
                .tracking(0.8)
                .foregroundStyle(TTColor.brand)
            Text(day?.title ?? plan.title)
                .font(TTFont.title(22))
            if let day {
                Text("\(day.weekday.title) · \(day.timeLabel) · \(day.durationMinutes) min · \(day.location ?? "Gym")")
                    .font(TTFont.body(14))
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
                        .font(TTFont.heading(15))
                        .foregroundStyle(TTColor.surface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(TTColor.brand)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            } else {
                Text(next.map { "Rest day. Next is \($0.weekday.title) at \($0.timeLabel)." } ?? plan.focus)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ttCard(padding: 20)
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
            TTSectionHeader(title: "Exercises")
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { _, item in
                if let exercise = store.exercise(id: item.exerciseId) {
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise, prescription: item)
                    } label: {
                        exerciseRow(exercise, item)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let cooldown = day.cooldown, !cooldown.isEmpty {
                labeledCard("Cool-down", cooldown)
            }
        } else if !plan.exercises.isEmpty {
            TTSectionHeader(title: "Exercises")
            ForEach(plan.exercises) { item in
                if let exercise = store.exercise(id: item.exerciseId) {
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise, prescription: item)
                    } label: {
                        exerciseRow(exercise, item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if let notes = plan.notes, !notes.isEmpty {
            labeledCard("Trainer notes", notes)
        }
    }

    private func labeledCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkSubtle)
            Text(body)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ttCard()
    }

    private func exerciseRow(_ exercise: Exercise, _ item: WorkoutExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: exercise.icon)
                    .foregroundStyle(TTColor.brand)
                    .frame(width: 44, height: 44)
                    .background(TTColor.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(TTFont.heading(15))
                        .foregroundStyle(TTColor.ink)
                    Text(item.prescriptionLine)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(TTColor.inkSubtle)
            }
            ForEach(item.workingSets.prefix(4)) { set in
                HStack {
                    Text("Set \(set.setNumber)")
                    Spacer()
                    Text("\(set.reps) reps")
                    Text(set.weightKg.map { "\($0.cleanKg) kg" } ?? "BW")
                }
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
            }
        }
        .ttCard()
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    let prescription: WorkoutExercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.muscleGroup.uppercased())
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.brand)
                    Text(exercise.name)
                        .font(TTFont.display(32))
                    Text(prescription.prescriptionLine)
                        .font(TTFont.body(15))
                        .foregroundStyle(TTColor.inkMuted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    TTSectionHeader(title: "Prescribed sets")
                    ForEach(prescription.workingSets) { set in
                        HStack {
                            Text("Set \(set.setNumber)")
                                .font(TTFont.heading(14))
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
                .ttCard()

                if let notes = prescription.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        TTSectionHeader(title: "How to perform")
                        Text(notes)
                            .font(TTFont.body(15))
                    }
                    .ttCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    TTSectionHeader(title: "Cues")
                    ForEach(exercise.cues, id: \.self) { cue in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(TTColor.brand).frame(width: 6, height: 6).padding(.top, 7)
                            Text(cue)
                                .font(TTFont.body(15))
                        }
                    }
                }
                .ttCard()

                NavigationLink {
                    LiveFormCorrectionView(initialExerciseId: exercise.id)
                } label: {
                    TTButton(title: "Open live form AI", icon: "camera.viewfinder", action: {})
                        .allowsHitTesting(false)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .ttScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ActiveWorkoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    var day: PlanDay?
    @State private var elapsed = 0
    @State private var timerRunning = false
    @State private var logs: [WorkoutSetLog] = []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var exercises: [WorkoutExercise] {
        day?.exercises ?? plan.exercises
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(day.map { "\($0.weekday.title) · \($0.timeLabel)" } ?? "Session")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                        Text(timeString)
                            .font(TTFont.display(36))
                    }
                    Spacer()
                    Button(timerRunning ? "Pause" : "Start") {
                        timerRunning.toggle()
                    }
                    .font(TTFont.heading(14))
                    .foregroundStyle(TTColor.brand)
                }
                .ttCard()

                if let notes = day?.coachNotes, !notes.isEmpty {
                    Text(notes)
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                        .ttCard()
                }

                ForEach(exercises) { item in
                    if let exercise = store.exercise(id: item.exerciseId) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(exercise.name)
                                .font(TTFont.heading(16))
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
                        .ttCard()
                    }
                }

                TTButton(title: "Finish workout", icon: "checkmark") {
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
                }
            }
            .padding(20)
        }
        .ttScreenBackground()
        .navigationTitle(day?.title ?? plan.title)
        .navigationBarTitleDisplayMode(.inline)
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
                .font(TTFont.heading(14))
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
            .foregroundStyle(existing == nil ? TTColor.brand : TTColor.success)
        }
    }
}
