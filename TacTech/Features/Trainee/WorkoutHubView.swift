import SwiftUI

struct WorkoutHubView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TTScreenHeader(eyebrow: "Follow the plan", title: "Workout")
                    if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
                        NavigationLink {
                            ActiveWorkoutView(plan: plan)
                        } label: {
                            startCard(plan)
                        }
                        .buttonStyle(.plain)

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

                        NavigationLink {
                            LiveFormCorrectionView(initialExerciseId: plan.exercises.first?.exerciseId)
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
                        TTEmptyState(icon: "dumbbell", title: "No workout assigned", message: "Your trainer will attach a plan to your profile.")
                            .ttCard()
                    }
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startCard(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.title)
                .font(TTFont.title(22))
            Text(plan.focus)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            HStack {
                Text("\(plan.durationMinutes) min")
                Text("·")
                Text("\(plan.exercises.count) exercises")
            }
            .font(TTFont.caption(13))
            .foregroundStyle(TTColor.inkMuted)
            Text("Start session")
                .font(TTFont.heading(15))
                .foregroundStyle(TTColor.surface)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(TTColor.brand)
                .clipShape(Capsule())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ttCard(padding: 20)
    }

    private func exerciseRow(_ exercise: Exercise, _ item: WorkoutExercise) -> some View {
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
                Text("\(item.sets)×\(item.reps) · \(exercise.muscleGroup)")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(TTColor.inkSubtle)
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
                    Text("\(prescription.sets) sets · \(prescription.reps) reps · \(prescription.restSeconds)s rest")
                        .font(TTFont.body(15))
                        .foregroundStyle(TTColor.inkMuted)
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
    @State private var elapsed = 0
    @State private var timerRunning = false
    @State private var logs: [WorkoutSetLog] = []
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Session")
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

                ForEach(plan.exercises) { item in
                    if let exercise = store.exercise(id: item.exerciseId) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(exercise.name)
                                .font(TTFont.heading(16))
                            ForEach(1...item.sets, id: \.self) { set in
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
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            if timerRunning { elapsed += 1 }
        }
        .onAppear { timerRunning = true }
    }

    private var timeString: String {
        String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private func setRow(exercise: Exercise, item: WorkoutExercise, set: Int) -> some View {
        let existing = logs.first { $0.exerciseId == exercise.id && $0.setNumber == set }
        return HStack {
            Text("Set \(set)")
                .font(TTFont.heading(14))
            Spacer()
            Text("\(item.reps) reps")
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.inkMuted)
            Button(existing == nil ? "Log" : "Done") {
                if existing == nil {
                    logs.append(
                        WorkoutSetLog(
                            id: UUID().uuidString,
                            exerciseId: exercise.id,
                            setNumber: set,
                            reps: item.reps,
                            weightKg: item.recommendedWeightKg ?? 0
                        )
                    )
                }
            }
            .font(TTFont.caption(13))
            .foregroundStyle(existing == nil ? TTColor.brand : TTColor.success)
        }
    }
}
