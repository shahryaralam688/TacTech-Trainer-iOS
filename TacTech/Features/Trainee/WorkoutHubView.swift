import SwiftUI

// MARK: - Trainee Workout Hub (Sandow / TacTech system design)

private enum TraineeWorkoutTab: String, CaseIterable, Identifiable {
    case today, plan, progress
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .plan: "Plan"
        case .progress: "Progress"
        }
    }
}

private struct WorkoutHubCollapsedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct WorkoutHubView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When presented as a sheet from Home, show a back control.
    var showsCloseChrome: Bool = false

    @State private var selectedTab: TraineeWorkoutTab = .today
    @State private var selectedDay = Date()
    @State private var isWeekExpanded = false
    /// Height of the fully collapsed header — the stacked cards pin directly below it.
    @State private var collapsedHeaderHeight: CGFloat = 0
    @State private var showDeleteAIConfirm = false
    @State private var isMutatingAIPlan = false
    @State private var hubToast: TTToastMessage?
    @State private var editingPlan: WorkoutPlan?
    @State private var deletingPlan: WorkoutPlan?
    @State private var showAssessmentReview = false

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = TTColor.charcoal
    private let orange = TTColor.actionOrange
    private let scrollSpace = "traineeWorkout"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                // Header is drawn over the scroll view; the content size never depends on its collapse.
                // Pinned segmented tab bar sticks directly under the collapsed header (same as Trainer's TraineeDetailView).
                TTCollapsingHeaderScreen(
                    sheetFill: canvas,
                    headerBackground: charcoal,
                    topRadius: { _ in TTSheetChrome.pageTopRadius },
                    pinsBelowCollapsedHeader: true,
                    topAnchorID: "workoutTop",
                    onRefresh: { await store.refreshAssignedPlanForCurrentTrainee() },
                    header: { progress in header(progress: progress) }
                ) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if let notice = store.planChangeNotice {
                            planChangeNoticeChip(notice)
                                .padding(.horizontal, TTSpace.screen)
                                .padding(.top, 14)
                        }

                        if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
                            Section {
                                tabContent(plan: plan, trainee: trainee)
                                    .padding(.horizontal, TTSpace.screen)
                                    .padding(.top, 12)
                                    .padding(.bottom, 36)
                            } header: {
                                pinnedTabBar(proxy: proxy)
                            }
                        } else {
                            emptyCard
                                .padding(.horizontal, TTSpace.screen)
                                .padding(.top, 16)
                                .padding(.bottom, 36)
                        }
                    }
                }
            }
            // The stacked cards measure their position in this space: its top is the screen content's top,
            // the same place the header is drawn from.
            .coordinateSpace(name: scrollSpace)
            .overlay(alignment: .top) {
                // Hidden copy of the collapsed header, only to measure where the pin line has to be.
                header(progress: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { Color.clear.preference(key: WorkoutHubCollapsedHeightKey.self, value: $0.size.height) })
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onPreferenceChange(WorkoutHubCollapsedHeightKey.self) { value in
                if abs(value - collapsedHeaderHeight) > 0.5 { collapsedHeaderHeight = value }
            }
            .background(charcoal.ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .ttSyncRootTabBarWithNavigationDepth()
            .ttToast($hubToast, bottomInset: 28)
            .task(id: store.currentTrainee?.id) {
                await store.refreshAssignedPlanForCurrentTrainee()
            }
            .sheet(item: $editingPlan) { plan in
                CreatePlanView(editingPlan: plan)
                    .ttModalSheetPresentation()
            }
            .confirmationDialog(
                "Delete this AI plan?",
                isPresented: $showDeleteAIConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete plan", role: .destructive) {
                    Task { await deleteAIPlan() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your AI week. You can generate a new one anytime.")
            }
            .sheet(isPresented: $showAssessmentReview) {
                AssessmentReviewSheet(assessment: store.loadSavedFitnessAssessment()) {
                    hubToast = TTToastMessage(text: "AI week ready", style: .success)
                }
                .ttModalSheetPresentation()
            }
        }
    }

    private func planChangeNoticeChip(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(orange)
            Text(text)
                .font(TTFont.workSans(13, weight: .semibold))
                .foregroundStyle(TTColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                store.planChangeNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TTColor.inkSubtle)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Pinned Tabs (Today / Plan / Progress)

    private func pinnedTabBar(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Picker("Workout section", selection: Binding(
                get: { selectedTab },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = newValue
                        proxy.scrollTo("workoutTop", anchor: .top)
                    }
                }
            )) {
                ForEach(TraineeWorkoutTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, TTSpace.screen)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TTColor.ink.opacity(0.08))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func tabContent(plan: WorkoutPlan, trainee: TraineeProfile) -> some View {
        switch selectedTab {
        case .today:
            todayTab(plan: plan)
        case .plan:
            planTab(plan: plan, trainee: trainee)
        case .progress:
            progressTab(trainee: trainee, plan: plan)
        }
    }

    private func todayTab(plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            todayDateBar(plan: plan)
            sessionHero(plan)
            sessionDetail(plan)
            if store.aiCapabilities.visionPose {
            liveFormCard(plan)
        }
        }
    }

    private func todayDateBar(plan: WorkoutPlan) -> some View {
        let isToday = Calendar.current.isDateInToday(selectedDay)
        let dateText = selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(orange)
                            .frame(width: 30, height: 30)
                            .background(orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(isToday ? "Today" : relativeDayLabel(for: Weekday.from(date: selectedDay)))
                                .font(TTFont.workSans(14, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                            Text(dateText)
                                .font(TTFont.workSans(12, weight: .medium))
                                .foregroundStyle(TTColor.inkMuted)
                        }

                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                            isWeekExpanded.toggle()
                        }
                    }

                    HStack(spacing: 8) {
                        if !isToday {
                            Button("Today") {
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                    selectedDay = Date()
                                }
                            }
                            .font(TTFont.workSans(12, weight: .bold))
                            .foregroundStyle(orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(orange.opacity(0.12))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }

                        Button {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                isWeekExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(TTColor.inkSubtle)
                                .rotationEffect(.degrees(isWeekExpanded ? 180 : 0))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isWeekExpanded ? "Hide week calendar" : "Show week calendar")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if isWeekExpanded {
                TTHomeWeekDatePicker(
                    selected: $selectedDay,
                    accent: orange,
                    sessionDayKeys: sessionDayKeySet(plan)
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    )
                )
            }
        }
    }

    private func planTab(plan: WorkoutPlan, trainee: TraineeProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            planOverviewCard(plan)
            planAdherenceCard(plan: plan, trainee: trainee)
            planScheduleBreakdown(plan: plan)
        }
    }

    private func planAdherenceCard(plan: WorkoutPlan, trainee: TraineeProfile) -> some View {
        let status = store.planFollowStatus(traineeId: trainee.id, plan: plan)
        let adherence = store.planAdherencePercent(traineeId: trainee.id, plan: plan)
        let statusColor = followStatusColor(status)
        let last = store.lastPlanWorkoutDate(traineeId: trainee.id, planId: plan.id)
        let trainingDays = Set(plan.scheduledDays.map(\.weekday))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("Plan consistency")
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer(minLength: 8)
                Text(status.title)
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if !trainingDays.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Weekday.allCases) { day in
                        let active = trainingDays.contains(day)
                        Text(String(day.short.prefix(1)))
                            .font(TTFont.workSans(12, weight: .bold))
                            .foregroundStyle(active ? .white : TTColor.inkSubtle)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(active ? orange : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }

            HStack(spacing: 8) {
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
                    Text("No workouts logged yet")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    @ViewBuilder
    private func planScheduleBreakdown(plan: WorkoutPlan) -> some View {
        let days = plan.scheduledDays.sorted { $0.weekday.sortIndex < $1.weekday.sortIndex }
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Weekly schedule (\(days.count) \(days.count == 1 ? "day" : "days"))")
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)

                ForEach(days) { day in
                    planDayDetailCard(day)
                }
            }
        } else if !plan.exercises.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Plan exercises (\(plan.exercises.count))")
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)

                ForEach(hubExercises(for: plan.exercises)) { row in
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

    private func planDayDetailCard(_ day: PlanDay) -> some View {
        let items = hubExercises(for: day.exercises)
        let isToday = day.weekday == Weekday.from(date: Date())

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(day.weekday.title.uppercased())
                            .font(TTFont.caption(11))
                            .fontWeight(.bold)
                            .tracking(0.6)
                            .foregroundStyle(isToday ? orange : TTColor.inkSubtle)
                        if isToday {
                            Text("TODAY")
                                .font(TTFont.workSans(9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(day.title)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("\(day.timeLabel) · \(day.durationMinutes) min · \(day.location ?? "Gym")")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 8)
                Text("\(items.count) \(items.count == 1 ? "ex" : "exs")")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(TTColor.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .clipShape(Capsule())
            }

            if !day.focus.isEmpty {
                Text(day.focus)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }

            if let notes = day.coachNotes, !notes.isEmpty {
                Text(notes)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkSubtle)
            }

            if !items.isEmpty {
                VStack(spacing: 8) {
                    ForEach(items) { row in
                        NavigationLink {
                            ExerciseDetailView(exercise: row.exercise, prescription: row.prescription)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(orange.opacity(0.16))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.exercise.name)
                                        .font(TTFont.workSans(14, weight: .semibold))
                                        .foregroundStyle(TTColor.ink)
                                    Text(row.prescription.prescriptionLine)
                                        .font(TTFont.workSans(12, weight: .medium))
                                        .foregroundStyle(TTColor.inkMuted)
                                }
                                Spacer(minLength: 4)
                                TTIcon(icon: .chevronRight, size: 12)
                                    .foregroundStyle(TTColor.inkSubtle)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    /// One past completed workout: relative date, title, duration and sets. Opens its summary.
    private func pastSessionRow(_ log: WorkoutLog) -> some View {
        let title = log.sessionTitle ?? store.plans.first(where: { $0.id == log.planId })?.title
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(orange.opacity(0.12))
                TTIcon(icon: .kettlebell, filled: true, size: 16)
                    .foregroundStyle(orange)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(WorkoutSummaryView.relativeDate(log.completedAt))
                    .font(TTFont.workSans(14, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                if let title, !title.isEmpty {
                    Text(title)
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                }
                Text("\(WorkoutLog.formattedDuration(log.totalSeconds)) · \(log.setCount) \(log.setCount == 1 ? "set" : "sets")")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
            }

            Spacer(minLength: 8)

            if log.totalVolumeKg > 0 {
                Text("\(Int(log.totalVolumeKg.rounded())) kg")
                    .font(TTFont.workSans(13, weight: .bold))
                    .foregroundStyle(TTColor.ink)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.7))
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .contentShape(Rectangle())
    }

    private func progressTab(trainee: TraineeProfile, plan: WorkoutPlan) -> some View {
        let logs = store.logs(for: trainee.id).sorted { $0.completedAt > $1.completedAt }
        let totalMinutes = logs.reduce(0) { $0 + $1.durationMinutes }
        let totalVolumeKg = logs.reduce(0.0) { $0 + $1.totalVolumeKg }
        let volumeText = totalVolumeKg >= 1000
            ? String(format: "%.1fk", totalVolumeKg / 1000)
            : "\(Int(totalVolumeKg.rounded()))"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                progressStatTile(value: "\(logs.count)", label: "Sessions")
                progressStatTile(value: "\(totalMinutes)m", label: "Time")
                progressStatTile(value: volumeText, label: "Volume kg")
            }

            if logs.isEmpty {
                VStack(spacing: 10) {
                    TTIcon(icon: .barbellDiagonal, filled: true, size: 24)
                        .foregroundStyle(orange)
                    Text("No workouts logged yet")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("Complete your first session in “\(plan.title)” from the Today tab to see your workout history and volume here.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent workouts")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)

                    ForEach(Array(logs.prefix(15))) { log in
                        NavigationLink {
                            WorkoutSummaryView(log: log)
                        } label: {
                            pastSessionRow(log)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func progressStatTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(TTFont.workSans(12, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
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

    // MARK: - Header

    @ViewBuilder
    private func header(progress: CGFloat) -> some View {
        if showsCloseChrome {
            TTDarkPageHeader(
                title: "Workout",
                collapseProgress: progress
            ) {
                dismiss()
            }
        } else {
            workoutTabHeader(progress: progress)
        }
    }

    /// The weekly day selector already shows the schedule, so the subtitle only appears without a plan.
    private var headerSubtitle: String? {
        if let trainee = store.currentTrainee, store.assignedPlan(for: trainee) != nil {
            return nil
        }
        return "Follow the plan"
    }

    private func workoutTabHeader(progress: CGFloat) -> some View {
        let p = min(1, max(0, progress))
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

                    if let headerSubtitle {
                        Text(headerSubtitle)
                            .font(TTFont.textSM(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .opacity(Double(expand))
                            .frame(height: 18 * expand, alignment: .top)
                            .clipped()
                    }
                }

                Spacer(minLength: 8)

                if store.aiCapabilities.visionPose,
                   let trainee = store.currentTrainee,
                   let plan = store.assignedPlan(for: trainee) {
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
        let canMutateAI = store.traineeCanEditDeleteAIPlan(plan)

        return VStack(alignment: .leading, spacing: 10) {
            // Title first — most important piece of information
            HStack(alignment: .top, spacing: 8) {
                Text(plan.title)
                    .font(TTFont.workSans(20, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                // Compact pill badge — doesn't compete with the title
                if canMutateAI {
                    Text("AI")
                        .font(TTFont.workSans(10, weight: .bold))
                        .foregroundStyle(orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(orange.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.top, 3)
                } else {
                    Text("Trainer")
                        .font(TTFont.workSans(10, weight: .semibold))
                        .foregroundStyle(TTColor.inkSubtle)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.93))
                        .clipShape(Capsule())
                        .padding(.top, 3)
                }
            }

            Text("\(plan.level) · \(plan.focus)")
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)

            // Smart schedule — avoid repeating "Time TBD" N times
            Text(scheduleDisplay(for: plan))
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = plan.notes, !notes.isEmpty {
                Text(notes)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }

            if canMutateAI {
                aiPlanActions(plan)
            } else if plan.isAISource && store.hasLinkedTrainer {
                // Friction B: explain why the AI controls disappeared instead of going silent.
                aiPausedExplainer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    /// Shows weekday names only when times are all TBD — avoids "Mon Time TBD · Mon Time TBD…"
    private func scheduleDisplay(for plan: WorkoutPlan) -> String {
        let scheduled = plan.scheduledDays
        if scheduled.isEmpty { return "\(plan.daysPerWeek)× per week" }
        let allTBD = scheduled.allSatisfy { $0.startTime == nil }
        if allTBD {
            return scheduled.map { $0.weekday.short }.joined(separator: " · ")
        }
        return plan.scheduleLine
    }

    /// Day keys (yyyy-M-d) for all days in the plan that have a session.
    private func sessionDayKeySet(_ plan: WorkoutPlan) -> Set<String> {
        let cal = Calendar.current
        // Build keys for the next 28 days that have a session
        let today = cal.startOfDay(for: Date())
        var keys = Set<String>()
        for offset in -7...28 {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            if plan.session(on: date) != nil {
                let c = cal.dateComponents([.year, .month, .day], from: date)
                keys.insert("\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)")
            }
        }
        return keys
    }

    /// Friction B: inline, neutral explainer for an AI plan whose controls are paused
    /// because a coach is now linked. Read-only ≠ un-trainable — the session still starts.
    private var aiPausedExplainer: some View {
        let coachName = store.currentTrainee
            .flatMap { store.trainer(for: $0)?.userId }
            .flatMap { id in store.users.first { $0.id == id }?.name }?
            .components(separatedBy: " ").first ?? "Your coach"

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TTColor.info)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(coachName) guides your training")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                Text("Your AI plan controls are paused while a coach guides you. They return if you leave your coach.")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.info.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 4)
    }

    private func aiPlanActions(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    editingPlan = plan
                } label: {
                    Text("Edit")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isMutatingAIPlan)

                Button {
                    showAssessmentReview = true
                } label: {
                    Text("Regenerate")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isMutatingAIPlan)
            }

            // Delete demoted to text link — extra distance from other CTAs prevents fat-finger deletion
            Button {
                deletingPlan = plan
                showDeleteAIConfirm = true
            } label: {
                Text("Delete this plan")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(Color(red: 0.72, green: 0.15, blue: 0.15).opacity(isMutatingAIPlan ? 0.4 : 1))
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(isMutatingAIPlan)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 4)
    }

    @MainActor
    private func deleteAIPlan() async {
        guard let plan = deletingPlan ?? store.currentTrainee.flatMap({ store.assignedPlan(for: $0) }) else { return }
        isMutatingAIPlan = true
        defer { isMutatingAIPlan = false }
        do {
            try await store.deleteAIPlan(id: plan.id)
            deletingPlan = nil
            hubToast = TTToastMessage(text: "AI plan removed", style: .success)
        } catch let error as AppError where error.isForbidden {
            hubToast = TTToastMessage(text: error.localizedDescription, style: .error)
        } catch let error as AppError where error.isAIRequired {
            _ = store.presentAIPaywallIfNeeded(for: error)
        } catch {
            hubToast = TTToastMessage(text: error.localizedDescription, style: .error)
        }
    }



    /// "Today", "Tomorrow", "Yesterday", or the weekday name.
    private func relativeDayLabel(for weekday: Weekday) -> String {
        let todayIdx = Weekday.from(date: selectedDay).sortIndex
        let targetIdx = weekday.sortIndex
        switch (targetIdx - todayIdx + 7) % 7 {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 6: return "Yesterday"
        default: return weekday.title
        }
    }

    private func session(in plan: WorkoutPlan) -> PlanDay? {
        plan.session(on: selectedDay)
    }

    private func currentExercises(in plan: WorkoutPlan) -> [WorkoutExercise] {
        session(in: plan)?.exercises ?? plan.exercises
    }

    private func hubExercises(in plan: WorkoutPlan) -> [HubExerciseItem] {
        hubExercises(for: currentExercises(in: plan))
    }

    private func hubExercises(for items: [WorkoutExercise]) -> [HubExerciseItem] {
        items.compactMap { item in
            guard let exercise = store.exercise(id: item.exerciseId) else { return nil }
            return HubExerciseItem(id: item.id, exercise: exercise, prescription: item)
        }
    }

    private enum HeroState {
        case notStarted, inProgress
        case done(WorkoutLog)
    }

    /// Real state of the selected day: a live session wins, then the latest completed log for that day + plan.
    private func heroState(plan: WorkoutPlan, day: PlanDay?) -> HeroState {
        if Calendar.current.isDateInToday(selectedDay),
           let active = store.activeWorkoutSession, active.planId == plan.id,
           day == nil || active.dayId == nil || active.dayId == day?.id {
            return .inProgress
        }
        if let traineeId = store.currentTrainee?.id,
           let log = store.logs(for: traineeId).first(where: { log in
               log.planId == plan.id
                   && Calendar.current.isDate(log.completedAt, inSameDayAs: selectedDay)
                   && (log.planDayId == nil || day == nil || log.planDayId == day?.id)
           }) {
            return .done(log)
        }
        return .notStarted
    }

    private func heroPill(_ title: LocalizedStringKey, systemImage: String, fg: Color, bg: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 14, weight: .bold))
            Text(title).font(TTFont.workSans(13, weight: .medium))
        }
        .foregroundStyle(fg)   // icon + text, not color alone
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bg)
        .clipShape(Capsule())
    }

    private func sessionHero(_ plan: WorkoutPlan) -> some View {
        let day = session(in: plan)
        let next = plan.nextSession(from: selectedDay)
        let isPast = selectedDay < Calendar.current.startOfDay(for: Date())
        let isRestDay = day == nil
        let state = heroState(plan: plan, day: day)

        return VStack(alignment: .leading, spacing: 10) {
            // Status: Done / In progress pills (same look as Home); otherwise the usual label.
            switch state {
            case .done:
                heroPill("Done", systemImage: "checkmark.circle.fill",
                         fg: Color(red: 21 / 255, green: 128 / 255, blue: 61 / 255),
                         bg: Color(red: 220 / 255, green: 252 / 255, blue: 231 / 255))
            case .inProgress:
                heroPill("In progress", systemImage: "play.circle.fill",
                         fg: Color(red: 194 / 255, green: 65 / 255, blue: 12 / 255),
                         bg: orange.opacity(0.14))
            case .notStarted:
                // Label: calm gray for rest days, orange only for active sessions
                Text(isRestDay ? "REST DAY" : (isPast ? "PAST SESSION" : "TODAY'S SESSION"))
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .tracking(0.8)
                    .foregroundStyle(isRestDay || isPast ? TTColor.inkSubtle : orange)
            }

            Text(day?.title ?? plan.title)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)

            if let day {
                Text("\(relativeDayLabel(for: day.weekday)) · \(day.timeLabel) · \(day.durationMinutes) min · \(day.location ?? "Gym")")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)

                if !day.focus.isEmpty {
                    Text(day.focus)
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }

                if case .done(let log) = state {
                    HStack(spacing: 10) {
                        NavigationLink {
                            WorkoutSummaryView(log: log)
                        } label: {
                            Text("View summary")
                                .font(TTFont.workSans(15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(charcoal)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        // Only for today: a new session can't be started on a past date.
                        if !isPast {
                            NavigationLink {
                                ActiveWorkoutView(plan: plan, day: day, autoStart: true)
                            } label: {
                                Text("Train again")
                                    .font(TTFont.workSans(15, weight: .semibold))
                                    .foregroundStyle(TTColor.ink)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color(white: 0.9))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                } else if case .inProgress = state {
                    NavigationLink {
                        ActiveWorkoutView(plan: plan, day: day, autoStart: true)
                    } label: {
                        Text("Continue workout")
                            .font(TTFont.workSans(15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                } else if isPast {
                    // Past date — session already over, don't offer to start it
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TTColor.inkSubtle)
                        Text("This session has passed")
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                    .padding(.top, 2)
                } else {
                    NavigationLink {
                        ActiveWorkoutView(plan: plan, day: day)
                    } label: {
                        Text("Start workout")
                            .font(TTFont.workSans(15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            } else {
                Text(next.map { "Next session: \(relativeDayLabel(for: $0.weekday)) · \($0.focus)" } ?? plan.focus)
                    .font(TTFont.body(13))
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
        } else {
            // Rest day — show recovery info, not the exercise list
            let next = plan.nextSession(from: selectedDay)
            VStack(alignment: .leading, spacing: 8) {
                Text("REST DAY")
                    .font(TTFont.caption(11))
                    .fontWeight(.bold)
                    .tracking(0.8)
                    .foregroundStyle(TTColor.inkSubtle)
                Text("Recovery is where the gains happen.")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                if let next {
                    Text("Next session: \(relativeDayLabel(for: next.weekday)) · \(next.timeLabel) · \(next.focus)")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Text("Today: stretch, walk, or sleep early. 💤")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            if let notes = plan.notes, !notes.isEmpty {
                labeledCard("Trainer notes", notes)
            }
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
                        scrollRunway: 0,
                        coordinateSpaceName: scrollSpace,
                        topInset: collapsedHeaderHeight
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
        let enabled = store.aiCapabilities.visionPose
        let row = HStack(spacing: TTCardTokens.listSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: TTCardTokens.thumbCorner, style: .continuous)
                    .fill(enabled ? orange.opacity(0.12) : Color(white: 0.9))
                TTIcon(icon: .camera1, filled: true, size: 18)
                    .foregroundStyle(enabled ? orange : TTColor.inkSubtle)
            }
            .frame(width: TTCardTokens.thumbSize, height: TTCardTokens.thumbSize)

            VStack(alignment: .leading, spacing: 3) {
                Text("Live form correction")
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(enabled ? TTColor.ink : TTColor.inkMuted)
                if enabled {
                    Text("Use the camera for real-time cues")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                } else {
                    // "Coming soon" badge instead of a dead subtitle that looks like a bug
                    Text("Coming soon")
                        .font(TTFont.workSans(10, weight: .bold))
                        .foregroundStyle(TTColor.inkSubtle)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(white: 0.91))
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 8)

            // Chevron only when tappable — no chevron on disabled rows
            if enabled {
                TTIcon(icon: .chevronRight, size: 14)
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .padding(TTCardTokens.padding)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .opacity(enabled ? 1 : 0.65)

        return Group {
            if enabled {
                NavigationLink {
                    LiveFormCorrectionView(initialExerciseId: currentExercises(in: plan).first?.exerciseId)
                } label: { row }
                .buttonStyle(.plain)
            } else {
                row // non-interactive, clearly disabled
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .barbellDiagonal, filled: true, size: 28)
                .foregroundStyle(orange)
            Text("No workout assigned")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(
                store.canShowSoloAIGenerate
                    ? "Generate my week from Home to build an AI plan, or link a trainer."
                    : "Your trainer will attach a plan with days, times, and weights."
            )
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
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let prescription: WorkoutExercise

    @State private var showFormStudio = false
    @State private var formStudioToast: TTToastMessage?

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = TTColor.charcoal
    private let orange = TTColor.actionOrange

    private var formStudioSession: FormStudioExerciseMap.DemoSession? {
        FormStudioExerciseMap.demoSession(for: exercise)
    }

    var body: some View {
        TTCollapsingHeaderScreen(
            sheetFill: canvas,
            headerBackground: TTColor.charcoal,
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            header: { progress in
                TTDarkPageHeader(title: exercise.name, collapseProgress: progress) {
                dismiss()
            }
            }
        ) {
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

                    formCoachActions
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .ttToast($formStudioToast, bottomInset: 28)
        .overlay(alignment: .top) {
            if let notice = store.planChangeNotice {
                Text(notice)
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(orange.opacity(0.14))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { store.beginTraineeSessionUI() }
        .onDisappear { store.endTraineeSessionUI() }
        .fullScreenCover(isPresented: $showFormStudio) {
            if let formStudioSession {
                FormStudioDemoView(session: formStudioSession) { message in
                    showFormStudio = false
                    formStudioToast = TTToastMessage(
                        text: message.isEmpty ? "Couldn't load 3D demo" : message,
                        style: .error
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var formCoachActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Form coaching")
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(TTColor.ink)

            if let formStudioSession {
                Button {
                    showFormStudio = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(orange.opacity(0.12))
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(orange)
                        }
                        .frame(width: 40, height: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("3D Form Demo")
                                .font(TTFont.workSans(15, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                            Text(
                                formStudioSession.subtitle
                                    ?? "Watch a 3D coach demonstrate form"
                            )
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        TTIcon(icon: .chevronRight, size: 14)
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open 3D form demonstration")
            } else {
                #if DEBUG
                if exercise.form3d?.enabled == true {
                    Text("3D demo enabled but no animationUrl / bundled clip (DEBUG)")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                } else if FormStudioExerciseMap.mappedIdIgnoringBundle(for: exercise) != nil {
                    Text("3D demo — awaiting backend form3d or Mixamo clip (DEBUG)")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }
                #endif
            }

            NavigationLink {
                LiveFormCorrectionView(initialExerciseId: exercise.id)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(orange.opacity(0.12))
                        TTIcon(icon: .camera1, filled: true, size: 16)
                            .foregroundStyle(orange)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Form")
                            .font(TTFont.workSans(15, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Text("Camera AI checks your form in real time")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer(minLength: 8)
                    TTIcon(icon: .chevronRight, size: 14)
                        .foregroundStyle(TTColor.inkSubtle)
                }
                .padding(14)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open live form AI")
        }
    }
}

#Preview("Workout Hub") {
    WorkoutHubView()
        .ttPreviewTrainee()
}

// MARK: - Workout summary (completed session)

/// Read-only summary of one finished `WorkoutLog`: hero metrics, per-exercise sets with timing, and "Train again".
struct WorkoutSummaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let log: WorkoutLog

    @State private var trainAgain = false

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = TTColor.charcoal
    private let orange = TTColor.actionOrange
    private let green = Color(red: 21 / 255, green: 128 / 255, blue: 61 / 255)

    private struct ExerciseGroup: Identifiable {
        var id: String
        var sets: [WorkoutSetLog]
    }

    private var plan: WorkoutPlan? { store.plans.first { $0.id == log.planId } }
    private var day: PlanDay? {
        guard let plan else { return nil }
        return log.planDayId.flatMap { id in plan.days.first { $0.id == id } }
    }
    private var title: String { log.sessionTitle ?? day?.title ?? plan?.title ?? String(localized: "Workout") }

    /// Grouped by exercise, in the order first performed.
    private var groups: [ExerciseGroup] {
        var order: [String] = []
        var bySets: [String: [WorkoutSetLog]] = [:]
        for set in log.sets {
            if bySets[set.exerciseId] == nil { order.append(set.exerciseId) }
            bySets[set.exerciseId, default: []].append(set)
        }
        return order.map { ExerciseGroup(id: $0, sets: (bySets[$0] ?? []).sorted { $0.setNumber < $1.setNumber }) }
    }

    static func relativeDate(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "\(String(localized: "Today")) · \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "\(String(localized: "Yesterday")) · \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    var body: some View {
        TTCollapsingHeaderScreen(
            sheetFill: canvas,
            headerBackground: TTColor.charcoal,
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            header: { progress in
                TTDarkPageHeader(title: title, collapseProgress: progress) { dismiss() }
            }
        ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(log.completedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)

                    heroCard

                    if !groups.isEmpty {
                        Text("Exercises")
                            .font(TTFont.workSans(11, weight: .bold))
                            .foregroundStyle(TTColor.inkMuted)
                            .kerning(0.8)
                            .textCase(.uppercase)
                            .padding(.top, 4)
                        ForEach(groups) { group in exerciseCard(group) }
                    }

                    trainAgainButton
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .navigationDestination(isPresented: $trainAgain) {
            if let plan {
                ActiveWorkoutView(plan: plan, day: day ?? plan.session(on: Date()) ?? plan.nextSession(from: Date()), autoStart: true)
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .bold))
                Text("Completed")
                    .font(TTFont.workSans(13, weight: .medium))
            }
            .foregroundStyle(green)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(red: 220 / 255, green: 252 / 255, blue: 231 / 255))
            .clipShape(Capsule())

            let volume = log.totalVolumeKg
            let setsText = volume > 0
                ? "\(log.setCount) · \(Int(volume.rounded())) kg"
                : "\(log.setCount)"
            // TODO: Active time / Total rest show "—" for logs saved before timing existed (backend must echo durationSeconds / totalRestSeconds).
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                metric("Total time", WorkoutLog.formattedDuration(log.totalSeconds))
                metric("Active time", log.activeSeconds.map(WorkoutLog.formattedDuration) ?? "—")
                metric("Total rest", log.restTotalSeconds.map(WorkoutLog.formattedDuration) ?? "—")
                metric(volume > 0 ? "Sets · Volume" : "Sets", setsText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(TTFont.workSans(12, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
            Text(verbatim: value)
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Exercises

    private func exerciseCard(_ group: ExerciseGroup) -> some View {
        let name = store.exercise(id: group.id)?.name ?? String(localized: "Exercise")
        let timed = group.sets.compactMap(\.durationSeconds)
        let total = timed.isEmpty ? nil : timed.reduce(0, +) + group.sets.compactMap(\.restSeconds).reduce(0, +)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Spacer(minLength: 8)
                if let total {
                    Text(WorkoutLog.formattedDuration(total))
                        .font(TTFont.workSans(12, weight: .semibold))
                        .foregroundStyle(TTColor.inkMuted)
                        .monospacedDigit()
                }
            }
            ForEach(group.sets) { set in
                Text(setLine(set))
                    .font(TTFont.workSans(13, weight: .regular))
                    .foregroundStyle(TTColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "Set 1 · 8 reps × 4.9 kg · 28s · Rest 1m 10s" — weight and timing omitted when unknown or zero.
    private func setLine(_ set: WorkoutSetLog) -> String {
        var parts = ["\(String(localized: "Set")) \(set.setNumber)"]
        var work = "\(set.reps) \(String(localized: "reps"))"
        if set.weightKg > 0 { work += " × \(set.weightKg.cleanKg) kg" }
        parts.append(work)
        if let d = set.durationSeconds { parts.append(WorkoutLog.formattedDuration(d)) }
        if let r = set.restSeconds, r > 0 { parts.append("\(String(localized: "Rest")) \(WorkoutLog.formattedDuration(r))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Train again

    @ViewBuilder
    private var trainAgainButton: some View {
        if plan != nil {
            Button { trainAgain = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .bold))
                    Text("Train again").font(TTFont.workSans(16, weight: .bold))
                }
                .foregroundStyle(TTColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        // TODO: plan no longer in the store (deleted/reassigned) → "Train again" hidden; nothing to start.
    }
}
