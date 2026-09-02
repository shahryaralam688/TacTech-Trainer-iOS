import SwiftUI

struct TraineeDetailView: View {
    @Environment(AppStore.self) private var store
    let trainee: TraineeProfile
    @State private var selectedPlanId: String = ""
    @State private var note = ""
    @State private var selectedDay = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileCard
                assignCard
                nutritionCard
                historyCard
                formCard
                feedbackCard
            }
            .padding(20)
        }
        .ttScreenBackground()
        .navigationTitle(store.user(forTrainee: trainee)?.name ?? "Trainee")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedPlanId = store.assignedPlan(for: trainee)?.id ?? store.plans.first?.id ?? ""
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TTAvatar(name: store.user(forTrainee: trainee)?.name ?? "T", size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.user(forTrainee: trainee)?.name ?? "Trainee")
                        .font(TTFont.title(20))
                    Text(trainee.goal)
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            HStack {
                stat("Weight", "\(Int(trainee.weightKg)) kg")
                stat("Height", "\(trainee.heightCm) cm")
                stat("Target", "\(trainee.dailyCalorieTarget) kcal")
            }
        }
        .ttCard()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(TTFont.caption(10))
                .foregroundStyle(TTColor.inkSubtle)
            Text(value)
                .font(TTFont.heading(14))
                .foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assignCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Assigned plan")
            Picker("Plan", selection: $selectedPlanId) {
                ForEach(store.plans.filter { $0.trainerId == store.currentTrainer?.id }) { plan in
                    Text(plan.title).tag(plan.id)
                }
            }
            .pickerStyle(.menu)
            .tint(TTColor.brand)
            TTButton(title: "Assign to trainee", icon: "arrow.right.square") {
                store.assign(planId: selectedPlanId, to: trainee.id)
            }
        }
        .ttCard()
    }

    private var nutritionCard: some View {
        let macros = store.dailyMacros(for: trainee.id, on: selectedDay)
        return VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Nutrition")
            TTWeekStrip(selected: $selectedDay)
            HStack {
                macro("Cal", "\(macros.calories)", TTColor.calorie)
                macro("P", String(format: "%.0f", macros.protein), TTColor.protein)
                macro("C", String(format: "%.0f", macros.carbs), TTColor.carbs)
                macro("F", String(format: "%.0f", macros.fat), TTColor.fat)
            }
            ForEach(store.meals(for: trainee.id, on: selectedDay)) { meal in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name)
                            .font(TTFont.heading(14))
                        Text(meal.isEstimate ? "Estimate · \(Int(meal.portionGrams)) g" : "\(Int(meal.portionGrams)) g")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer()
                    Text("\(meal.macros.calories) kcal")
                        .font(TTFont.heading(14))
                }
            }
        }
        .ttCard()
    }

    private func macro(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TTFont.heading(16))
                .foregroundStyle(tint)
            Text(title)
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Workout history")
            let logs = store.logs(for: trainee.id)
            if logs.isEmpty {
                Text("No sessions logged yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(logs.prefix(5)) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.plans.first { $0.id == log.planId }?.title ?? "Workout")
                                .font(TTFont.heading(14))
                            Text(log.completedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        Spacer()
                        Text("\(log.durationMinutes) min")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.brand)
                    }
                }
            }
        }
        .ttCard()
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Form analysis")
            let reports = store.formReports(for: trainee.id)
            if reports.isEmpty {
                Text("No live form sessions yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(store.exercise(id: report.exerciseId)?.name ?? "Exercise")
                                .font(TTFont.heading(14))
                            Spacer()
                            Text("\(report.score)")
                                .font(TTFont.heading(16))
                                .foregroundStyle(report.score >= 80 ? TTColor.success : TTColor.brand)
                        }
                        Text(report.cues.joined(separator: " · "))
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
            }
        }
        .ttCard()
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Feedback")
            ForEach(store.feedback(for: trainee.id).prefix(3)) { item in
                Text(item.message)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.ink)
                    + Text("  \(item.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            TextField("Write a note for this trainee", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(TTColor.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            TTButton(title: "Send feedback", icon: "paperplane.fill") {
                guard let trainer = store.currentTrainer, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                store.saveFeedback(
                    TrainerFeedback(
                        id: UUID().uuidString,
                        trainerId: trainer.id,
                        traineeId: trainee.id,
                        message: note,
                        createdAt: .now,
                        relatedExerciseId: nil
                    )
                )
                note = ""
            }
        }
        .ttCard()
    }
}
