import SwiftUI

// MARK: - Create Plan (guided 3-step builder)

private enum CreatePlanStep: Int, CaseIterable, Hashable {
    case basics = 0
    case days = 1
    case sessions = 2

    var number: Int { rawValue + 1 }
    var total: Int { Self.allCases.count }

    var title: String {
        switch self {
        case .basics: "Program basics"
        case .days: "Training days"
        case .sessions: "Build sessions"
        }
    }

    var instruction: String {
        switch self {
        case .basics:
            "Name the plan and set level. You can refine focus and notes — or skip them for now."
        case .days:
            "Tap every day this program runs. You’ll add exercises on the next step."
        case .sessions:
            "Open a day, tap Add, and prescribe exercises. Only days with exercises are saved."
        }
    }

    var primaryTitle: String {
        switch self {
        case .basics, .days: "Continue"
        case .sessions: "Save plan"
        }
    }
}

struct CreatePlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When set, wizard edits this plan instead of creating a new one.
    var editingPlan: WorkoutPlan? = nil
    /// Called with the newly created plan after a successful create (not on edit).
    /// Lets a presenter (e.g. the trainee assign flow) pick up and select the new plan.
    var onCreate: ((WorkoutPlan) -> Void)? = nil
    /// When true, a successful create hands the plan to `onCreate` and closes — no saved screen.
    var returnAfterCreate: Bool = false
    /// Prefills step 1's name (e.g. from the assign sheet's search text). Ignored when editing.
    var initialTitle: String? = nil

    @State private var step: CreatePlanStep = .basics
    @State private var title = ""
    @State private var focus = ""
    @State private var level = "Intermediate"
    @State private var notes = ""
    @State private var selectedDays: [Weekday] = []
    @State private var sessions: [Weekday: SessionDraft] = [:]
    @State private var pickerDay: Weekday?
    @State private var isSaving = false
    @State private var error: String?
    @State private var showLeaveConfirm = false
    @State private var showSessionTips = false
    @State private var didHydrate = false
    @State private var showNotes = false
    @State private var hasChanges = false
    @State private var savedPlan: WorkoutPlan? = nil
    @State private var savedPlanResolved = false   // false → only the draft fallback was found
    @State private var showAssign = false
    @Environment(\.selectTrainerTab) private var selectTrainerTab

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange
    private let levels = ["Beginner", "Intermediate", "Advanced"]

    private var isEditing: Bool { editingPlan != nil }

    /// Trainee editing an AI-sourced plan — saves via `/trainee/ai-plans/{id}`, not trainer routes.
    private var savesAsTraineeAIPlan: Bool {
        guard let plan = editingPlan else { return false }
        return store.session?.role == .trainee
            && plan.isAISource
            && store.traineeCanEditDeleteAIPlan(plan)
    }

    private var stepMotion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.88)
    }

    private var canAdvance: Bool {
        switch step {
        case .basics:
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .days:
            !selectedDays.isEmpty && allDaysHaveTitleAndFocus
        case .sessions:
            canSave
        }
    }

    private var allDaysHaveTitleAndFocus: Bool {
        selectedDays.allSatisfy { day in
            guard let session = sessions[day] else { return false }
            return !session.title.trimmingCharacters(in: .whitespaces).isEmpty
                && !session.focus.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedDays.allSatisfy { !(sessions[$0]?.exercises.isEmpty ?? true) }
    }

    private var emptyDaysHint: String? {
        let empty = selectedDays.filter { sessions[$0]?.exercises.isEmpty ?? true }
        if empty.isEmpty { return nil }
        let names = empty.map { $0.short }.joined(separator: ", ")
        return "\(names) has no exercises. Days without exercises aren't saved. Add one or remove the day in step 2."
    }

    var body: some View {
        if let savedPlan {
            PlanSavedContent(
                plan: savedPlan,
                unassignedCount: unassignedTraineeCount,
                onDone: { dismiss() },
                onAssign: { showAssign = true },
                onViewInPlans: {
                    dismiss()
                    selectTrainerTab(.plans)
                }
            )
            .sheet(isPresented: $showAssign) {
                PlanQuickAssignSheet(
                    preselectedPlanId: savedPlanResolved ? savedPlan.id : nil,
                    onAssigned: { dismiss() }
                )
                .ttModalSheetPresentation()
            }
        } else {
            wizardBody
        }
    }

    /// Roster members with no assigned plan (existing roster + assigned-plan lookups).
    private var unassignedTraineeCount: Int {
        guard let trainer = store.currentTrainer else { return 0 }
        return store.trainees(for: trainer).filter { store.assignedPlan(for: $0) == nil }.count
    }

    private var wizardBody: some View {
        VStack(spacing: 0) {
            wizardHeader
            progressTrack

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TTModalSheetChrome.contentSpacing) {
                    Group {
                        switch step {
                        case .basics: basicsStep
                        case .days: daysStep
                        case .sessions: sessionsStep
                        }
                    }
                    .id(step)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            )
                    )

                    if let error {
                        Text(error)
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.danger)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                .padding(.top, TTModalSheetChrome.contentTopPadding)
                .padding(.bottom, 12)
                .animation(stepMotion, value: step)
            }

            wizardFooter
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .sheet(item: $pickerDay) { day in
            ExerciseLibrarySheet { draft in
                add(draft, to: day)
            }
            .ttModalSheetPresentation()
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            isEditing ? "Discard changes?" : "Discard this plan?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(isEditing ? "Discard changes" : "Discard plan", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(
                isEditing
                    ? "Your edits to this plan won't be saved."
                    : "Nothing has been saved yet."
            )
        }
        .onAppear {
            hydrateFromEditingPlanIfNeeded()
            if editingPlan == nil, title.isEmpty, let initialTitle, !initialTitle.isEmpty {
                title = initialTitle
                DispatchQueue.main.async { hasChanges = false }
            }
        }
    }

    // MARK: - Chrome

    private var wizardHeader: some View {
        HStack(alignment: .center, spacing: TTModalSheetChrome.headerSpacing) {
            if step != .basics {
                TTBackButton(
                    style: .onLight,
                    size: TTModalSheetChrome.controlSize
                ) {
                    goBack()
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isEditing ? "Edit Plan" : "New Plan")
                    .font(TTFont.workSans(20, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Step \(step.number) of \(CreatePlanStep.basics.total) · \(step.title)")
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.inkMuted)
                    .lineLimit(1)
            }

            Spacer()

            Button("Cancel") {
                requestLeave()
            }
            .font(TTFont.workSans(15, weight: .semibold))
            .foregroundStyle(TTColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
        .padding(.vertical, TTModalSheetChrome.headerVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            let fraction = CGFloat(step.number) / CGFloat(CreatePlanStep.basics.total)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.06))
                Capsule()
                    .fill(orange)
                    .frame(width: max(8, geo.size.width * fraction))
                    .animation(stepMotion, value: step)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    private var stepGuidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(step.instruction)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(orange.opacity(0.18), lineWidth: 1)
        )
    }

    private var wizardFooter: some View {
        VStack(spacing: 10) {
            if step == .basics {
                Text(basicsHint)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await advance() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(step == .sessions ? (isEditing ? "Save changes" : "Save plan") : step.primaryTitle)
                            .font(TTFont.workSans(16, weight: .bold))
                        if step != .sessions {
                            TTIcon(icon: .chevronRight, size: 14)
                        } else {
                            TTIcon(icon: .check, filled: true, size: 14)
                        }
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canAdvance ? Color.black : Color(white: 0.72))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(TTSearchPressStyle(scale: 0.98))
            .disabled(!canAdvance || isSaving)
            .accessibilityLabel(step.primaryTitle)
        }
        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            Color.white
                .shadow(color: .black.opacity(0.06), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var basicsHint: String {
        let titleEmpty = title.trimmingCharacters(in: .whitespaces).isEmpty
        let focusEmpty = focus.trimmingCharacters(in: .whitespaces).isEmpty

        if titleEmpty && focusEmpty {
            return "Add a plan name and a focus"
        } else if titleEmpty {
            return "Add a plan name to continue"
        } else if focusEmpty {
            return "Add a focus to continue"
        } else {
            return "Next: Training days"
        }
    }

    // MARK: - Steps

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Program", icon: .clipboard)

            labeledField("Plan title", "Required", text: $title, prompt: "e.g. 4-day strength block")
                .onChange(of: title) { _, _ in
                    if !isEditing { hasChanges = true }
                }
            labeledField("Focus", "Required", text: $focus, prompt: "e.g. Hypertrophy")
                .onChange(of: focus) { _, _ in
                    if !isEditing { hasChanges = true }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text("LEVEL")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkMuted)
                HStack(spacing: 8) {
                    ForEach(levels, id: \.self) { item in
                        let on = level == item
                        Button {
                            withAnimation(stepMotion) { level = item }
                        } label: {
                            Text(item)
                                .font(TTFont.workSans(13, weight: .semibold))
                                .foregroundStyle(on ? .white : TTColor.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(on ? orange : Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onChange(of: level) { _, _ in
                    if !isEditing { hasChanges = true }
                }
            }

            if showNotes || !notes.isEmpty {
                sandowField(
                    "Coach notes (optional)",
                    text: $notes,
                    prompt: "How this week should feel, deload rules…",
                    axis: .vertical
                )
                .onChange(of: notes) { _, _ in
                    if !isEditing { hasChanges = true }
                }
            } else {
                Button {
                    withAnimation(stepMotion) { showNotes = true }
                } label: {
                    Text("Add coach notes (optional)")
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }

            if let duplicateWarning = duplicateNameWarning {
                Text(duplicateWarning)
                    .font(TTFont.caption(12))
                    .foregroundStyle(orange)
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func labeledField(_ title: String, _ required: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkMuted)
                Spacer()
                Text(required)
                    .font(TTFont.caption(10))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            TTSandowLabeledField(title: "", prompt: prompt, axis: .horizontal, idleFill: .white, text: text)
        }
    }

    private var duplicateNameWarning: String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return nil }

        let existingPlans = store.plans.filter { $0.trainerId == store.currentTrainer?.id }
        let plansToCheck = isEditing
            ? existingPlans.filter { $0.id != editingPlan?.id }
            : existingPlans

        let hasDuplicate = plansToCheck.contains { $0.title.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveContains(trimmedTitle) }

        if hasDuplicate {
            return "You already have a plan with this name. A different name makes them easier to tell apart."
        }
        return nil
    }

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("This week’s days", icon: .calendar1)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    let on = selectedDays.contains(day)
                    Button {
                        withAnimation(stepMotion) { toggle(day) }
                    } label: {
                        Text(day.short)
                            .font(TTFont.workSans(13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(on ? .white : TTColor.ink)
                            .background(on ? orange : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(on ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(TTSearchPressStyle(scale: 0.97))
                }
            }

            if selectedDays.isEmpty {
                tipRow("Select at least one training day.")
            } else {
                Text("\(selectedDays.count) day\(selectedDays.count == 1 ? "" : "s") selected")
                    .font(TTFont.caption(12))
                    .foregroundStyle(orange)
                    .fontWeight(.semibold)

                if !daysMissingTitleOrFocus.isEmpty {
                    let missing = daysMissingTitleOrFocus.map { $0.short }.joined(separator: ", ")
                    tipRow("Add a title and target muscles for \(missing).")
                }
            }
        }
        .padding(18)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var sessionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Sessions", icon: .kettlebell)
                Spacer()
                Button {
                    withAnimation(stepMotion) { showSessionTips.toggle() }
                } label: {
                    Text(showSessionTips ? "Hide tips" : "Tips")
                        .font(TTFont.workSans(12, weight: .bold))
                        .foregroundStyle(orange)
                }
                .buttonStyle(.plain)
            }

            if showSessionTips {
                tipRow("Expand a day → Add exercise → set reps & weight. Collapse days you are done with.")
            }

            if selectedDays.isEmpty {
                tipRow("Go back and pick training days first.")
            } else {
                ForEach(selectedDays, id: \.self) { day in
                    if let binding = binding(for: day) {
                        SessionEditor(day: day, draft: binding, addExercise: { pickerDay = day }, isEditing: isEditing, onChange: { hasChanges = true })
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }

            if !canSave, !selectedDays.isEmpty {
                if let hint = emptyDaysHint {
                    tipRow(hint)
                } else {
                    tipRow("Add at least one exercise to any day before saving.")
                }
            }
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            TTIcon(icon: .infoCircle, filled: true, size: 14)
                .foregroundStyle(orange)
                .padding(.top, 1)
            Text(text)
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionLabel(_ title: String, icon: SandowIcon) -> some View {
        HStack(spacing: 8) {
            TTIcon(icon: icon, filled: true, size: 16)
                .foregroundStyle(orange)
            Text(title)
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(TTColor.ink)
        }
    }

    private func sandowField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        axis: Axis = .horizontal
    ) -> some View {
        TTSandowLabeledField(title: title, prompt: prompt, axis: axis, idleFill: .white, text: text)
    }

    // MARK: - Navigation

    private func goBack() {
        error = nil
        if step == .basics {
            requestLeave()
            return
        }
        withAnimation(stepMotion) {
            if let prev = CreatePlanStep(rawValue: step.rawValue - 1) {
                step = prev
            }
        }
    }

    private func advance() async {
        error = nil
        switch step {
        case .basics, .days:
            guard canAdvance, let next = CreatePlanStep(rawValue: step.rawValue + 1) else { return }
            withAnimation(stepMotion) { step = next }
        case .sessions:
            await save()
        }
    }

    private func requestLeave() {
        if hasChanges {
            showLeaveConfirm = true
        } else {
            dismiss()
        }
    }

    // MARK: - Logic

    private func toggle(_ day: Weekday) {
        if let index = selectedDays.firstIndex(of: day) {
            selectedDays.remove(at: index)
            sessions[day] = nil
        } else {
            selectedDays.append(day)
            selectedDays.sort { $0.sortIndex < $1.sortIndex }
            let sessionTitle = sessionTitleForDay(day)
            let session = SessionDraft(day: day, focus: focus)
            sessions[day] = session
            if session.title.isEmpty {
                sessions[day]?.title = sessionTitle
            }
            if session.focus.isEmpty {
                sessions[day]?.focus = focus
            }
        }
        if !isEditing { hasChanges = true }
    }

    private func sessionTitleForDay(_ day: Weekday) -> String {
        let sortedDays = selectedDays.sorted { $0.sortIndex < $1.sortIndex }
        guard let index = sortedDays.firstIndex(of: day) else { return "" }
        let letters = ["A", "B", "C", "D", "E", "F", "G"]
        return "Session \(letters[index % letters.count])"
    }

    private var daysMissingTitleOrFocus: [Weekday] {
        selectedDays.filter { day in
            guard let session = sessions[day] else { return true }
            return session.title.trimmingCharacters(in: .whitespaces).isEmpty
                || session.focus.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func binding(for day: Weekday) -> Binding<SessionDraft>? {
        guard sessions[day] != nil else { return nil }
        return Binding(
            get: { sessions[day] ?? SessionDraft(day: day, focus: focus) },
            set: { sessions[day] = $0 }
        )
    }

    private func add(_ draft: ExerciseDraft, to day: Weekday) {
        sessions[day, default: SessionDraft(day: day, focus: focus)].exercises.append(draft)
        if !isEditing { hasChanges = true }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        let planDays = selectedDays.compactMap { sessions[$0]?.asPlanDay() }
        let flat = planDays.flatMap(\.exercises)

        if savesAsTraineeAIPlan, let existing = editingPlan {
            let draft = WorkoutPlan(
                id: existing.id,
                trainerId: existing.trainerId,
                title: title,
                focus: focus,
                durationMinutes: planDays.map(\.durationMinutes).max() ?? 45,
                level: level,
                daysPerWeek: planDays.count,
                exercises: flat,
                notes: notes.isEmpty ? nil : notes,
                days: planDays,
                source: "ai"
            )
            do {
                try await store.updateAIPlan(draft)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            return
        }

        guard let trainer = store.currentTrainer else { return }
        let draft = WorkoutPlan(
            id: editingPlan?.id ?? UUID().uuidString,
            trainerId: trainer.id,
            title: title,
            focus: focus,
            durationMinutes: planDays.map(\.durationMinutes).max() ?? 45,
            level: level,
            daysPerWeek: planDays.count,
            exercises: flat,
            notes: notes.isEmpty ? nil : notes,
            days: planDays,
            source: "trainer"
        )
        do {
            if isEditing {
                try await store.updatePlan(draft)
                dismiss()
            } else {
                try await store.createPlan(draft)
                // createPlan returns Void → read the stored copy (server id may differ from the draft's).
                let resolved = store.plans.first { $0.id == draft.id }
                    ?? store.plans.last { $0.title == draft.title && $0.trainerId == draft.trainerId }
                let created = resolved ?? draft
                onCreate?(created)
                hasChanges = false
                if returnAfterCreate {
                    dismiss()
                    return
                }
                savedPlanResolved = resolved != nil
                withAnimation(stepMotion) { savedPlan = created }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func hydrateFromEditingPlanIfNeeded() {
        guard !didHydrate, let plan = editingPlan else { return }
        didHydrate = true
        title = plan.title
        focus = plan.focus
        level = plan.level.isEmpty ? "Intermediate" : plan.level
        notes = plan.notes ?? ""
        // De-duplicate by weekday — keep the last entry if the plan has duplicate days
        let uniqueDays = plan.scheduledDays.reduce(into: [Weekday: PlanDay]()) { $0[$1.weekday] = $1 }
        selectedDays = Array(uniqueDays.keys)
        sessions = uniqueDays.mapValues { SessionDraft(from: $0) }
        hasChanges = false
        // onChange handlers fire after this pass — reset again once they've run.
        DispatchQueue.main.async { hasChanges = false }
    }
}

/// Keeps a loaded value visible unchanged when it isn't in the preset list.
private func pickerOptions(_ base: [Int], including value: Int) -> [Int] {
    base.contains(value) ? base : (base + [value]).sorted()
}

// MARK: - Drafts

struct SessionDraft {
    var day: Weekday
    var time = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    var title = ""
    var focus = ""
    var duration = 55
    var location = "Gym"
    var warmup = "5 min easy cardio, then hip openers and 2 empty-bar sets."
    var cooldown = "Walk 3 minutes. Stretch the trained muscles."
    var coachNotes = ""
    var exercises: [ExerciseDraft] = []

    init(day: Weekday, focus: String = "") {
        self.day = day 
        self.focus = focus
    }

    init(from planDay: PlanDay) {
        day = planDay.weekday
        time = Date.fromHHMM(planDay.startTime) ?? Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
        title = planDay.title
        focus = planDay.focus
        duration = planDay.durationMinutes
        location = planDay.location ?? "Gym"
        warmup = planDay.warmup ?? ""
        cooldown = planDay.cooldown ?? ""
        coachNotes = planDay.coachNotes ?? ""
        exercises = planDay.exercises.map(ExerciseDraft.init(from:))
    }

    func asPlanDay() -> PlanDay {
        PlanDay(
            id: UUID().uuidString,
            weekday: day,
            startTime: time.hhmm,
            title: title.isEmpty ? "\(day.title) session" : title,
            focus: focus,
            durationMinutes: duration,
            location: location,
            warmup: warmup.isEmpty ? nil : warmup,
            cooldown: cooldown.isEmpty ? nil : cooldown,
            coachNotes: coachNotes.isEmpty ? nil : coachNotes,
            exercises: exercises.map { $0.asExercise() }
        )
    }
}

struct ExerciseDraft: Identifiable {
    var id = UUID()
    var exerciseId: String
    /// Saved template label shown as subtitle under the exercise name.
    var templateName: String = ""
    var sets = 4
    var reps = 8
    var rest = 90
    var weight = 40.0
    var tempo = "3-1-1-0"
    var rpe = 7.5
    var howTo = "Brace, control the eccentric, full lockout, no bouncing."
    var side = "Both"
    var setRows: [SetDraft]
    /// UI: exercise card expanded in the day editor.
    var isExpanded: Bool = false

    init(exerciseId: String, templateName: String = "") {
        self.exerciseId = exerciseId
        self.templateName = templateName
        self.setRows = (1...4).map { SetDraft(setNumber: $0, reps: 8, weight: 40) }
    }

    init(from exercise: WorkoutExercise) {
        let workingWeight = exercise.recommendedWeightKg ?? 0
        let workingReps = max(1, exercise.reps)
        let workingSetsCount = max(1, exercise.sets)
        let sourceRows = exercise.workingSets
        let builtRows: [SetDraft]
        if sourceRows.isEmpty {
            builtRows = (1...workingSetsCount).map {
                SetDraft(setNumber: $0, reps: workingReps, weight: workingWeight)
            }
        } else {
            builtRows = sourceRows.map {
                SetDraft(setNumber: $0.setNumber, reps: $0.reps, weight: $0.weightKg ?? workingWeight)
            }
        }

        exerciseId = exercise.exerciseId
        sets = builtRows.count <= 0 ? 4 : builtRows.count
        reps = workingReps <= 0 ? 8 : workingReps
        rest = exercise.restSeconds <= 0 ? 90 : exercise.restSeconds
        weight = workingWeight
        tempo = exercise.tempo ?? "3-1-1-0"
        rpe = exercise.rpe ?? 7.5
        howTo = exercise.notes ?? ""
        side = exercise.side ?? "Both"
        setRows = builtRows
    }

    var prescriptionSummary: String {
        "\(sets)×\(reps) · \(weight.cleanKg) kg · \(rest)s rest"
    }

    mutating func syncSetCount() {
        if setRows.count < sets {
            let last = setRows.last
            for number in (setRows.count + 1)...sets {
                setRows.append(SetDraft(setNumber: number, reps: last?.reps ?? reps, weight: last?.weight ?? weight))
            }
        } else if setRows.count > sets {
            setRows = Array(setRows.prefix(sets))
        }
        for index in setRows.indices {
            setRows[index].setNumber = index + 1
        }
        weight = setRows.last?.weight ?? weight
        reps = setRows.last?.reps ?? reps
    }

    func asExercise() -> WorkoutExercise {
        WorkoutExercise(
            id: UUID().uuidString,
            exerciseId: exerciseId,
            sets: sets,
            reps: reps,
            restSeconds: rest,
            recommendedWeightKg: weight,
            tempo: tempo,
            rpe: rpe,
            notes: howTo,
            side: side,
            prescribedSets: setRows.map {
                PrescribedSet(id: UUID().uuidString, setNumber: $0.setNumber, reps: $0.reps, weightKg: $0.weight, rpe: rpe)
            }
        )
    }
}

struct SetDraft: Identifiable {
    var id = UUID()
    var setNumber: Int
    var reps: Int
    var weight: Double
}

// MARK: - Session editor

struct SessionEditor: View {
    let day: Weekday
    @Binding var draft: SessionDraft
    var addExercise: () -> Void
    var isEditing: Bool = false
    var onChange: () -> Void = {}

    @Environment(AppStore.self) private var store
    @State private var isExpanded = false
    @State private var showMoreOptions = false

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange
    private let locations = ["Gym", "Home", "Outdoor", "Studio"]

    private var morph: Animation {
        .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var sessionSubtitle: String {
        let name = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let focus = draft.focus.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = name.isEmpty ? (focus.isEmpty ? "\(day.title) session" : focus) : name
        return "\(head) · \(draft.exercises.count) moves · \(draft.duration) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    sessionFields
                    exercisesBlock
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 4)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            } else if !draft.exercises.isEmpty {
                collapsedExercisePreview
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(morph, value: isExpanded)
        .animation(morph, value: draft.exercises.count)
        .animation(morph, value: showMoreOptions)
    }

    // MARK: Header

    private var dayHeader: some View {
        Button {
            withAnimation(morph) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(orange.opacity(0.14))
                    TTIcon(icon: .calendar1, filled: true, size: 16)
                        .foregroundStyle(orange)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(day.title)
                            .font(TTFont.workSans(17, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        if draft.exercises.isEmpty {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(orange)
                                .font(.system(size: 16))
                                .accessibilityLabel("\(day.title), no exercises yet")
                        }
                    }
                    Text(sessionSubtitle)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: addExercise) {
                    HStack(spacing: 5) {
                        TTIcon(icon: .plus, filled: true, size: 11)
                        Text("Add")
                            .font(TTFont.workSans(12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.96))

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
        .accessibilityLabel(isExpanded ? "Collapse \(day.title)" : "Expand \(day.title)")
    }

    private var collapsedExercisePreview: some View {
        VStack(spacing: 8) {
            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(TTFont.workSans(12, weight: .bold))
                        .foregroundStyle(orange)
                        .frame(width: 22, height: 22)
                        .background(orange.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.exercise(id: item.exerciseId)?.name ?? "Exercise")
                            .font(TTFont.workSans(14, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                            .lineLimit(1)
                        Text(item.templateName.isEmpty ? item.prescriptionSummary : item.templateName)
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(item.prescriptionSummary)
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: Fields

    private var sessionFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            TTSandowLabeledField(title: "Session name", prompt: "Lower strength", idleFill: .white, text: $draft.title)
                .onChange(of: draft.title) { _, _ in
                    if !isEditing { onChange() }
                }
            TTSandowLabeledField(title: "Focus", prompt: "Squat pattern + hamstrings", idleFill: .white, text: $draft.focus)
                .onChange(of: draft.focus) { _, _ in
                    if !isEditing { onChange() }
                }

            HStack(spacing: 12) {
                labeled("When") {
                    DatePicker("", selection: $draft.time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: draft.time) { _, _ in
                    if !isEditing { onChange() }
                }
                TTDropPicker(
                    title: "Minutes",
                    selection: $draft.duration,
                    options: Array(stride(from: 20, through: 120, by: 5)),
                    format: { "\($0) min" }
                )
                .onChange(of: draft.duration) { _, _ in
                    if !isEditing { onChange() }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("WHERE")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkMuted)
                HStack(spacing: 6) {
                    ForEach(locations, id: \.self) { place in
                        let on = draft.location == place
                        Button {
                            draft.location = place
                            if !isEditing { onChange() }
                        } label: {
                            Text(place)
                                .font(TTFont.workSans(12, weight: .semibold))
                                .foregroundStyle(on ? .white : TTColor.ink)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(on ? orange : Color.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                withAnimation(morph) { showMoreOptions.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(showMoreOptions ? "Hide warm-up & notes" : "More options")
                        .font(TTFont.workSans(13, weight: .bold))
                    Spacer()
                    TTIcon(icon: .chevronDown, size: 12)
                        .rotationEffect(.degrees(showMoreOptions ? 180 : 0))
                }
                .foregroundStyle(orange)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if showMoreOptions {
                VStack(alignment: .leading, spacing: 14) {
                    TTSandowLabeledField(
                        title: "How to start (warm-up)",
                        prompt: "Warm-up",
                        axis: .vertical,
                        idleFill: .white,
                        text: $draft.warmup
                    )
                    .onChange(of: draft.warmup) { _, _ in
                        if !isEditing { onChange() }
                    }
                    TTSandowLabeledField(
                        title: "How to finish (cool-down)",
                        prompt: "Cool-down",
                        axis: .vertical,
                        idleFill: .white,
                        text: $draft.cooldown
                    )
                    .onChange(of: draft.cooldown) { _, _ in
                        if !isEditing { onChange() }
                    }
                    TTSandowLabeledField(
                        title: "How they should do this day",
                        prompt: "Pace, rest rules, form priority…",
                        axis: .vertical,
                        idleFill: .white,
                        text: $draft.coachNotes
                    )
                    .onChange(of: draft.coachNotes) { _, _ in
                        if !isEditing { onChange() }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var exercisesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Exercises")
                    .font(TTFont.workSans(16, weight: .bold))
                Spacer()
                volumeLabel
            }

            if draft.exercises.isEmpty {
                Text("Tap Add to pick an exercise and template.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach($draft.exercises) { $item in
                    ExerciseDraftEditor(draft: $item, isEditing: isEditing, onChange: onChange)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                }
            }
        }
    }

    private var volumeLabel: some View {
        let count = draft.exercises.count
        let (text, color): (String, Color) = {
            switch count {
            case 0...3: ("Aim for 4–6 exercises", TTColor.inkMuted)
            case 4...6: ("Good volume", TTColor.success)
            case 7: ("Upper limit", orange)
            default: ("Too many — trainees tire out", orange)
            }
        }()
        return Text(text)
            .font(TTFont.caption(11))
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Exercise draft editor

struct ExerciseDraftEditor: View {
    @Environment(AppStore.self) private var store
    @Binding var draft: ExerciseDraft
    @FocusState private var howToFocused: Bool
    @State private var showMoreOptions = false
    var isEditing: Bool = false
    var onChange: () -> Void = {}

    private let orange = TTColor.actionOrange

    private var morph: Animation {
        .spring(response: 0.32, dampingFraction: 0.88)
    }

    private var hasNonDefaults: Bool {
        draft.weight != 40.0 ||
        draft.tempo != "3-1-1-0" ||
        draft.rpe != 7.5 ||
        !draft.howTo.isEmpty ||
        draft.setRows.count != 4 ||
        draft.setRows.contains(where: { $0.reps != 8 || $0.weight != 40.0 })
    }

    private var exerciseTitle: String {
        store.exercise(id: draft.exerciseId)?.name ?? "Exercise"
    }

    private var subtitle: String {
        if !draft.templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return draft.templateName
        }
        return store.exercise(id: draft.exerciseId).map { "\($0.muscleGroup) · \($0.equipment)" } ?? draft.prescriptionSummary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(morph) { draft.isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(orange.opacity(0.12))
                        TTIcon(icon: .kettlebell, filled: true, size: 16)
                            .foregroundStyle(orange)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(exerciseTitle)
                            .font(TTFont.workSans(15, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(TTFont.caption(12))
                            .foregroundStyle(orange.opacity(0.95))
                            .lineLimit(1)
                        if !draft.isExpanded {
                            HStack(spacing: 4) {
                                Text("Rest \(draft.rest)s")
                                    .font(TTFont.caption(11))
                                    .foregroundStyle(TTColor.inkMuted)
                                Text("·")
                                    .foregroundStyle(TTColor.inkSubtle)
                                Text(draft.prescriptionSummary)
                                    .font(TTFont.caption(11))
                                    .foregroundStyle(TTColor.inkMuted)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .fill(Color(white: 0.94))
                            .frame(width: 30, height: 30)
                        TTIcon(icon: .chevronDown, size: 12)
                            .foregroundStyle(TTColor.inkMuted)
                            .rotationEffect(.degrees(draft.isExpanded ? 180 : 0))
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onAppear {
                if hasNonDefaults {
                    showMoreOptions = true
                }
            }
            .onChange(of: hasNonDefaults) { _, newValue in
                if newValue && !showMoreOptions {
                    showMoreOptions = true
                }
            }

            if draft.isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if !draft.templateName.isEmpty {
                        HStack(spacing: 6) {
                            TTIcon(icon: .layerThree, filled: true, size: 12)
                            Text("Template · \(draft.templateName)")
                                .font(TTFont.caption(12))
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(orange.opacity(0.1))
                        .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        TTDropPicker(title: "Sets", selection: $draft.sets, options: pickerOptions(Array(1...8), including: draft.sets))
                            .onChange(of: draft.sets) { _, _ in
                                draft.syncSetCount()
                                if !isEditing { onChange() }
                            }
                        TTDropPicker(
                            title: "Reps",
                            selection: $draft.reps,
                            options: pickerOptions(Array(1...30), including: draft.reps),
                            format: { "\($0)" }
                        )
                        .onChange(of: draft.reps) { _, value in
                            for index in draft.setRows.indices { draft.setRows[index].reps = value }
                            if !isEditing { onChange() }
                        }
                        TTDropPicker(
                            title: "Rest",
                            selection: $draft.rest,
                            options: pickerOptions([20, 30, 45, 60, 75, 90, 120, 150, 180, 210, 240], including: draft.rest),
                            format: { "\($0)s" }
                        )
                        .onChange(of: draft.rest) { _, _ in
                            if !isEditing { onChange() }
                        }
                    }

                    Button {
                        withAnimation(morph) { showMoreOptions.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showMoreOptions ? "Hide options" : "More options")
                                .font(TTFont.workSans(12, weight: .bold))
                            Spacer()
                            TTIcon(icon: .chevronDown, size: 10)
                                .rotationEffect(.degrees(showMoreOptions ? 180 : 0))
                        }
                        .foregroundStyle(orange)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)

                    if showMoreOptions {
                        VStack(alignment: .leading, spacing: 12) {
                            TTDropPicker(
                                title: "Working weight",
                                selection: $draft.weight,
                                options: PlanPickValues.weights,
                                format: { "\($0.cleanKg) kg" }
                            )
                            .onChange(of: draft.weight) { _, value in
                                for index in draft.setRows.indices { draft.setRows[index].weight = value }
                                if !isEditing { onChange() }
                            }

                            VStack(spacing: 8) {
                                ForEach($draft.setRows) { $row in
                                    HStack(spacing: 8) {
                                        Text("Set \(row.setNumber)")
                                            .font(TTFont.workSans(13, weight: .semibold))
                                            .foregroundStyle(TTColor.ink)
                                            .frame(width: 52, alignment: .leading)
                                        TTDropPicker(
                                            selection: $row.reps,
                                            options: pickerOptions(Array(1...30), including: row.reps),
                                            format: { "\($0) reps" }
                                        )
                                        .onChange(of: row.reps) { _, _ in
                                            if !isEditing { onChange() }
                                        }
                                        TTDropPicker(
                                            selection: $row.weight,
                                            options: PlanPickValues.weights,
                                            format: { "\($0.cleanKg) kg" }
                                        )
                                        .onChange(of: row.weight) { _, _ in
                                            if !isEditing { onChange() }
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                TTDropPicker(
                                    title: "Tempo",
                                    selection: $draft.tempo,
                                    options: ["3-1-1-0", "2-0-2-0", "3-0-1-0", "4-1-1-0", "2-1-1-0", "1-0-X-0", "Explosive"]
                                )
                                .onChange(of: draft.tempo) { _, _ in
                                    if !isEditing { onChange() }
                                }
                                TTDropPicker(
                                    title: "RPE",
                                    selection: $draft.rpe,
                                    options: PlanPickValues.rpe,
                                    format: { String(format: "%g", $0) }
                                )
                                .onChange(of: draft.rpe) { _, _ in
                                    if !isEditing { onChange() }
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("HOW TO PERFORM")
                                    .font(TTFont.caption(10))
                                    .foregroundStyle(TTColor.inkSubtle)
                                TextField("Cues, depth, grip, breathing…", text: $draft.howTo, axis: .vertical)
                                    .font(TTFont.body(14))
                                    .lineLimit(2...5)
                                    .focused($howToFocused)
                                    .tint(orange)
                                    .padding(10)
                                    .onChange(of: draft.howTo) { _, _ in
                                        if !isEditing { onChange() }
                                    }
                                    .ttInputChrome(
                                        focused: howToFocused,
                                        cornerRadius: 12,
                                        idleFill: Color(white: 0.97)
                                    )
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(draft.isExpanded ? orange.opacity(0.28) : Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: draft.isExpanded ? orange.opacity(0.08) : .clear, radius: 10, y: 4)
        .animation(morph, value: draft.isExpanded)
    }
}

// MARK: - Exercise library

struct ExerciseLibrarySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (ExerciseDraft) -> Void

    @State private var query = ""
    @State private var showCreateExercise = false
    @FocusState private var searchFocused: Bool
    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange

    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.exercises }
        return store.exercises.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.muscleGroup.localizedCaseInsensitiveContains(q)
                || $0.equipment.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(title: "Add exercise", background: .white)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            TTIcon(icon: .magnifyingGlass, size: 16)
                                .foregroundStyle(searchFocused ? orange : TTColor.inkMuted)
                            TextField("Search exercises", text: $query)
                                .font(TTFont.body(15))
                                .focused($searchFocused)
                                .tint(orange)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .ttInputChrome(
                            focused: searchFocused,
                            cornerRadius: 16,
                            idleFill: cardFill
                        )

                        // Create-new option alongside the existing exercise list — stays on
                        // this screen after saving so the trainer never loses their place.
                        Button {
                            showCreateExercise = true
                        } label: {
                            HStack(spacing: 10) {
                                TTIcon(icon: .plus, filled: true, size: 15)
                                Text("Create new exercise")
                                    .font(TTFont.workSans(15, weight: .semibold))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(orange)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(orange.opacity(0.4), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(TTSearchPressStyle(scale: 0.99))

                        if filtered.isEmpty {
                            Text("No matches")
                                .font(TTFont.body(14))
                                .foregroundStyle(TTColor.inkMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(filtered) { exercise in
                                NavigationLink {
                                    ExerciseTemplatePickerView(exercise: exercise) { draft in
                                        onPick(draft)
                                        dismiss()
                                    }
                                } label: {
                                    exerciseRow(exercise)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                    .padding(.top, TTModalSheetChrome.contentTopPadding)
                    .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
                }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .sheet(isPresented: $showCreateExercise) {
                CreateExerciseSheet { name, muscleGroup, equipment, difficulty in
                    let created = store.addCustomExercise(
                        name: name,
                        muscleGroup: muscleGroup,
                        equipment: equipment,
                        difficulty: difficulty
                    )
                    // Surface the new exercise at the top of this same list.
                    query = ""
                    _ = created
                }
                .ttModalSheetPresentation()
            }
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        let count = store.templates(forExerciseId: exercise.id).count
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(orange.opacity(0.12))
                TTIcon(icon: .kettlebell, filled: true, size: 18)
                    .foregroundStyle(orange)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text("\(exercise.muscleGroup) · \(exercise.equipment) · \(exercise.difficulty)")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                if count > 0 {
                    Text("\(count) saved template\(count == 1 ? "" : "s")")
                        .font(TTFont.caption(11))
                        .foregroundStyle(orange)
                }
            }

            Spacer(minLength: 0)
            TTIcon(icon: .chevronRight, size: 14)
                .foregroundStyle(TTColor.inkSubtle)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Create custom exercise

/// Lightweight form to define a new exercise inline, without leaving the picker flow.
struct CreateExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (_ name: String, _ muscleGroup: String, _ equipment: String, _ difficulty: String) -> Void

    @State private var name = ""
    @State private var muscleGroup = ""
    @State private var equipment = ""
    @State private var difficulty = "Intermediate"
    @FocusState private var focusedField: Field?

    private enum Field { case name, muscle, equipment }
    private let difficulties = ["Beginner", "Intermediate", "Advanced"]
    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(title: "New exercise", background: .white)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    field("EXERCISE NAME", placeholder: "e.g. Cable Fly", text: $name, focus: .name)
                    field("MUSCLE GROUP", placeholder: "e.g. Chest", text: $muscleGroup, focus: .muscle)
                    field("EQUIPMENT", placeholder: "e.g. Cable", text: $equipment, focus: .equipment)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("DIFFICULTY")
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkMuted)
                        Picker("Difficulty", selection: $difficulty) {
                            ForEach(difficulties, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        onCreate(name, muscleGroup, equipment, difficulty)
                        dismiss()
                    } label: {
                        Text("Create exercise")
                            .font(TTFont.workSans(16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(canSave ? Color.black : Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(TTSearchPressStyle(scale: 0.98))
                    .disabled(!canSave)
                    .padding(.top, 4)
                }
                .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                .padding(.top, TTModalSheetChrome.contentTopPadding)
                .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
            TextField(placeholder, text: text)
                .font(TTFont.body(16))
                .focused($focusedField, equals: focus)
                .tint(orange)
                .padding(12)
                .ttInputChrome(
                    focused: focusedField == focus,
                    cornerRadius: 12,
                    idleFill: .white
                )
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum PlanPickValues {
    static let weights: [Double] = stride(from: 0.0, through: 220.0, by: 2.5).map { $0 }
    static let rpe: [Double] = stride(from: 5.0, through: 10.0, by: 0.5).map { $0 }
}

extension Date {
    var hhmm: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func fromHHMM(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }
}

#Preview("Create Plan") {
    CreatePlanView()
        .ttPreviewTrainer()
}

// MARK: - Saved: what next?

/// Shown in the same sheet after a NEW plan is saved (create mode only).
private struct PlanSavedContent: View {
    let plan: WorkoutPlan
    let unassignedCount: Int
    var onDone: () -> Void
    var onAssign: () -> Void
    var onViewInPlans: () -> Void

    private let canvas = Color(white: 0.97)
    private let orange = TTColor.actionOrange

    private var exerciseCount: Int { plan.days.reduce(0) { $0 + $1.exercises.count } }
    private var setCount: Int { plan.days.flatMap(\.exercises).reduce(0) { $0 + $1.sets } }

    private var assignSubtitle: String {
        switch unassignedCount {
        case 0: "Pick who should train with it"
        case 1: "1 trainee has no plan yet"
        default: "\(unassignedCount) trainees have no plan yet"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(orange)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.vertical, TTModalSheetChrome.headerVerticalPadding)
            .background(Color.white)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(TTColor.success)
                            .frame(width: 64, height: 64)
                            .overlay(TTIcon(icon: .check, filled: true, size: 28).foregroundStyle(.white))
                            .accessibilityHidden(true)
                        Text("Plan saved")
                            .font(TTFont.workSans(24, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Text(plan.title)
                            .font(TTFont.workSans(17, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                            .multilineTextAlignment(.center)
                        Text("\(plan.level) · \(plan.daysPerWeek) days/week · \(plan.durationMinutes) min")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.inkMuted)
                        Text("\(exerciseCount) exercises · \(setCount) sets")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                    Text("WHAT'S NEXT?")
                        .font(TTFont.workSans(12, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(TTColor.inkMuted)

                    VStack(spacing: 12) {
                        nextRow(title: "Assign to a trainee", subtitle: assignSubtitle,
                                icon: .userPlus, dark: true, action: onAssign)
                        nextRow(title: "View in Plans", subtitle: "Review it with your other plans",
                                icon: .barbellDiagonal, dark: false, action: onViewInPlans)
                    }

                    Text("Tap Done to go back. You can assign it any time from Plans.")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                .padding(.top, TTModalSheetChrome.contentTopPadding)
                .padding(.bottom, 24)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }

    private func nextRow(title: String, subtitle: String, icon: SandowIcon, dark: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                TTIcon(icon: icon, filled: true, size: 20)
                    .foregroundStyle(dark ? .white : orange)
                    .frame(width: 44, height: 44)
                    .background(dark ? orange : orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(TTFont.workSans(16, weight: .semibold))
                        .foregroundStyle(dark ? .white : TTColor.ink)
                    Text(subtitle)
                        .font(TTFont.caption(13))
                        .foregroundStyle(dark ? Color.white.opacity(0.7) : TTColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                TTChevronForward(color: dark ? Color.white.opacity(0.7) : Color(white: 0.55))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dark ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}
