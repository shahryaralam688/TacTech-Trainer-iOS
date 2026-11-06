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

    // Sort / filter / delete
    @AppStorage("trainer.plans.sort") private var sortRaw = PlanSort.newest.rawValue
    @State private var levelFilter: String?
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var pendingDelete: [WorkoutPlan] = []
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var toast: TTToastMessage?

    private let levels = ["Beginner", "Intermediate", "Advanced"]

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let scrollSpace = "workoutPlans"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                trainerListHeader(
                    title: "Workout Plans",
                    subtitle: plans.count == 1 ? "1 plan" : "\(plans.count) plans",
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

                            if plans.count > 1 {
                                listControls
                            }

                            if isFiltering && !isSelecting {
                                filterSummary
                            }

                            if plans.isEmpty {
                                emptyCard(
                                    icon: .clipboard,
                                    title: "No plans yet",
                                    message: "Build a weekly plan once, then assign it to any of your trainees.",
                                    actionTitle: "Create your first plan"
                                ) { showCreate = true }
                            } else if filtered.isEmpty {
                                emptyCard(
                                    icon: .clipboard,
                                    title: "No plans match",
                                    message: "Nothing fits \(activeFilterText). Clear it to see all \(plans.count) plans.",
                                    actionTitle: "Clear search and filters"
                                ) { clearFilters() }
                            } else if isSelecting {
                                // Plain list while selecting — no stacked scroll effect under checkboxes.
                                VStack(spacing: TTSpace.md) {
                                    ForEach(filtered) { plan in
                                        selectableCard(plan)
                                    }
                                }
                            } else {
                                TTStackedSections(
                                    data: filtered,
                                    stackOffset: TTStackedTokens.stackOffset,
                                    withDramaEffect: true,
                                    paneGap: TTSpace.md,
                                    scrollRunway: TTStackedTokens.defaultRunway,
                                    coordinateSpaceName: scrollSpace
                                ) { plan in
                                    NavigationLink {
                                        WorkoutPlanDetailView(plan: plan)
                                    } label: {
                                        planCard(plan)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            isSelecting = true
                                            selection = [plan.id]
                                        } label: {
                                            Label("Select", systemImage: "checkmark.circle")
                                        }
                                        Button(role: .destructive) {
                                            requestDelete([plan])
                                        } label: {
                                            Label("Delete plan", systemImage: "trash")
                                        }
                                    }
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
                .safeAreaInset(edge: .bottom) {
                    if isSelecting { selectionBar }
                }
            }
            .onChange(of: plans.count) { _, count in
                if count < 2 && isSelecting { exitSelection() }
            }
            .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .ttSyncRootTabBarWithNavigationDepth()
            .sheet(isPresented: $showCreate) {
                CreatePlanView()
                    .ttModalSheetPresentation()
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
            .confirmationDialog(
                deleteTitle,
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(pendingDelete.count == 1 ? "Delete plan" : "Delete \(pendingDelete.count) plans",
                       role: .destructive) {
                    Task { await performDelete() }
                }
                Button("Cancel", role: .cancel) { pendingDelete = [] }
            } message: {
                Text(deleteMessage)
            }
            .ttToast($toast)
        }
    }

    // MARK: - Sort / filter / select

    enum PlanSort: String, CaseIterable, Identifiable {
        // Kept to the orders trainers actually reach for; old stored values fall back to .newest.
        case newest, oldest, name, level, shortest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newest: "Newest first"
            case .oldest: "Oldest first"
            case .name: "Name (A–Z)"
            case .level: "Level (Beginner first)"
            case .shortest: "Shortest session first"
            }
        }
        var short: String {
            switch self {
            case .newest: "Newest"
            case .oldest: "Oldest"
            case .name: "Name"
            case .level: "Level"
            case .shortest: "Shortest"
            }
        }
    }

    private var sort: PlanSort { PlanSort(rawValue: sortRaw) ?? .newest }

    /// Only offer levels that actually exist in the trainer's plans.
    private var availableLevels: [String] {
        levels.filter { level in plans.contains { $0.level.caseInsensitiveCompare(level) == .orderedSame } }
    }

    /// One calm row: Sort · Level on the left, Select on the right. Hidden while selecting.
    @ViewBuilder private var listControls: some View {
        if isSelecting {
            HStack(spacing: 10) {
                Button("Done") { exitSelection() }
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(minHeight: 44)

                Text(selection.isEmpty ? "Tap plans to select" : "\(selection.count) selected")
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .frame(maxWidth: .infinity)

                Button(allFilteredSelected ? "Deselect All" : "Select All") {
                    selection = allFilteredSelected ? [] : Set(filtered.map(\.id))
                }
                .font(TTFont.workSans(15, weight: .semibold))
                .foregroundStyle(TTColor.actionOrange)
                .frame(minHeight: 44)
            }
        } else {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort by", selection: $sortRaw) {
                        ForEach(PlanSort.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } label: {
                    controlPill(icon: "arrow.up.arrow.down", text: sort.short, active: false)
                }
                .accessibilityLabel("Sort plans, currently \(sort.title)")

                if availableLevels.count > 1 {
                    Menu {
                        Picker("Level", selection: $levelFilter) {
                            Text("All levels").tag(String?.none)
                            ForEach(availableLevels, id: \.self) { level in
                                Text(level).tag(String?.some(level))
                            }
                        }
                    } label: {
                        controlPill(
                            icon: "line.3.horizontal.decrease",
                            text: levelFilter ?? "All levels",
                            active: levelFilter != nil
                        )
                    }
                    .accessibilityLabel("Filter by level, currently \(levelFilter ?? "all levels")")
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.snappy(duration: 0.2)) { isSelecting = true }
                } label: {
                    Text("Select")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.actionOrange)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose plans to delete")
            }
        }
    }

    /// iOS-style bottom action bar for bulk actions — destructive action lives here, away from Select All.
    private var selectionBar: some View {
        Button {
            requestDelete(filtered.filter { selection.contains($0.id) })
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "trash")
                    Text(selection.isEmpty
                         ? "Delete"
                         : selection.count == 1 ? "Delete 1 plan" : "Delete \(selection.count) plans")
                }
            }
            .font(TTFont.workSans(16, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(selection.isEmpty ? Color(white: 0.75) : TTColor.danger)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selection.isEmpty || isDeleting)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Filter state

    private var isFiltering: Bool { !query.isEmpty || focusFilter != nil || levelFilter != nil }

    private var activeFilterText: String {
        var parts: [String] = []
        if !query.isEmpty { parts.append("“\(query)”") }
        if let focusFilter { parts.append(focusFilter) }
        if let levelFilter { parts.append(levelFilter) }
        return parts.joined(separator: " · ")
    }

    /// Always tells the trainer when part of the list is hidden, with a one-tap way back.
    private var filterSummary: some View {
        HStack(spacing: 8) {
            Text("Showing \(filtered.count) of \(plans.count) · \(activeFilterText)")
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Clear") { clearFilters() }
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(TTColor.actionOrange)
                .frame(minHeight: 44)
        }
    }

    private func clearFilters() {
        withAnimation(.snappy(duration: 0.2)) {
            query = ""
            focusFilter = nil
            levelFilter = nil
        }
    }

    private func controlPill(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(TTFont.workSans(14, weight: .semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(active ? .white : TTColor.ink)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(active ? Color.black : cardFill)
        .clipShape(Capsule())
        .contentShape(Capsule())
    }

    private func selectableCard(_ plan: WorkoutPlan) -> some View {
        let isOn = selection.contains(plan.id)
        return Button {
            if isOn { selection.remove(plan.id) } else { selection.insert(plan.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(isOn ? TTColor.actionOrange : Color(white: 0.7))
                    .frame(width: 32)
                planCard(plan)
                    .overlay(
                        RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous)
                            .strokeBorder(isOn ? TTColor.actionOrange : .clear, lineWidth: 2)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint("Double-tap to \(isOn ? "deselect" : "select")")
    }

    private var allFilteredSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { selection.contains($0.id) }
    }

    private func exitSelection() {
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = false
            selection = []
        }
    }

    // MARK: - Delete

    private func requestDelete(_ targets: [WorkoutPlan]) {
        guard !targets.isEmpty else { return }
        pendingDelete = targets
        showDeleteConfirm = true
    }

    private var deleteTitle: String {
        pendingDelete.count == 1 ? "Delete “\(pendingDelete[0].title)”?" : "Delete \(pendingDelete.count) plans?"
    }

    private var deleteMessage: String {
        let ids = Set(pendingDelete.map(\.id))
        let affected = Set(store.assignments.filter { ids.contains($0.planId) }.map(\.traineeId)).count
        let base = "This can’t be undone."
        switch affected {
        case 0: return base
        case 1: return "1 trainee is using \(pendingDelete.count == 1 ? "this plan" : "these plans") and will lose it. \(base)"
        default: return "\(affected) trainees are using \(pendingDelete.count == 1 ? "this plan" : "these plans") and will lose it. \(base)"
        }
    }

    private func performDelete() async {
        let targets = pendingDelete
        pendingDelete = []
        isDeleting = true
        defer { isDeleting = false }
        var failed = 0
        for plan in targets {
            do { try await store.deletePlan(id: plan.id) } catch { failed += 1 }
        }
        let deleted = targets.count - failed
        selection.subtract(targets.map(\.id))
        if failed == 0 {
            toast = TTToastMessage(text: deleted == 1 ? "Plan deleted" : "\(deleted) plans deleted")
            exitSelection()
        } else {
            toast = TTToastMessage(
                text: deleted == 0 ? "Couldn’t delete" : "Deleted \(deleted) of \(targets.count)",
                style: .error,
                subtitle: "\(failed) plan\(failed == 1 ? "" : "s") couldn’t be deleted. Try again."
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
        if let levelFilter {
            result = result.filter { $0.level.caseInsensitiveCompare(levelFilter) == .orderedSame }
        }
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.focus.localizedCaseInsensitiveContains(query)
                    || $0.level.localizedCaseInsensitiveContains(query)
            }
        }
        return sorted(result)
    }

    /// WorkoutPlan has no created date — store order is creation order (new plans are appended).
    private func sorted(_ list: [WorkoutPlan]) -> [WorkoutPlan] {
        let order = Dictionary(store.plans.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byNewest: (WorkoutPlan, WorkoutPlan) -> Bool = { (order[$0.id] ?? 0) > (order[$1.id] ?? 0) }
        let rank: (String) -> Int = { ["beginner": 0, "intermediate": 1, "advanced": 2][$0.lowercased()] ?? 3 }
        switch sort {
        case .newest:
            return list.sorted(by: byNewest)
        case .oldest:
            return list.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        case .name:
            return list.sorted {
                let c = $0.title.localizedStandardCompare($1.title)
                return c == .orderedSame ? byNewest($0, $1) : c == .orderedAscending
            }
        case .shortest:
            return list.sorted { $0.durationMinutes == $1.durationMinutes ? byNewest($0, $1) : $0.durationMinutes < $1.durationMinutes }
        case .level:
            return list.sorted { rank($0.level) == rank($1.level) ? byNewest($0, $1) : rank($0.level) < rank($1.level) }
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

            // Shape of the plan in one scannable line (schedule days already say how many per week).
            HStack(spacing: 14) {
                metaChip(
                    icon: .calendar1,
                    text: plan.scheduledDays.isEmpty
                        ? "\(plan.daysPerWeek) days / week"
                        : plan.scheduledDays.map { $0.weekday.short }.joined(separator: " · ")
                )
                metaChip(icon: .alarm, text: "\(plan.durationMinutes) min")
                metaChip(icon: .kettlebell, text: "\(plan.allExercises.count) exercises")
                Spacer(minLength: 0)
            }
            .lineLimit(1)

            Divider().opacity(0.6)

            // What a trainer most needs to know at a glance: is this plan in use?
            HStack(spacing: 6) {
                let count = assignedCount(plan)
                Circle()
                    .fill(count > 0 ? TTColor.success : Color(white: 0.7))
                    .frame(width: 7, height: 7)
                Text(count == 0 ? "Not assigned yet" : count == 1 ? "Assigned to 1 trainee" : "Assigned to \(count) trainees")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(count > 0 ? TTColor.ink : TTColor.inkMuted)
                Spacer(minLength: 0)
                if !isSelecting {
                    TTIcon(icon: .chevronRight, size: 16)
                        .foregroundStyle(TTColor.inkSubtle)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func metaChip(icon: SandowIcon, text: String) -> some View {
        HStack(spacing: 5) {
            TTIcon(icon: icon, size: 12)
            Text(text)
        }
        .font(TTFont.caption(12))
        .foregroundStyle(TTColor.inkMuted)
    }

    private func assignedCount(_ plan: WorkoutPlan) -> Int {
        Set(store.assignments.filter { $0.planId == plan.id }.map(\.traineeId)).count
    }

    private func emptyCard(
        icon: SandowIcon,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            TTIcon(icon: icon, filled: true, size: 28)
                .foregroundStyle(TTColor.actionOrange)
            Text(title)
                .font(TTFont.workSans(17, weight: .bold))
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            Button(action: action) {
                Text(actionTitle)
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(Color.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
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
    let planSeed: WorkoutPlan
    @State private var selectedTraineeId = ""
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isAssigning = false
    @State private var assignSucceeded = false
    @State private var celebrateAssign = false
    @State private var feedbackToast: TTToastMessage?
    @State private var actionError: String?
    @State private var unassignTraineeId: String?
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let scrollSpace = "workoutPlanDetail"

    init(plan: WorkoutPlan) {
        self.planSeed = plan
    }

    private var plan: WorkoutPlan {
        store.plans.first(where: { $0.id == planSeed.id }) ?? planSeed
    }

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
                        managePlanCard

                        sectionLabel("Assigned & status")
                        assignmentAnalyticsCard

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

                        if let actionError {
                            Text(actionError)
                                .font(TTFont.caption(13))
                                .foregroundStyle(TTColor.danger)
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
        .sheet(isPresented: $showEdit) {
            CreatePlanView(editingPlan: plan)
                .ttModalSheetPresentation()
        }
        .confirmationDialog(
            "Delete this plan?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete plan", role: .destructive) {
                Task { await deletePlan() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the plan and clears active assignments. Workout history stays.")
        }
        .confirmationDialog(
            "Unassign trainee?",
            isPresented: Binding(
                get: { unassignTraineeId != nil },
                set: { if !$0 { unassignTraineeId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unassign", role: .destructive) {
                guard let traineeId = unassignTraineeId else { return }
                Task { await unassign(traineeId: traineeId) }
            }
            Button("Cancel", role: .cancel) {
                unassignTraineeId = nil
            }
        } message: {
            Text("They will no longer see this plan as their assigned program.")
        }
        .ttAssignSuccessChrome(toast: $feedbackToast, celebrate: $celebrateAssign)
    }

    private var managePlanCard: some View {
        HStack(spacing: 10) {
            Button {
                showEdit = true
            } label: {
                HStack(spacing: 8) {
                    TTIcon(icon: .pencil1, filled: true, size: 14)
                    Text("Modify")
                        .font(TTFont.workSans(15, weight: .bold))
                }
                .foregroundStyle(TTColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                    } else {
                        TTIcon(icon: .trash1, filled: true, size: 14)
                        Text("Delete")
                            .font(TTFont.workSans(15, weight: .bold))
                    }
                }
                .foregroundStyle(TTColor.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(TTColor.danger.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
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

    private var assignedAthletes: [(trainee: TraineeProfile, assignedAt: Date)] {
        store.traineesAssigned(toPlanId: plan.id)
    }

    private var assignmentAnalyticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if assignedAthletes.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    TTIcon(icon: .usersTwo, filled: true, size: 16)
                        .foregroundStyle(TTColor.actionOrange)
                    Text("No trainee is on this plan yet. Assign someone below to track follow-through.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Text("\(assignedAthletes.count) athlete\(assignedAthletes.count == 1 ? "" : "s")")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Spacer()
                    Text("14-day adherence")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }

                ForEach(assignedAthletes, id: \.trainee.id) { item in
                    assignmentStatusRow(trainee: item.trainee, assignedAt: item.assignedAt)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func assignmentStatusRow(trainee: TraineeProfile, assignedAt: Date) -> some View {
        let name = store.user(forTrainee: trainee)?.name ?? "Trainee"
        let status = store.planFollowStatus(traineeId: trainee.id, plan: plan)
        let adherence = store.planAdherencePercent(traineeId: trainee.id, plan: plan)
        let last = store.lastPlanWorkoutDate(traineeId: trainee.id, planId: plan.id)
        let statusColor = followStatusColor(status)

        return HStack(alignment: .top, spacing: 12) {
            TTAvatar(name: name, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
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

                Text("Assigned \(assignedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)

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
                    unassignTraineeId = trainee.id
                } label: {
                    Text("Unassign")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(TTColor.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(TTColor.danger.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func followStatusColor(_ status: PlanFollowStatus) -> Color {
        switch status {
        case .trainedToday, .following: TTColor.success
        case .dueToday: TTColor.actionOrange
        case .behind: Color(red: 0.86, green: 0.45, blue: 0.14)
        case .notStarted: TTColor.inkMuted
        }
    }

    private func assignCard(trainer: TrainerProfile) -> some View {
        let trainees = store.trainees(for: trainer)
        let alreadyOnPlan = !selectedTraineeId.isEmpty
            && assignedAthletes.contains(where: { $0.trainee.id == selectedTraineeId })
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

            TTAssignSuccessButton(
                title: alreadyOnPlan ? "Already assigned" : "Assign this plan",
                isEnabled: !selectedTraineeId.isEmpty && !alreadyOnPlan,
                isLoading: isAssigning,
                showSuccess: assignSucceeded
            ) {
                Task { await assignSelected() }
            }
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

    private func assignSelected() async {
        actionError = nil
        guard !selectedTraineeId.isEmpty else { return }
        isAssigning = true
        defer { isAssigning = false }
        do {
            try await store.assign(planId: plan.id, to: selectedTraineeId)
            let traineeName = store.trainees.first(where: { $0.id == selectedTraineeId })
                .flatMap { store.user(forTrainee: $0)?.name } ?? "Trainee"
            TTAssignSuccessFeedback.play(
                toast: $feedbackToast,
                celebrate: $celebrateAssign,
                planTitle: plan.title,
                traineeName: traineeName
            )
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                assignSucceeded = true
            }
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeOut(duration: 0.2)) {
                assignSucceeded = false
            }
        } catch {
            actionError = error.localizedDescription
            feedbackToast = TTToastMessage(text: "Couldn’t assign plan", style: .error, subtitle: error.localizedDescription)
        }
    }

    private func unassign(traineeId: String) async {
        actionError = nil
        let traineeName = store.trainees.first(where: { $0.id == traineeId })
            .flatMap { store.user(forTrainee: $0)?.name } ?? "Trainee"
        defer { unassignTraineeId = nil }
        do {
            try await store.unassign(planId: plan.id, from: traineeId)
            TTAssignSuccessFeedback.playUnassign(toast: $feedbackToast, traineeName: traineeName)
        } catch {
            actionError = error.localizedDescription
            feedbackToast = TTToastMessage(text: "Couldn’t unassign", style: .error, subtitle: error.localizedDescription)
        }
    }

    private func deletePlan() async {
        isDeleting = true
        actionError = nil
        defer { isDeleting = false }
        do {
            try await store.deletePlan(id: plan.id)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct PlanDayDetailCard: View {
    let day: PlanDay
    @State private var isExpanded = false

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange

    private var morph: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var collapsedSummary: String {
        let focus = day.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = focus.isEmpty ? day.title : focus
        return "\(head) · \(day.exercises.count) exercise\(day.exercises.count == 1 ? "" : "s") · \(day.durationMinutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(morph) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(day.weekday.title)
                                .font(TTFont.workSans(17, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                            Spacer(minLength: 8)
                            Text(day.timeLabel)
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(orange)
                        }
                        Text(collapsedSummary)
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(2)
                    }

                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 34, height: 34)
                        TTIcon(icon: .chevronDown, size: 14)
                            .foregroundStyle(TTColor.inkMuted)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Minimize \(day.weekday.title)" : "Expand \(day.weekday.title)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(morph, value: isExpanded)
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
    @State private var isExpanded = false

    private let orange = TTColor.actionOrange

    private var morph: Animation {
        .spring(response: 0.32, dampingFraction: 0.88)
    }

    var body: some View {
        let exercise = store.exercise(id: item.exerciseId)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(morph) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index)")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(orange)
                        .frame(width: 28, height: 28)
                        .background(orange.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise?.name ?? "Exercise")
                            .font(TTFont.workSans(15, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                        Text(item.prescriptionLine)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer(minLength: 8)
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.94))
                            .frame(width: 28, height: 28)
                        TTIcon(icon: .chevronDown, size: 12)
                            .foregroundStyle(TTColor.inkMuted)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Minimize exercise" : "Expand exercise")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
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
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(morph, value: isExpanded)
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

// MARK: - Quick assign / assignments list

struct PlanQuickAssignSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var planId = ""
    @State private var traineeId = ""
    @State private var isAssigning = false
    @State private var assignSucceeded = false
    @State private var celebrateAssign = false
    @State private var feedbackToast: TTToastMessage?
    @State private var showCreatePlan = false
    @State private var newPlanId: String?
    @State private var planSearch = ""
    @FocusState private var searchFocused: Bool

    var preselectedPlanId: String? = nil
    var preselectedTraineeId: String? = nil
    var onAssigned: (() -> Void)? = nil

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var plans: [WorkoutPlan] {
        store.plans.filter { $0.trainerId == store.currentTrainer?.id }
    }

    /// Opened from the saved screen → trainees without a plan first; otherwise roster order.
    private var trainees: [TraineeProfile] {
        guard let trainer = store.currentTrainer else { return [] }
        let all = store.trainees(for: trainer)
        guard preselectedPlanId != nil else { return all }
        return all.filter { store.assignedPlan(for: $0) == nil } + all.filter { store.assignedPlan(for: $0) != nil }
    }

    var body: some View {
        Group {
            if preselectedTraineeId != nil {
                traineeModeBody
            } else {
                defaultBody
            }
        }
        // Wizard stacks on top of this sheet; Cancel/Discard returns here unchanged.
        .sheet(isPresented: $showCreatePlan) {
            CreatePlanView(onCreate: { plan in
                newPlanId = plan.id
                planId = plan.id
                planSearch = ""
            }, returnAfterCreate: true, initialTitle: trimmedSearch.isEmpty ? nil : trimmedSearch)
            .ttModalSheetPresentation()
        }
    }

    // MARK: Shared: create-a-plan row + plan meta

    private var createPlanRow: some View {
        Button {
            showCreatePlan = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TTColor.actionOrange.opacity(0.12))
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(TTColor.actionOrange)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSearching ? "Create “\(trimmedSearch)”" : "Create a new plan")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    Text("You’ll come back here with it selected")
                        .font(TTFont.textSM(.medium))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                TTIcon(icon: .chevronRight, size: 14)
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(white: 0.75), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "<focus> · <level> · <n> days/week · <m> min" from non-empty parts only.
    private func planMeta(_ plan: WorkoutPlan) -> String {
        let days = plan.daysPerWeek > 0 ? "\(plan.daysPerWeek) \(plan.daysPerWeek == 1 ? "day" : "days")/week" : ""
        let minutes = plan.durationMinutes > 0 ? "\(plan.durationMinutes) min" : ""
        return [plan.level, days, minutes]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// New plan first, then the current plan, then the rest in store order; searchable when long.
    private var orderedPlans: [WorkoutPlan] {
        let pinned = [newPlanId, currentPlan?.id].compactMap { $0 }
        var list = pinned.compactMap { id in plans.first { $0.id == id } }
        list += plans.filter { !pinned.contains($0.id) }
        var seen = Set<String>()
        list = list.filter { seen.insert($0.id).inserted }
        guard isSearching else { return list }
        // Filtering only hides cards; the selected planId is never cleared here.
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedSearch)
                || $0.focus.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var trimmedSearch: String { planSearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Search only exists (and only applies) when the list is long enough to need it.
    private var isSearching: Bool { plans.count > 6 && !trimmedSearch.isEmpty }

    // MARK: Trainee mode (opened for one trainee)

    private var fixedTrainee: TraineeProfile? {
        guard let preselectedTraineeId, let trainer = store.currentTrainer else { return nil }
        return store.trainees(for: trainer).first { $0.id == preselectedTraineeId }
    }

    private var fixedTraineeName: String {
        fixedTrainee.flatMap { store.user(forTrainee: $0)?.name } ?? "Trainee"
    }

    private var firstName: String {
        fixedTraineeName.split(separator: " ").first.map(String.init) ?? fixedTraineeName
    }

    private var currentPlan: WorkoutPlan? {
        fixedTrainee.flatMap { store.assignedPlan(for: $0) }
    }

    private var traineeModeHint: String {
        if planId.isEmpty { return "Choose a plan to continue" }
        if let currentPlan, currentPlan.id == planId { return "This is already their plan" }
        let picked = plans.first { $0.id == planId }?.title ?? "Plan"
        if let currentPlan { return "“\(picked)” replaces “\(currentPlan.title)”" }
        return "“\(picked)” · \(firstName) sees it in their Workout tab"
    }

    private var traineeModeBody: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: currentPlan == nil ? "Assign plan" : "Change plan",
                background: .white,
                showsBack: false
            ) {
                Button("Cancel") { dismiss() }
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(minHeight: 44)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text("FOR")
                            .font(TTFont.workSans(12, weight: .bold))
                            .foregroundStyle(TTColor.inkMuted)
                        TTAvatar(name: fixedTraineeName, size: 32)
                        Text(fixedTraineeName)
                            .font(TTFont.workSans(16, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)

                    HStack {
                        Text("CHOOSE A PLAN")
                            .font(TTFont.workSans(12, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(TTColor.inkMuted)
                        Spacer(minLength: 8)
                        Text(isSearching ? "\(orderedPlans.count) of \(plans.count)" : "\(plans.count) \(plans.count == 1 ? "plan" : "plans")")
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(TTColor.inkMuted)
                    }

                    if plans.count > 6 {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(TTColor.inkMuted)
                            TextField("Search name or focus", text: $planSearch)
                                .font(TTFont.workSans(15, weight: .medium))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .focused($searchFocused)
                                .onSubmit { searchFocused = false }
                            if !planSearch.isEmpty {
                                Button {
                                    planSearch = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color(white: 0.7))
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear search")
                            }
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, planSearch.isEmpty ? 14 : 0)
                        .frame(height: 44)
                        .background(cardFill)
                        .clipShape(Capsule())
                    }

                    VStack(spacing: 10) {
                        createPlanRow
                        if plans.isEmpty {
                            Text("No plans yet")
                                .font(TTFont.workSans(14, weight: .medium))
                                .foregroundStyle(TTColor.inkMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        if isSearching && orderedPlans.isEmpty {
                            Text("No plans match “\(trimmedSearch)”. Create it above, or clear the search.")
                                .font(TTFont.workSans(14, weight: .medium))
                                .foregroundStyle(TTColor.inkMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(18)
                                .background(cardFill)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        ForEach(orderedPlans) { plan in
                            planRadioCard(plan)
                        }
                    }
                }
                .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                .padding(.top, TTModalSheetChrome.contentTopPadding)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.immediately)

            VStack(spacing: 10) {
                Text(traineeModeHint)
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity)

                // Same primary button as CreatePlanView's Continue: black, label left, arrow right.
                let canAssign = !planId.isEmpty && planId != currentPlan?.id
                Button {
                    Task { await assignForTrainee() }
                } label: {
                    HStack(spacing: 8) {
                        if isAssigning {
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Assign to \(firstName)")
                                .font(TTFont.workSans(16, weight: .bold))
                            Spacer(minLength: 8)
                            TTIcon(icon: .chevronRight, size: 14)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(canAssign ? Color.black : Color(white: 0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.98))
                .disabled(!canAssign || isAssigning)
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .ttToast($feedbackToast)
        .onAppear {
            traineeId = preselectedTraineeId ?? ""
            // Only the trainee's current plan is preselected; otherwise nothing is.
            if planId.isEmpty, newPlanId == nil { planId = currentPlan?.id ?? "" }
        }
    }

    private func planRadioCard(_ plan: WorkoutPlan) -> some View {
        let isOn = planId == plan.id
        let isCurrent = plan.id == currentPlan?.id
        let isNew = plan.id == newPlanId
        return Button {
            planId = plan.id
            searchFocused = false
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? TTColor.actionOrange : Color(white: 0.7))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(plan.title)
                            .font(TTFont.workSans(16, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if isNew {
                            Text("New")
                                .font(TTFont.caption(11))
                                .fontWeight(.bold)
                                .foregroundStyle(TTColor.actionOrange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(TTColor.actionOrange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        if isCurrent {
                            Text("Current")
                                .font(TTFont.caption(11))
                                .fontWeight(.bold)
                                .foregroundStyle(TTColor.success)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(TTColor.success.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    let focus = plan.focus.trimmingCharacters(in: .whitespaces)
                    if !focus.isEmpty {
                        Text(focus)
                            .font(TTFont.textSM(.medium))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    let meta = planMeta(plan)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(TTFont.textSM(.medium))
                            .foregroundStyle(TTColor.inkMuted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? TTColor.actionOrange : Color(white: 0.88), lineWidth: isOn ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// Trainee mode: close immediately; the opener shows the toast (with Undo).
    private func assignForTrainee() async {
        guard let preselectedTraineeId else { return }
        isAssigning = true
        defer { isAssigning = false }
        do {
            try await store.assign(planId: planId, to: preselectedTraineeId)
            onAssigned?()
            dismiss()
        } catch {
            feedbackToast = TTToastMessage(
                text: "Couldn’t assign plan",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    // MARK: Default mode

    private var defaultBody: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(title: "Assign to trainee", background: .white)

            VStack(alignment: .leading, spacing: 16) {
                createPlanRow

                if plans.isEmpty {
                    Text("No plans yet")
                        .font(TTFont.workSans(14, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                        .frame(maxWidth: .infinity)
                } else {
                    section("Plan") {
                        Picker("Plan", selection: $planId) {
                            Text("Select plan").tag("")
                            ForEach(orderedPlans) { plan in
                                Text(plan.id == newPlanId ? "\(plan.title) · New" : plan.title).tag(plan.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
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

                TTAssignSuccessButton(
                    title: "Assign plan",
                    isEnabled: !planId.isEmpty && !traineeId.isEmpty,
                    isLoading: isAssigning,
                    showSuccess: assignSucceeded
                ) {
                    Task { await assign() }
                }
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, TTModalSheetChrome.contentTopPadding)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .ttAssignSuccessChrome(toast: $feedbackToast, celebrate: $celebrateAssign)
        .onAppear {
            if let preselectedPlanId {
                // Opened for a specific plan: select it, let the coach pick the trainee.
                planId = preselectedPlanId
            } else {
                if planId.isEmpty { planId = plans.first?.id ?? "" }
                if traineeId.isEmpty { traineeId = trainees.first?.id ?? "" }
            }
        }
    }

    private func assign() async {
        isAssigning = true
        defer { isAssigning = false }
        do {
            try await store.assign(planId: planId, to: traineeId)
            let planTitle = plans.first(where: { $0.id == planId })?.title ?? "Plan"
            let traineeName = trainees.first(where: { $0.id == traineeId })
                .flatMap { store.user(forTrainee: $0)?.name } ?? "Trainee"
            TTAssignSuccessFeedback.play(
                toast: $feedbackToast,
                celebrate: $celebrateAssign,
                planTitle: planTitle,
                traineeName: traineeName
            )
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                assignSucceeded = true
            }
            try? await Task.sleep(for: .milliseconds(1100))
            dismiss()
            onAssigned?()
        } catch {
            feedbackToast = TTToastMessage(
                text: "Couldn’t assign plan",
                style: .error,
                subtitle: error.localizedDescription
            )
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
        let statusTitle: String
        let statusColor: Color
        let adherence: Int
    }

    private var rows: [Row] {
        guard let trainer = store.currentTrainer else { return [] }
        return store.trainees(for: trainer).map { trainee in
            let plan = store.assignedPlan(for: trainee)
            let assignment = store.assignments
                .filter { $0.traineeId == trainee.id }
                .sorted { $0.assignedAt > $1.assignedAt }
                .first
            let status = plan.map { store.planFollowStatus(traineeId: trainee.id, plan: $0) }
            let adherence = plan.map { store.planAdherencePercent(traineeId: trainee.id, plan: $0) } ?? 0
            let statusTitle: String
            let statusColor: Color
            if let status {
                statusTitle = status.title
                switch status {
                case .trainedToday, .following: statusColor = TTColor.success
                case .dueToday: statusColor = TTColor.actionOrange
                case .behind: statusColor = Color(red: 0.86, green: 0.45, blue: 0.14)
                case .notStarted: statusColor = TTColor.inkMuted
                }
            } else {
                statusTitle = "Idle"
                statusColor = TTColor.inkMuted
            }
            return Row(
                id: trainee.id,
                traineeName: store.user(forTrainee: trainee)?.name ?? "Trainee",
                planTitle: plan?.title ?? "No plan assigned",
                assignedAt: assignment?.assignedAt,
                hasPlan: plan != nil,
                statusTitle: statusTitle,
                statusColor: statusColor,
                adherence: adherence
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasPlan != rhs.hasPlan { return lhs.hasPlan && !rhs.hasPlan }
            return lhs.traineeName.localizedCaseInsensitiveCompare(rhs.traineeName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(title: "Plan assignments", background: .white)

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
                        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                        .padding(.top, TTModalSheetChrome.contentTopPadding)
                        .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
                    }
                }
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
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
                if row.hasPlan {
                    Text("\(row.adherence)% follow · \(row.statusTitle)")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }
                if let date = row.assignedAt, row.hasPlan {
                    Text("Assigned \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }
            }

            Spacer(minLength: 8)

            Text(row.statusTitle)
                .font(TTFont.caption(11))
                .fontWeight(.bold)
                .foregroundStyle(row.statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(row.statusColor.opacity(0.12))
                .clipShape(Capsule())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
