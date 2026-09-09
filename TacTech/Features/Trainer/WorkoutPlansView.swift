import SwiftUI

// MARK: - Workout Plans (Sandow / TacTech system design)

struct WorkoutPlansView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var searchNS
    @State private var showCreate = false
    @State private var showSearch = false
    @State private var query = ""
    @State private var focusFilter: String?
    @State private var selectedPlan: WorkoutPlan?
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let scrollSpace = "workoutPlans"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                trainerListHeader(
                    title: "Workout Plans",
                    subtitle: "\(filtered.count) programs",
                    trailingIcon: .plus,
                    collapseProgress: scrollCollapse.progress
                ) {
                    showCreate = true
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TTHomeScrollCollapseProbe(model: scrollCollapse, space: scrollSpace)

                        VStack(alignment: .leading, spacing: 12) {
                            TTSearchEntryPill(
                                placeholder: TTSearchCopy.plans.pillPlaceholder,
                                query: displayQuery,
                                namespace: searchNS
                            ) {
                                showSearch = true
                            }

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
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
                .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
                .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
            }
            .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .sheet(isPresented: $showCreate) {
                CreatePlanView()
            }
            .navigationDestination(item: $selectedPlan) { plan in
                WorkoutPlanDetailView(plan: plan)
            }
            .ttSearchOverlay(
                isPresented: $showSearch,
                catalog: searchCatalog,
                namespace: searchNS,
                onOutcome: handleSearchOutcome
            )
        }
    }

    private var plans: [WorkoutPlan] {
        store.plans.filter { $0.trainerId == store.currentTrainer?.id }
    }

    private var searchCatalog: TTSearchCatalog {
        TTSearchCatalog.workoutPlans(
            plans: plans,
            trainerId: store.currentTrainer?.id ?? "local"
        )
    }

    private var displayQuery: String {
        if !query.isEmpty { return query }
        if let focusFilter { return focusFilter }
        return ""
    }

    private var filtered: [WorkoutPlan] {
        var result = plans
        if let focusFilter {
            result = result.filter { $0.focus.lowercased() == focusFilter.lowercased() }
        }
        guard !query.isEmpty else { return result }
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.focus.localizedCaseInsensitiveContains(query)
                || $0.level.localizedCaseInsensitiveContains(query)
        }
    }

    private func handleSearchOutcome(_ outcome: TTSearchOutcome) {
        switch outcome {
        case .item(let id):
            query = ""
            focusFilter = nil
            selectedPlan = plans.first { $0.id == id }
        case .category(let id):
            query = ""
            focusFilter = id
        case .offer:
            if plans.isEmpty {
                showCreate = true
            } else {
                selectedPlan = plans.first
            }
        case .applyQuery(let q):
            focusFilter = nil
            query = q
        case .dismissed:
            break
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
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let scrollSpace = "workoutPlanDetail"

    var body: some View {
        VStack(spacing: 0) {
            TTDarkPageHeader(
                title: plan.title,
                collapseProgress: scrollCollapse.progress
            ) {
                dismiss()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    TTHomeScrollCollapseProbe(model: scrollCollapse, space: scrollSpace)

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
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
            .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
        }
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
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
        let trainees = store.trainees(for: trainer)
        return VStack(alignment: .leading, spacing: 12) {
            if trainees.isEmpty {
                Text("No trainees on your roster yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Picker("Trainee", selection: $selectedTraineeId) {
                    Text("Select trainee").tag("")
                    ForEach(trainees) { trainee in
                        Text(store.user(forTrainee: trainee)?.name ?? "Trainee").tag(trainee.id)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    if selectedTraineeId.isEmpty || !trainees.contains(where: { $0.id == selectedTraineeId }) {
                        selectedTraineeId = trainees.first?.id ?? ""
                    }
                }
            }

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

// Shared trainer list header (Plans / Trainees) — shrinks on scroll like home.
@ViewBuilder
func trainerListHeader(
    title: String,
    subtitle: String,
    trailingIcon: SandowIcon,
    collapseProgress: CGFloat = 0,
    isMenuOpen: Bool = false,
    action: @escaping () -> Void
) -> some View {
    let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    let p = min(1, max(0, collapseProgress))
    let expand = 1 - p
    let compactHeight: CGFloat = 64
    let headerHeight = compactHeight + (TTDarkPageHeader.cardHeight - compactHeight) * expand

    VStack(alignment: .leading, spacing: 10 * expand) {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4 * expand) {
                Text(title)
                    .font(TTFont.workSans(28 - 8 * p, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(subtitle)
                    .font(TTFont.textSM(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .opacity(Double(expand))
                    .frame(height: 18 * expand, alignment: .top)
                    .clipped()
            }

            Spacer(minLength: 8)

            Button(action: action) {
                TTIcon(icon: trailingIcon, filled: true, size: 18 - 2 * p)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(isMenuOpen ? 45 : 0))
                    .frame(width: 44 - 4 * p, height: 44 - 4 * p)
                    .background(isMenuOpen ? Color.black : TTColor.actionOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14 - 2 * p, style: .continuous))
                    .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isMenuOpen)
            }
            .buttonStyle(.plain)
            .opacity(isMenuOpen ? 0 : 1)
            .allowsHitTesting(!isMenuOpen)
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, 14 - 4 * p)
    .padding(.bottom, 20 - 8 * p)
    .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .bottomLeading)
    .background {
        Rectangle()
            .fill(charcoal)
            .ignoresSafeArea(edges: .top)
    }
    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.9), value: p)
}

// MARK: - Quick assign / assignments list

struct PlanQuickAssignSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var planId = ""
    @State private var traineeId = ""

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var plans: [WorkoutPlan] {
        store.plans.filter { $0.trainerId == store.currentTrainer?.id }
    }

    private var trainees: [TraineeProfile] {
        guard let trainer = store.currentTrainer else { return [] }
        return store.trainees(for: trainer)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                section("Plan") {
                    Picker("Plan", selection: $planId) {
                        Text("Select plan").tag("")
                        ForEach(plans) { plan in
                            Text(plan.title).tag(plan.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                section("Trainee") {
                    Picker("Trainee", selection: $traineeId) {
                        Text("Select trainee").tag("")
                        ForEach(trainees) { trainee in
                            Text(store.user(forTrainee: trainee)?.name ?? "Trainee").tag(trainee.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()

                Button {
                    Task {
                        try? await store.assign(planId: planId, to: traineeId)
                        dismiss()
                    }
                } label: {
                    Text("Assign plan")
                        .font(TTFont.workSans(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(planId.isEmpty || traineeId.isEmpty)
                .opacity(planId.isEmpty || traineeId.isEmpty ? 0.45 : 1)
            }
            .padding(20)
            .background(Color(white: 0.97).ignoresSafeArea())
            .navigationTitle("Assign to trainee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if planId.isEmpty { planId = plans.first?.id ?? "" }
                if traineeId.isEmpty { traineeId = trainees.first?.id ?? "" }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(TTFont.workSans(14, weight: .bold))
                .foregroundStyle(TTColor.ink)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// Roster of which trainee currently has which plan.
struct PlanAssignmentsListSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private struct Row: Identifiable {
        let id: String
        let traineeName: String
        let planTitle: String
        let assignedAt: Date?
        let hasPlan: Bool
    }

    private var rows: [Row] {
        guard let trainer = store.currentTrainer else { return [] }
        return store.trainees(for: trainer).map { trainee in
            let plan = store.assignedPlan(for: trainee)
            let assignment = store.assignments
                .filter { $0.traineeId == trainee.id }
                .sorted { $0.assignedAt > $1.assignedAt }
                .first
            return Row(
                id: trainee.id,
                traineeName: store.user(forTrainee: trainee)?.name ?? "Trainee",
                planTitle: plan?.title ?? "No plan assigned",
                assignedAt: assignment?.assignedAt,
                hasPlan: plan != nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasPlan != rhs.hasPlan { return lhs.hasPlan && !rhs.hasPlan }
            return lhs.traineeName.localizedCaseInsensitiveCompare(rhs.traineeName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    VStack(spacing: 12) {
                        TTIcon(icon: .usersTwo, filled: true, size: 28)
                            .foregroundStyle(TTColor.actionOrange)
                        Text("No trainees yet")
                            .font(TTFont.workSans(17, weight: .bold))
                        Text("When athletes join your roster, their assigned plans show up here.")
                            .font(TTFont.body(14))
                            .foregroundStyle(TTColor.inkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(rows) { row in
                                assignmentRow(row)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 12)
                    }
                }
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle("Plan assignments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func assignmentRow(_ row: Row) -> some View {
        HStack(spacing: 12) {
            TTAvatar(name: row.traineeName, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.traineeName)
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text(row.planTitle)
                    .font(TTFont.caption(13))
                    .foregroundStyle(row.hasPlan ? TTColor.actionOrange : TTColor.inkMuted)
                    .lineLimit(2)
                if let date = row.assignedAt, row.hasPlan {
                    Text("Assigned \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }
            }

            Spacer(minLength: 8)

            Text(row.hasPlan ? "Active" : "Idle")
                .font(TTFont.caption(11))
                .fontWeight(.bold)
                .foregroundStyle(row.hasPlan ? TTColor.success : TTColor.inkMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((row.hasPlan ? TTColor.success : TTColor.inkMuted).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

#Preview("Assignments list") {
    PlanAssignmentsListSheet()
        .ttPreviewTrainer()
}
