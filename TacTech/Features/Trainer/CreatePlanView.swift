import SwiftUI

struct CreatePlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var focus = ""
    @State private var level = "Intermediate"
    @State private var notes = ""
    @State private var selectedDays: [Weekday] = []
    @State private var sessions: [Weekday: SessionDraft] = [:]
    @State private var pickerDay: Weekday?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    planHeader
                    dayPicker
                    ForEach(selectedDays, id: \.self) { day in
                        if let binding = binding(for: day) {
                            SessionEditor(day: day, draft: binding) {
                                pickerDay = day
                            }
                        }
                    }
                    if let error {
                        Text(error)
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.danger)
                    }
                    TTButton(title: "Save detailed plan", icon: "checkmark", isLoading: isSaving) {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .sheet(item: $pickerDay) { day in
                ExerciseLibrarySheet { exercise in
                    add(exercise, to: day)
                }
            }
        }
    }

    private var planHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Program")
                .font(TTFont.title(20))
            field("Plan title", text: $title, prompt: "e.g. 4-day strength block")
            field("Focus", text: $focus, prompt: "Hypertrophy · posterior chain")
            VStack(alignment: .leading, spacing: 8) {
                Text("LEVEL")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkMuted)
                Picker("Level", selection: $level) {
                    ForEach(["Beginner", "Intermediate", "Advanced"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
            }
            field("Coach notes for the trainee", text: $notes, prompt: "How this week should feel, deload rules, food timing…", axis: .vertical)
        }
        .ttCard()
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which days will they train?")
                .font(TTFont.title(20))
            Text("Pick every training day, then set the time, how to do the session, and the exact weight for each set.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    let on = selectedDays.contains(day)
                    Button {
                        toggle(day)
                    } label: {
                        Text(day.short)
                            .font(TTFont.heading(13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(on ? TTColor.surface : TTColor.ink)
                            .background(on ? TTColor.brand : TTColor.surfaceAlt)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .ttCard()
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(TTColor.inkSubtle), axis: axis)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .font(TTFont.body(16))
                .padding(12)
                .background(TTColor.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

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

    private func add(_ exercise: Exercise, to day: Weekday) {
        sessions[day, default: SessionDraft(day: day, focus: focus)].exercises.append(ExerciseDraft(exerciseId: exercise.id))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedDays.contains { !(sessions[$0]?.exercises.isEmpty ?? true) }
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
    var sets = 4
    var reps = 8
    var rest = 90
    var weight = 40.0
    var tempo = "3-1-1-0"
    var rpe = 7.5
    var howTo = "Brace, control the eccentric, full lockout, no bouncing."
    var side = "Both"
    var setRows: [SetDraft]

    init(exerciseId: String) {
        self.exerciseId = exerciseId
        self.setRows = (1...4).map { SetDraft(setNumber: $0, reps: 8, weight: 40) }
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

struct SessionEditor: View {
    let day: Weekday
    @Binding var draft: SessionDraft
    var addExercise: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(day.title)
                .font(TTFont.title(20))
            labeled("Session name") {
                TextField("Lower strength", text: $draft.title)
            }
            labeled("Focus") {
                TextField("Squat pattern + hamstrings", text: $draft.focus)
            }
            HStack(spacing: 12) {
                labeled("When") {
                    DatePicker("", selection: $draft.time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                labeled("Minutes") {
                    Stepper("\(draft.duration)", value: $draft.duration, in: 20...120, step: 5)
                }
            }
            labeled("Where") {
                Picker("Location", selection: $draft.location) {
                    ForEach(["Gym", "Home", "Outdoor", "Studio"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
            }
            labeled("How to start (warm-up)") {
                TextField("Warm-up", text: $draft.warmup, axis: .vertical)
                    .lineLimit(2...4)
            }
            labeled("How to finish (cool-down)") {
                TextField("Cool-down", text: $draft.cooldown, axis: .vertical)
                    .lineLimit(2...4)
            }
            labeled("How they should do this day") {
                TextField("Pace, rest rules, form priority…", text: $draft.coachNotes, axis: .vertical)
                    .lineLimit(2...5)
            }

            HStack {
                Text("Exercises")
                    .font(TTFont.heading(16))
                Spacer()
                Button("Add", action: addExercise)
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.brand)
            }

            ForEach($draft.exercises) { $item in
                ExerciseDraftEditor(draft: $item)
            }
        }
        .ttCard()
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
            content()
                .padding(10)
                .background(TTColor.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct ExerciseDraftEditor: View {
    @Environment(AppStore.self) private var store
    @Binding var draft: ExerciseDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.exercise(id: draft.exerciseId)?.name ?? "Exercise")
                .font(TTFont.heading(16))
            Text(store.exercise(id: draft.exerciseId).map { "\($0.muscleGroup) · \($0.equipment)" } ?? "")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)

            HStack {
                stepper("Sets", value: $draft.sets, range: 1...8)
                    .onChange(of: draft.sets) { _, _ in draft.syncSetCount() }
                stepper("Reps", value: $draft.reps, range: 3...20)
                    .onChange(of: draft.reps) { _, value in
                        for index in draft.setRows.indices { draft.setRows[index].reps = value }
                    }
                stepper("Rest s", value: $draft.rest, range: 20...240, step: 15)
            }

            labeled("Working weight (kg)") {
                HStack {
                    Slider(value: $draft.weight, in: 0...200, step: 2.5)
                    Text("\(draft.weight.cleanKg)")
                        .font(TTFont.heading(14))
                        .frame(width: 48, alignment: .trailing)
                }
                .onChange(of: draft.weight) { _, value in
                    for index in draft.setRows.indices { draft.setRows[index].weight = value }
                }
            }

            ForEach($draft.setRows) { $row in
                HStack {
                    Text("Set \(row.setNumber)")
                        .font(TTFont.heading(13))
                        .frame(width: 52, alignment: .leading)
                    Stepper("\(row.reps) reps", value: $row.reps, in: 1...30)
                    Stepper("\(row.weight.cleanKg) kg", value: $row.weight, in: 0...220, step: 2.5)
                }
                .font(TTFont.caption(13))
            }

            labeled("Tempo") { TextField("3-1-1-0", text: $draft.tempo) }
            labeled("RPE") {
                HStack {
                    Slider(value: $draft.rpe, in: 5...10, step: 0.5)
                    Text(String(format: "%.1f", draft.rpe))
                        .font(TTFont.heading(14))
                }
            }
            labeled("How to perform") {
                TextField("Cues, depth, grip, breathing…", text: $draft.howTo, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .padding(12)
        .background(TTColor.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(TTFont.caption(10))
                .foregroundStyle(TTColor.inkSubtle)
            Stepper("\(value.wrappedValue)", value: value, in: range, step: step)
                .font(TTFont.caption(13))
        }
        .frame(maxWidth: .infinity)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(TTFont.caption(10))
                .foregroundStyle(TTColor.inkSubtle)
            content()
        }
    }
}

struct ExerciseLibrarySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            List(store.exercises) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(TTFont.heading(16))
                            .foregroundStyle(TTColor.ink)
                        Text("\(exercise.muscleGroup) · \(exercise.equipment) · \(exercise.difficulty)")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }
}

extension Date {
    var hhmm: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
