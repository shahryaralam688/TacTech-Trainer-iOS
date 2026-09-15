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

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange
    private let levels = ["Beginner", "Intermediate", "Advanced"]

    private var stepMotion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.88)
    }

    private var hasDraftProgress: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedDays.isEmpty
            || sessions.values.contains { !$0.exercises.isEmpty }
    }

    private var canAdvance: Bool {
        switch step {
        case .basics:
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .days:
            !selectedDays.isEmpty
        case .sessions:
            canSave
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedDays.contains { !(sessions[$0]?.exercises.isEmpty ?? true) }
    }

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            progressTrack

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TTModalSheetChrome.contentSpacing) {
                    stepGuidance

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
        .confirmationDialog(
            "Continue later?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue later", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This plan isn’t saved yet. You can start again anytime from Plans.")
        }
    }

    // MARK: - Chrome

    private var wizardHeader: some View {
        TTModalSheetHeader(
            title: "New Plan",
            subtitle: "Step \(step.number) of \(CreatePlanStep.basics.total)",
            background: .white,
            onBack: { goBack() }
        ) {
            Text("\(step.number)/\(CreatePlanStep.basics.total)")
                .font(TTFont.workSans(13, weight: .bold))
                .foregroundStyle(TTColor.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(white: 0.94))
                .clipShape(Capsule())
        }
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
            Button {
                Task { await advance() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(step.primaryTitle)
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

            Button {
                requestLeave()
            } label: {
                Text("Continue later")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel("Continue later")
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

    // MARK: - Steps

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Program", icon: .clipboard)

            sandowField("Plan title", text: $title, prompt: "e.g. 4-day strength block")
            sandowField("Focus (optional)", text: $focus, prompt: "Hypertrophy · posterior chain")

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
            }

            sandowField(
                "Coach notes (optional)",
                text: $notes,
                prompt: "How this week should feel, deload rules…",
                axis: .vertical
            )

            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tipRow("Add a plan title to continue.")
            }
        }
        .padding(18)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                        SessionEditor(day: day, draft: binding) {
                            pickerDay = day
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }

            if !canSave, !selectedDays.isEmpty {
                tipRow("Add at least one exercise to any day before saving.")
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
        if hasDraftProgress {
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
            sessions[day] = SessionDraft(day: day, focus: focus)
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
    }

    private func save() async {
        guard let trainer = store.currentTrainer else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        let planDays = selectedDays.compactMap { sessions[$0]?.asPlanDay() }
        let flat = planDays.flatMap(\.exercises)
        do {
            try await store.createPlan(
                WorkoutPlan(
                    id: UUID().uuidString,
                    trainerId: trainer.id,
                    title: title,
                    focus: focus,
                    durationMinutes: planDays.map(\.durationMinutes).max() ?? 45,
                    level: level,
                    daysPerWeek: planDays.count,
                    exercises: flat,
                    notes: notes.isEmpty ? nil : notes,
                    days: planDays
                )
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
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

    func asPlanDay() -> PlanDay {
        PlanDay(
            id: UUID().uuidString,
            weekday: day,
            startTime: time.hhmm,
            title: title.isEmpty ? "\(day.title) session" : title,
            focus: focus,
            durationMinutes: duration,
            location: location,
            warmup: warmup,
            cooldown: cooldown,
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
                    Text(day.title)
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
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
            TTSandowLabeledField(title: "Focus", prompt: "Squat pattern + hamstrings", idleFill: .white, text: $draft.focus)

            HStack(spacing: 12) {
                labeled("When") {
                    DatePicker("", selection: $draft.time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                TTDropPicker(
                    title: "Minutes",
                    selection: $draft.duration,
                    options: Array(stride(from: 20, through: 120, by: 5)),
                    format: { "\($0) min" }
                )
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
                    TTSandowLabeledField(
                        title: "How to finish (cool-down)",
                        prompt: "Cool-down",
                        axis: .vertical,
                        idleFill: .white,
                        text: $draft.cooldown
                    )
                    TTSandowLabeledField(
                        title: "How they should do this day",
                        prompt: "Pace, rest rules, form priority…",
                        axis: .vertical,
                        idleFill: .white,
                        text: $draft.coachNotes
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var exercisesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(TTFont.workSans(16, weight: .bold))

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
                    ExerciseDraftEditor(draft: $item)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        ))
                }
            }
        }
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

    private let orange = TTColor.actionOrange

    private var morph: Animation {
        .spring(response: 0.32, dampingFraction: 0.88)
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
                            Text(draft.prescriptionSummary)
                                .font(TTFont.caption(11))
                                .foregroundStyle(TTColor.inkMuted)
                                .lineLimit(1)
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
                        TTDropPicker(title: "Sets", selection: $draft.sets, options: Array(1...8))
                            .onChange(of: draft.sets) { _, _ in draft.syncSetCount() }
                        TTDropPicker(
                            title: "Reps",
                            selection: $draft.reps,
                            options: Array(1...30),
                            format: { "\($0)" }
                        )
                        .onChange(of: draft.reps) { _, value in
                            for index in draft.setRows.indices { draft.setRows[index].reps = value }
                        }
                        TTDropPicker(
                            title: "Rest",
                            selection: $draft.rest,
                            options: [20, 30, 45, 60, 75, 90, 120, 150, 180, 210, 240],
                            format: { "\($0)s" }
                        )
                    }

                    TTDropPicker(
                        title: "Working weight",
                        selection: $draft.weight,
                        options: PlanPickValues.weights,
                        format: { "\($0.cleanKg) kg" }
                    )
                    .onChange(of: draft.weight) { _, value in
                        for index in draft.setRows.indices { draft.setRows[index].weight = value }
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
                                    options: Array(1...30),
                                    format: { "\($0) reps" }
                                )
                                TTDropPicker(
                                    selection: $row.weight,
                                    options: PlanPickValues.weights,
                                    format: { "\($0.cleanKg) kg" }
                                )
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TTDropPicker(
                            title: "Tempo",
                            selection: $draft.tempo,
                            options: ["3-1-1-0", "2-0-2-0", "3-0-1-0", "4-1-1-0", "2-1-1-0", "1-0-X-0", "Explosive"]
                        )
                        TTDropPicker(
                            title: "RPE",
                            selection: $draft.rpe,
                            options: PlanPickValues.rpe,
                            format: { String(format: "%g", $0) }
                        )
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
                            .ttInputChrome(
                                focused: howToFocused,
                                cornerRadius: 12,
                                idleFill: Color(white: 0.97)
                            )
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

enum PlanPickValues {
    static let weights: [Double] = stride(from: 0.0, through: 220.0, by: 2.5).map { $0 }
    static let rpe: [Double] = stride(from: 5.0, through: 10.0, by: 0.5).map { $0 }
}

extension Date {
    var hhmm: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

#Preview("Create Plan") {
    CreatePlanView()
        .ttPreviewTrainer()
}
