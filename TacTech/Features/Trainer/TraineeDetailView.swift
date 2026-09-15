import SwiftUI

struct TraineeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trainee: TraineeProfile
    @State private var selectedPlanId: String = ""
    @State private var note = ""
    @State private var selectedDay = Date()
    @FocusState private var noteFocused: Bool
    @State private var isAssigning = false
    @State private var assignSucceeded = false
    @State private var celebrateAssign = false
    @State private var feedbackToast: TTToastMessage?
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let scrollSpace = "traineeDetail"

    private var displayName: String {
        store.user(forTrainee: trainee)?.name ?? "Trainee"
    }

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(
                title: displayName,
                collapseProgress: scrollCollapse.progress
            ) {
                dismiss()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TTHomeScrollCollapseProbe(model: scrollCollapse, space: scrollSpace)

                    VStack(alignment: .leading, spacing: 12) {
                        profileCard
                        sectionLabel("Assigned plan")
                        assignCard
                        sectionLabel("Nutrition")
                        nutritionCard
                        sectionLabel("Workout history")
                        historyCard
                        sectionLabel("Form analysis")
                        formCard
                        sectionLabel("Feedback")
                        feedbackCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
            .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .onAppear {
            selectedPlanId = store.assignedPlan(for: trainee)?.id ?? store.plans.first?.id ?? ""
        }
        .task(id: selectedDay) {
            await store.refreshDay(for: trainee.id, on: selectedDay)
        }
        .ttAssignSuccessChrome(toast: $feedbackToast, celebrate: $celebrateAssign)
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TTAvatar(name: displayName, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(TTFont.workSans(18, weight: .bold))
                        .foregroundStyle(TTColor.ink)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(TTFont.caption(10))
                .foregroundStyle(TTColor.inkSubtle)
            Text(value)
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assignCard: some View {
        let plans = store.plans.filter { $0.trainerId == store.currentTrainer?.id }
        return VStack(alignment: .leading, spacing: 12) {
            if plans.isEmpty {
                Text("No plans to assign yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Picker("Plan", selection: $selectedPlanId) {
                    Text("Select plan").tag("")
                    ForEach(plans) { plan in
                        Text(plan.title).tag(plan.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(TTColor.actionOrange)
                .onAppear {
                    if selectedPlanId.isEmpty || !plans.contains(where: { $0.id == selectedPlanId }) {
                        selectedPlanId = store.assignedPlan(for: trainee)?.id ?? plans.first?.id ?? ""
                    }
                }
            }

            TTAssignSuccessButton(
                title: "Assign to trainee",
                isEnabled: !selectedPlanId.isEmpty,
                isLoading: isAssigning,
                showSuccess: assignSucceeded
            ) {
                Task { await assignSelectedPlan() }
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func assignSelectedPlan() async {
        guard !selectedPlanId.isEmpty else { return }
        isAssigning = true
        defer { isAssigning = false }
        do {
            try await store.assign(planId: selectedPlanId, to: trainee.id)
            let planTitle = store.plans.first(where: { $0.id == selectedPlanId })?.title ?? "Plan"
            TTAssignSuccessFeedback.play(
                toast: $feedbackToast,
                celebrate: $celebrateAssign,
                planTitle: planTitle,
                traineeName: displayName
            )
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                assignSucceeded = true
            }
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeOut(duration: 0.2)) {
                assignSucceeded = false
            }
        } catch {
            feedbackToast = TTToastMessage(
                text: "Couldn’t assign plan",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    private var nutritionCard: some View {
        let macros = store.dailyMacros(for: trainee.id, on: selectedDay)
        return VStack(alignment: .leading, spacing: 12) {
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
                            .font(TTFont.workSans(14, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                        Text(meal.isEstimate ? "Estimate · \(Int(meal.portionGrams)) g" : "\(Int(meal.portionGrams)) g")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer()
                    Text("\(meal.macros.calories) kcal")
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                }
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func macro(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TTFont.workSans(16, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var historyCard: some View {
        let logs = store.logs(for: trainee.id)
        return VStack(alignment: .leading, spacing: 12) {
            if logs.isEmpty {
                Text("No sessions logged yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(logs.prefix(5)) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.plans.first { $0.id == log.planId }?.title ?? "Workout")
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(TTColor.ink)
                            Text(log.completedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        Spacer()
                        Text("\(log.durationMinutes) min")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.actionOrange)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var formCard: some View {
        let reports = store.formReports(for: trainee.id)
        return VStack(alignment: .leading, spacing: 12) {
            if reports.isEmpty {
                Text("No live form sessions yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(store.exercise(id: report.exerciseId)?.name ?? "Exercise")
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(TTColor.ink)
                            Spacer()
                            Text("\(report.score)")
                                .font(TTFont.workSans(16, weight: .bold))
                                .foregroundStyle(report.score >= 80 ? TTColor.success : TTColor.actionOrange)
                        }
                        Text(report.cues.joined(separator: " · "))
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .focused($noteFocused)
                .tint(TTColor.actionOrange)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(noteFocused ? TTColor.actionOrange : Color.clear, lineWidth: 1.5)
                )

            Button {
                guard let trainer = store.currentTrainer, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let text = note
                note = ""
                Task {
                    try? await store.saveFeedback(
                        TrainerFeedback(
                            id: UUID().uuidString,
                            trainerId: trainer.id,
                            traineeId: trainee.id,
                            message: text,
                            createdAt: .now,
                            relatedExerciseId: nil
                        )
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Send feedback")
                        .font(TTFont.workSans(16, weight: .semibold))
                    TTIcon(icon: .paperPlaneDiagonal, filled: true, size: 14)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(TTFont.workSans(15, weight: .bold))
            .foregroundStyle(TTColor.ink)
            .padding(.top, 4)
    }
}

#Preview("Trainee Detail") {
    NavigationStack {
        TraineeDetailView(trainee: TTPreview.sampleTrainee)
            .ttPreviewTrainer()
    }
}
