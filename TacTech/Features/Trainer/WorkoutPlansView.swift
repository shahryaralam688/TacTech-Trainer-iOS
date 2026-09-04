import SwiftUI

// MARK: - Workout Plans (Sandow / TacTech system design)

struct WorkoutPlansView: View {
    @Environment(AppStore.self) private var store
    @State private var showCreate = false
    @State private var query = ""

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                trainerListHeader(
                    title: "Workout Plans",
                    subtitle: "\(filtered.count) programs",
                    trailingIcon: .plus
                ) {
                    showCreate = true
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        searchField(placeholder: "Search plans")

                        if filtered.isEmpty {
                            emptyCard(
                                icon: .clipboard,
                                title: plans.isEmpty ? "No plans yet" : "No matches",
                                message: plans.isEmpty
                                    ? "Tap + to build a detailed weekly plan for your athletes."
                                    : "Try a different search."
                            )
                        } else {
                            ForEach(filtered) { plan in
                                NavigationLink {
                                    WorkoutPlanDetailView(plan: plan)
                                } label: {
                                    planCard(plan)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .sheet(isPresented: $showCreate) {
                CreatePlanView()
            }
        }
    }

    private var plans: [WorkoutPlan] {
        store.plans.filter { $0.trainerId == store.currentTrainer?.id }
    }

    private var filtered: [WorkoutPlan] {
        guard !query.isEmpty else { return plans }
        return plans.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.focus.localizedCaseInsensitiveContains(query)
                || $0.level.localizedCaseInsensitiveContains(query)
        }
    }

    private func planCard(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TTColor.actionOrange.opacity(0.12))
                    TTIcon(icon: .barbellDiagonal, filled: true, size: 20)
                        .foregroundStyle(TTColor.actionOrange)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .multilineTextAlignment(.leading)
                    Text(plan.focus)
                        .font(TTFont.textSM(.medium))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(plan.level)
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .foregroundStyle(TTColor.actionOrange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(plan.scheduleLine)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.actionOrange)

            HStack(spacing: 14) {
                metaChip(icon: .alarm, text: "\(plan.durationMinutes) min")
                metaChip(
                    icon: .calendar1,
                    text: plan.scheduledDays.isEmpty
                        ? "\(plan.daysPerWeek)× / week"
                        : "\(plan.scheduledDays.count) days"
                )
                metaChip(icon: .kettlebell, text: "\(plan.allExercises.count) moves")
                Spacer(minLength: 0)
                TTIcon(icon: .chevronRight, size: 16)
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func searchField(placeholder: String) -> some View {
        HStack(spacing: 10) {
            TTIcon(icon: .magnifyingGlass, size: 16)
                .foregroundStyle(TTColor.inkMuted)
            TextField(placeholder, text: $query)
                .font(TTFont.body(15))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metaChip(icon: SandowIcon, text: String) -> some View {
        HStack(spacing: 5) {
            TTIcon(icon: icon, size: 12)
            Text(text)
        }
        .font(TTFont.caption(12))
        .foregroundStyle(TTColor.inkMuted)
    }

    private func emptyCard(icon: SandowIcon, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            TTIcon(icon: icon, filled: true, size: 28)
                .foregroundStyle(TTColor.actionOrange)
            Text(title)
                .font(TTFont.workSans(17, weight: .bold))
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Plan Detail

struct WorkoutPlanDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    @State private var selectedTraineeId = ""

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(title: plan.title) { dismiss() }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    overviewCard

                    if plan.scheduledDays.isEmpty {
                        sectionLabel("Exercise plan")
                        ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, item in
                            ExercisePrescriptionCard(index: index + 1, item: item)
                        }
                    } else {
                        ForEach(plan.scheduledDays) { day in
                            PlanDayDetailCard(day: day)
                        }
                    }

                    if let trainer = store.currentTrainer {
                        sectionLabel("Assign")
                        assignCard(trainer: trainer)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .onAppear {
            if let trainer = store.currentTrainer {
                selectedTraineeId = store.trainees(for: trainer).first?.id ?? ""
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.focus)
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.actionOrange)
            Text("\(plan.level) · \(plan.scheduleLine)")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            if let notes = plan.notes, !notes.isEmpty {
                Text(notes)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func assignCard(trainer: TrainerProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Trainee", selection: $selectedTraineeId) {
                ForEach(store.trainees(for: trainer)) { trainee in
                    Text(store.user(forTrainee: trainee)?.name ?? "Trainee").tag(trainee.id)
                }
            }
            .pickerStyle(.menu)

            Button {
                Task { try? await store.assign(planId: plan.id, to: selectedTraineeId) }
            } label: {
                HStack(spacing: 8) {
                    Text("Assign this plan")
                        .font(TTFont.workSans(16, weight: .semibold))
                    TTIcon(icon: .check, filled: true, size: 14)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(selectedTraineeId.isEmpty)
            .opacity(selectedTraineeId.isEmpty ? 0.45 : 1)
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

struct PlanDayDetailCard: View {
    let day: PlanDay

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.weekday.title)
                    .font(TTFont.workSans(17, weight: .bold))
                Spacer()
                Text(day.timeLabel)
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
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
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .font(TTFont.workSans(13, weight: .bold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 28, height: 28)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise?.name ?? "Exercise")
                        .font(TTFont.workSans(15, weight: .semibold))
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
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// Shared trainer list header (Plans / Trainees)
@ViewBuilder
func trainerListHeader(
    title: String,
    subtitle: String,
    trailingIcon: SandowIcon,
    action: @escaping () -> Void
) -> some View {
    let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TTFont.headingLG(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(TTFont.textSM(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button(action: action) {
                TTIcon(icon: trailingIcon, filled: true, size: 18)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(TTColor.actionOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, 14)
    .padding(.bottom, 28)
    .frame(maxWidth: .infinity, minHeight: TTDarkPageHeader.cardHeight, alignment: .bottomLeading)
    .background {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: TTDarkPageHeader.bottomRadius,
            bottomTrailingRadius: TTDarkPageHeader.bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(charcoal)
        .ignoresSafeArea(edges: .top)
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
