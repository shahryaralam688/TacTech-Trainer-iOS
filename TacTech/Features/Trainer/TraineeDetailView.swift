import SwiftUI

struct TraineeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trainee: TraineeProfile
    @State private var note = ""
    @State private var selectedDay = Date()
    @FocusState private var noteFocused: Bool
    @State private var showAssignSheet = false
    @State private var previousPlanId: String?
    @State private var viewedPlan: WorkoutPlan?
    @State private var celebrateAssign = false
    @State private var feedbackToast: TTToastMessage?
    @State private var unassignConfirm = false
    @State private var isUnassigning = false
    @State private var removeConfirm = false
    @State private var isRemoving = false
    @State private var performanceTab: TraineeDetailPerformanceTab = .history
    @State private var isRefreshingPerformance = false
    @State private var performanceError: String?
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let scrollSpace = "traineeDetail"

    private var displayName: String {
        store.user(forTrainee: trainee)?.name ?? "Trainee"
    }

    private var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    private var currentAssignedPlan: WorkoutPlan? {
        store.assignedPlan(for: trainee)
    }

    private var analytics: TraineeAnalytics? {
        store.analytics(for: trainee.id)
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
                        performancePicker

                        Group {
                            switch performanceTab {
                            case .history:
                                TraineeDetailHistorySection(trainee: trainee, analytics: analytics)
                            case .analytics:
                                TraineeDetailAnalyticsSection(
                                    trainee: trainee,
                                    analytics: analytics,
                                    loadError: performanceError
                                )
                            case .meals:
                                nutritionCard
                            }
                        }

                        sectionLabel("Form analysis")
                        formCard
                        sectionLabel("Feedback")
                        feedbackCard

                        // Destructive, rarely used → last, with breathing room above.
                        sectionLabel("Roster")
                            .padding(.top, 32)
                        removeFromRosterCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
            .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await reloadPerformance(forceErrorSurface: true)
                await store.refreshDay(for: trainee.id, on: selectedDay)
            }
        }
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .onChange(of: store.trainees.map(\.id)) { _, ids in
            // Peer leave / remote remove — detail is stale; pop without force-quit.
            if !ids.contains(trainee.id) {
                dismiss()
            }
        }
        .task(id: trainee.id) {
            await reloadPerformance(forceErrorSurface: false)
        }
        .task(id: selectedDay) {
            await store.refreshDay(for: trainee.id, on: selectedDay)
        }
        .ttAssignSuccessChrome(toast: $feedbackToast, celebrate: $celebrateAssign)
        .navigationDestination(item: $viewedPlan) { plan in
            WorkoutPlanDetailView(plan: plan)
        }
        .sheet(isPresented: $showAssignSheet) {
            PlanQuickAssignSheet(preselectedTraineeId: trainee.id, onAssigned: {
                showAssignedToast()
            })
            .ttModalSheetPresentation()
        }
        .confirmationDialog(
            "Unassign this plan?",
            isPresented: $unassignConfirm,
            titleVisibility: .visible
        ) {
            Button("Unassign", role: .destructive) {
                Task { await unassignCurrentPlan() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(displayName) will no longer see this plan as their assigned program.")
        }
        .confirmationDialog(
            "Remove from roster?",
            isPresented: $removeConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove from roster", role: .destructive) {
                guard !isRemoving else { return }
                Task { @MainActor in
                    await removeFromRoster()
                }
            }
            .disabled(isRemoving)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(displayName) from your roster? Their assigned plan will be cleared. Chat stays.")
        }
    }

    private var removeFromRosterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ends the coaching relationship. This is different from Unassign, which only removes the plan.")
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                removeConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isRemoving {
                        ProgressView()
                    } else {
                        Text("Remove from roster")
                            .font(TTFont.workSans(14, weight: .bold))
                    }
                }
                .foregroundStyle(TTColor.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(TTColor.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRemoving)
            .accessibilityLabel("Remove trainee from roster")
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var performancePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Performance")
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer()
                if isRefreshingPerformance {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Picker("Performance", selection: $performanceTab) {
                ForEach(TraineeDetailPerformanceTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.top, 4)
    }

    private func reloadPerformance(forceErrorSurface: Bool) async {
        isRefreshingPerformance = true
        defer { isRefreshingPerformance = false }
        do {
            try await store.refreshTraineePerformance(traineeId: trainee.id)
            performanceError = nil
        } catch let error as AppError where error == .unauthorized {
            performanceError = error.localizedDescription
        } catch let error as AppError {
            if case .notFound = error {
                performanceError = "This trainee isn’t available on your roster."
            } else if forceErrorSurface || analytics == nil {
                performanceError = error.localizedDescription
            }
        } catch {
            if forceErrorSurface || analytics == nil {
                performanceError = error.localizedDescription
            }
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TTAvatar(name: displayName, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trainee.goal)
                        .font(TTFont.body(14))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }

            HStack {
                stat("Weight", "\(Int(trainee.weightKg)) kg")
                stat("Height", "\(trainee.heightCm) cm")
                stat("Calories", "\(trainee.dailyCalorieTarget) kcal")
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

    /// One plan card: assigning / changing always goes through PlanQuickAssignSheet.
    private var assignCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let assigned = currentAssignedPlan {
                assignedPlanSummary(assigned)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No plan yet")
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("Assign a plan so \(firstName) can start training. Their sessions will show up below.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    openAssignSheet()
                } label: {
                    // Standard primary button (same as the assign sheet): label left, arrow right.
                    HStack(spacing: 8) {
                        Text("Assign plan")
                            .font(TTFont.workSans(16, weight: .bold))
                        Spacer(minLength: 8)
                        TTIcon(icon: .chevronRight, size: 14)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.98))
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func openAssignSheet() {
        previousPlanId = currentAssignedPlan?.id
        showAssignSheet = true
    }

    /// Same pattern as Home: toast after the sheet closes, Undo restores the previous state.
    private func showAssignedToast() {
        guard let newPlan = store.assignedPlan(for: trainee) else { return }
        let first = displayName.split(separator: " ").first.map(String.init) ?? displayName
        let previous = previousPlanId
        feedbackToast = TTToastMessage(
            text: "“\(newPlan.title)” assigned to \(first)",
            action: TTToastAction(title: "Undo") {
                Task {
                    do {
                        if let previous {
                            try await store.assign(planId: previous, to: trainee.id)
                        } else {
                            try await store.unassign(planId: newPlan.id, from: trainee.id)
                        }
                        feedbackToast = TTToastMessage(text: "Undone")
                    } catch {
                        feedbackToast = TTToastMessage(text: "Couldn’t undo", style: .error, subtitle: error.localizedDescription)
                    }
                }
            }
        )
    }

    private func assignedPlanSummary(_ plan: WorkoutPlan) -> some View {
        let status = store.planFollowStatus(traineeId: trainee.id, plan: plan)
        let adherence = store.planAdherencePercent(traineeId: trainee.id, plan: plan)
        let statusColor = followStatusColor(status)
        let last = store.lastPlanWorkoutDate(traineeId: trainee.id, planId: plan.id)
        let assignmentDate = store.assignments
            .filter { $0.traineeId == trainee.id && $0.planId == plan.id }
            .map(\.assignedAt)
            .max()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT PLAN")
                        .font(TTFont.caption(10))
                        .fontWeight(.bold)
                        .tracking(0.6)
                        .foregroundStyle(TTColor.actionOrange)
                    Text(plan.title)
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("\(plan.level) · \(plan.focus)")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                    Text(plan.scheduleLine)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(status.title)
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                Text("\(adherence)% follow")
                    .font(TTFont.caption(12))
                    .fontWeight(.semibold)
                    .foregroundStyle(TTColor.inkMuted)
                Text("·")
                    .foregroundStyle(TTColor.inkSubtle)
                if let last {
                    Text("Last \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                } else {
                    Text("No workouts logged")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }

            if let assignmentDate {
                Text("Assigned \(assignmentDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.06))
                    Capsule()
                        .fill(statusColor)
                        .frame(width: max(4, geo.size.width * CGFloat(adherence) / 100))
                }
            }
            .frame(height: 4)

            Button {
                openAssignSheet()
            } label: {
                Text("Change plan")
                    .font(TTFont.workSans(14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    viewedPlan = plan
                } label: {
                    Text("View plan")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    unassignConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        if isUnassigning {
                            ProgressView()
                        } else {
                            Text("Unassign")
                                .font(TTFont.workSans(13, weight: .bold))
                        }
                    }
                    .foregroundStyle(TTColor.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(TTColor.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isUnassigning)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func followStatusColor(_ status: PlanFollowStatus) -> Color {
        switch status {
        case .trainedToday: TTColor.success
        case .following: TTColor.actionOrange
        case .dueToday: Color(red: 0.95, green: 0.55, blue: 0.15)
        case .behind: TTColor.danger
        case .notStarted: TTColor.inkMuted
        }
    }

    private func unassignCurrentPlan() async {
        guard let plan = currentAssignedPlan else { return }
        isUnassigning = true
        defer { isUnassigning = false }
        do {
            try await store.unassign(planId: plan.id, from: trainee.id)
            TTAssignSuccessFeedback.playUnassign(toast: $feedbackToast, traineeName: displayName)
        } catch {
            feedbackToast = TTToastMessage(
                text: "Couldn’t unassign",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func removeFromRoster() async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        do {
            try await store.removeTrainee(traineeId: trainee.id)
            feedbackToast = TTToastMessage(
                text: "\(displayName) removed from roster",
                style: .success
            )
            // Brief pause so the success toast is visible before dismiss.
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        } catch {
            let detail = (error as? AppError)?.errorDescription
                ?? error.localizedDescription
            feedbackToast = TTToastMessage(
                text: detail.isEmpty ? "Couldn't remove trainee" : detail,
                style: .error
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
                            HStack(spacing: 6) {
                                Text("\(report.score)/100")
                                    .font(TTFont.workSans(16, weight: .bold))
                                    .foregroundStyle(report.score >= 80 ? TTColor.success : TTColor.actionOrange)
                                Text(report.score >= 80 ? "Good" : report.score >= 60 ? "Fair" : "Needs work")
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(TTColor.inkMuted)
                            }
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

            let canSend = !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                Task { await sendFeedback() }
            } label: {
                HStack(spacing: 8) {
                    Text("Send feedback")
                        .font(TTFont.workSans(16, weight: .semibold))
                    TTIcon(icon: .paperPlaneDiagonal, filled: true, size: 14)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canSend ? Color.black : Color(white: 0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Keeps the text on failure so nothing the coach wrote is lost.
    private func sendFeedback() async {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trainer = store.currentTrainer, !text.isEmpty else { return }
        do {
            try await store.saveFeedback(
                TrainerFeedback(
                    id: UUID().uuidString,
                    trainerId: trainer.id,
                    traineeId: trainee.id,
                    message: text,
                    createdAt: .now,
                    relatedExerciseId: nil
                )
            )
            note = ""
            noteFocused = false
            feedbackToast = TTToastMessage(text: "Note sent to \(firstName)")
        } catch {
            feedbackToast = TTToastMessage(text: "Couldn’t send. Try again.", style: .error)
        }
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
