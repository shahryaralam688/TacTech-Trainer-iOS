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
            Text(plan.scheduleLine)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.brand)
            HStack(spacing: 16) {
                label(icon: "clock", text: "\(plan.durationMinutes) min")
                label(icon: "calendar", text: plan.scheduledDays.isEmpty ? "\(plan.daysPerWeek)x / week" : "\(plan.scheduledDays.count) days")
                label(icon: "dumbbell", text: "\(plan.allExercises.count) moves")
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
                    Text("\(plan.level) · \(plan.scheduleLine)")
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                    if let notes = plan.notes, !notes.isEmpty {
                        Text(notes)
                            .font(TTFont.body(14))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }

                if plan.scheduledDays.isEmpty {
                    TTSectionHeader(title: "Exercise plan")
                    ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, item in
                        ExercisePrescriptionCard(index: index + 1, item: item)
                    }
                } else {
                    ForEach(plan.scheduledDays) { day in
                        PlanDayDetailCard(day: day)
                    }
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
                        Task { try? await store.assign(planId: plan.id, to: selectedTraineeId) }
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

struct PlanDayDetailCard: View {
    let day: PlanDay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.weekday.title)
                    .font(TTFont.title(18))
                Spacer()
                Text(day.timeLabel)
                    .font(TTFont.heading(14))
                    .foregroundStyle(TTColor.brand)
            }
            Text("\(day.title) · \(day.durationMinutes) min · \(day.location ?? "Gym")")
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.inkMuted)
            if !day.focus.isEmpty {
                Text(day.focus)
                    .font(TTFont.body(14))
            }
            if let notes = day.coachNotes, !notes.isEmpty {
                labeled("How to do this day", notes)
            }
            if let warmup = day.warmup, !warmup.isEmpty {
                labeled("Warm-up", warmup)
            }
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, item in
                ExercisePrescriptionCard(index: index + 1, item: item)
            }
            if let cooldown = day.cooldown, !cooldown.isEmpty {
                labeled("Cool-down", cooldown)
            }
        }
        .ttCard()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(TTFont.caption(10))
                .foregroundStyle(TTColor.inkSubtle)
            Text(value)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
        }
    }
}

struct ExercisePrescriptionCard: View {
    @Environment(AppStore.self) private var store
    let index: Int
    let item: WorkoutExercise

    var body: some View {
        let exercise = store.exercise(id: item.exerciseId)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index)")
                    .font(TTFont.heading(13))
                    .foregroundStyle(TTColor.brand)
                    .frame(width: 28, height: 28)
                    .background(TTColor.brandSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise?.name ?? "Exercise")
                        .font(TTFont.heading(15))
                    Text(item.prescriptionLine)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            ForEach(item.workingSets) { set in
                HStack {
                    Text("Set \(set.setNumber)")
                    Spacer()
                    Text("\(set.reps) reps")
                    Text(set.weightKg.map { "\($0.cleanKg) kg" } ?? "bodyweight")
                }
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            }
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.ink)
            }
        }
        .padding(10)
        .background(TTColor.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview("Workout Plans") {
    WorkoutPlansView()
        .ttPreviewTrainer()
}

#Preview("Plan Detail") {
    NavigationStack {
        WorkoutPlanDetailView(plan: TTPreview.samplePlan)
            .ttPreviewTrainer()
    }
}
