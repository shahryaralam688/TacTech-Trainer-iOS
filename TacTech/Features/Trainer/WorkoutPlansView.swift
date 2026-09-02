import SwiftUI

struct WorkoutPlansView: View {
    @Environment(AppStore.self) private var store
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TTScreenHeader(
                        eyebrow: "Programming",
                        title: "Workout Plans",
                        trailing: AnyView(
                            Button {
                                showCreate = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(TTColor.surface)
                                    .frame(width: 40, height: 40)
                                    .background(TTColor.brand)
                                    .clipShape(Circle())
                            }
                        )
                    )
                    ForEach(plans) { plan in
                        NavigationLink {
                            WorkoutPlanDetailView(plan: plan)
                        } label: {
                            planCard(plan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCreate) {
                CreatePlanView()
            }
        }
    }

    private var plans: [WorkoutPlan] {
        store.plans.filter { $0.trainerId == store.currentTrainer?.id }
    }

    private func planCard(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(TTFont.title(18))
                        .foregroundStyle(TTColor.ink)
                    Text(plan.focus)
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer()
                Text(plan.level)
                    .font(TTFont.caption(11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TTColor.brandSoft)
                    .foregroundStyle(TTColor.brand)
                    .clipShape(Capsule())
            }
            HStack(spacing: 16) {
                label(icon: "clock", text: "\(plan.durationMinutes) min")
                label(icon: "calendar", text: "\(plan.daysPerWeek)x / week")
                label(icon: "dumbbell", text: "\(plan.exercises.count) moves")
            }
        }
        .ttCard()
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(TTFont.caption(12))
        .foregroundStyle(TTColor.inkMuted)
    }
}

struct WorkoutPlanDetailView: View {
    @Environment(AppStore.self) private var store
    let plan: WorkoutPlan
    @State private var selectedTraineeId = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.focus)
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.brand)
                    Text("\(plan.durationMinutes) min · \(plan.level) · \(plan.daysPerWeek) days")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }

                TTSectionHeader(title: "Exercise plan")
                ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, item in
                    let exercise = store.exercise(id: item.exerciseId)
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(TTFont.heading(14))
                            .foregroundStyle(TTColor.brand)
                            .frame(width: 32, height: 32)
                            .background(TTColor.brandSoft)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise?.name ?? "Exercise")
                                .font(TTFont.heading(15))
                            Text("\(item.sets) sets · \(item.reps) reps · \(item.restSeconds)s rest")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        Spacer()
                        if let kg = item.recommendedWeightKg {
                            Text("\(Int(kg)) kg")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                    }
                    .ttCard()
                }

                if let trainer = store.currentTrainer {
                    TTSectionHeader(title: "Assign")
                    Picker("Trainee", selection: $selectedTraineeId) {
                        ForEach(store.trainees(for: trainer)) { trainee in
                            Text(store.user(forTrainee: trainee)?.name ?? "Trainee").tag(trainee.id)
                        }
                    }
                    .pickerStyle(.menu)
                    TTButton(title: "Assign this plan") {
                        store.assign(planId: plan.id, to: selectedTraineeId)
                    }
                }
            }
            .padding(20)
        }
        .ttScreenBackground()
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let trainer = store.currentTrainer {
                selectedTraineeId = store.trainees(for: trainer).first?.id ?? ""
            }
        }
    }
}

struct CreatePlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var focus = ""
    @State private var duration = 45
    @State private var level = "Intermediate"
    @State private var days = 3
    @State private var selectedExerciseIds: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Title", text: $title)
                    TextField("Focus", text: $focus)
                    Stepper("Duration \(duration) min", value: $duration, in: 20...90, step: 5)
                    Picker("Level", selection: $level) {
                        ForEach(["Beginner", "Intermediate", "Advanced"], id: \.self) { Text($0) }
                    }
                    Stepper("\(days) days / week", value: $days, in: 1...6)
                }
                Section("Exercises") {
                    ForEach(store.exercises) { exercise in
                        Button {
                            if let index = selectedExerciseIds.firstIndex(of: exercise.id) {
                                selectedExerciseIds.remove(at: index)
                            } else {
                                selectedExerciseIds.append(exercise.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(exercise.name)
                                    Text("\(exercise.muscleGroup) · \(exercise.equipment)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedExerciseIds.contains(exercise.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(TTColor.brand)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let drafts = selectedExerciseIds.map {
                            WorkoutExercise(id: UUID().uuidString, exerciseId: $0, sets: 3, reps: 10, restSeconds: 75, recommendedWeightKg: nil)
                        }
                        store.createPlan(title: title, focus: focus, duration: duration, level: level, days: days, exerciseDrafts: drafts)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedExerciseIds.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
