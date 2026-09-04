import SwiftUI

/// After picking an exercise from the library — show previous templates + customize.
struct ExerciseTemplatePickerView: View {
    @Environment(AppStore.self) private var store
    let exercise: Exercise
    let onSelect: (ExerciseDraft) -> Void

    @State private var customizeDraft: ExerciseDraft?
    @State private var saveAsTemplate = true
    @State private var templateName = "My template"

    private var previous: [ExerciseTemplate] {
        store.templates(forExerciseId: exercise.id)
    }

    private var starter: ExerciseTemplate? {
        guard let trainerId = store.currentTrainer?.id else { return nil }
        return ExerciseTemplate.starter(for: exercise, trainerId: trainerId)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name)
                        .font(TTFont.title(20))
                        .foregroundStyle(TTColor.ink)
                    Text("\(exercise.muscleGroup) · \(exercise.equipment) · \(exercise.difficulty)")
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.inkMuted)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            if previous.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No saved templates yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Use a starter, or customize and save for next time.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section("Previous templates") {
                    ForEach(previous) { template in
                        templateRow(template)
                    }
                }
            }

            if let starter, previous.allSatisfy({ $0.fingerprint != starter.fingerprint }) {
                Section("Starter") {
                    templateRow(starter)
                }
            }

            Section {
                Button {
                    let base = previous.first ?? starter
                    var draft = base.map(ExerciseDraft.init(template:)) ?? ExerciseDraft(exerciseId: exercise.id)
                    draft.exerciseId = exercise.id
                    templateName = "Custom \(exercise.name)"
                    saveAsTemplate = true
                    customizeDraft = draft
                } label: {
                    Label("Customize new template", systemImage: "slider.horizontal.3")
                        .font(TTFont.heading(16))
                }
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $customizeDraft) { draft in
            NavigationStack {
                ExerciseTemplateCustomizeView(
                    exercise: exercise,
                    draft: draft,
                    templateName: $templateName,
                    saveAsTemplate: $saveAsTemplate
                ) { finished in
                    commit(finished, name: templateName, persist: saveAsTemplate)
                }
            }
        }
    }

    private func templateRow(_ template: ExerciseTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                    Text(template.summary)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                    if !template.howTo.isEmpty {
                        Text(template.howTo)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkSubtle)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Button("Use") {
                    commit(ExerciseDraft(template: template), name: template.name, persist: true)
                }
                .font(TTFont.caption(13))
                .buttonStyle(.borderedProminent)
                .tint(TTColor.brand)
            }

            Button {
                templateName = template.name
                saveAsTemplate = true
                customizeDraft = ExerciseDraft(template: template)
            } label: {
                Text("Customize")
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.brand)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func commit(_ draft: ExerciseDraft, name: String, persist: Bool) {
        if persist, let trainerId = store.currentTrainer?.id {
            store.saveExerciseTemplate(draft.asTemplate(name: name, trainerId: trainerId))
        }
        onSelect(draft)
    }
}

struct ExerciseTemplateCustomizeView: View {
    let exercise: Exercise
    @State var draft: ExerciseDraft
    @Binding var templateName: String
    @Binding var saveAsTemplate: Bool
    let onDone: (ExerciseDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TEMPLATE NAME")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkMuted)
                    TextField("e.g. Strength 5×5", text: $templateName)
                        .font(TTFont.body(16))
                        .padding(12)
                        .background(TTColor.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Toggle("Save for next time", isOn: $saveAsTemplate)
                    .font(TTFont.body(15))

                ExerciseDraftEditor(draft: $draft)

                TTButton(title: "Add to plan", icon: "plus") {
                    onDone(draft)
                    dismiss()
                }
            }
            .padding(20)
        }
        .ttScreenBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

extension ExerciseDraft {
    init(template: ExerciseTemplate) {
        self.init(exerciseId: template.exerciseId)
        id = UUID()
        exerciseId = template.exerciseId
        sets = template.sets
        reps = template.reps
        rest = template.restSeconds
        weight = template.weightKg
        tempo = template.tempo
        rpe = template.rpe
        howTo = template.howTo
        side = template.side
        setRows = template.setRows.map {
            SetDraft(setNumber: $0.setNumber, reps: $0.reps, weight: $0.weightKg)
        }
        if setRows.isEmpty {
            syncSetCount()
        }
    }

    func asTemplate(name: String, trainerId: String) -> ExerciseTemplate {
        ExerciseTemplate(
            id: UUID().uuidString,
            exerciseId: exerciseId,
            trainerId: trainerId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My template" : name,
            sets: sets,
            reps: reps,
            restSeconds: rest,
            weightKg: weight,
            tempo: tempo,
            rpe: rpe,
            howTo: howTo,
            side: side,
            setRows: setRows.map {
                ExerciseTemplateSet(
                    id: $0.id.uuidString,
                    setNumber: $0.setNumber,
                    reps: $0.reps,
                    weightKg: $0.weight
                )
            },
            updatedAt: .now
        )
    }
}

#Preview("Templates") {
    NavigationStack {
        ExerciseTemplatePickerView(
            exercise: Exercise(
                id: "ex-1",
                name: "Back Squat",
                muscleGroup: "Quads",
                equipment: "Barbell",
                difficulty: "Intermediate",
                cues: ["Brace hard"],
                icon: "figure.strengthtraining.traditional"
            ),
            onSelect: { _ in }
        )
        .ttPreviewTrainer()
    }
}
