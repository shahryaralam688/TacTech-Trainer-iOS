import SwiftUI

/// After picking an exercise from the library — previous templates + customize (Sandow theme).
struct ExerciseTemplatePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let onSelect: (ExerciseDraft) -> Void

    @State private var customizeDraft: ExerciseDraft?
    @State private var saveAsTemplate = true
    @State private var templateName = "My template"

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange

    private var previous: [ExerciseTemplate] {
        store.templates(forExerciseId: exercise.id)
    }

    private var starter: ExerciseTemplate? {
        guard let trainerId = store.currentTrainer?.id else { return nil }
        return ExerciseTemplate.starter(for: exercise, trainerId: trainerId)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TTBackButton(style: .onLight) { dismiss() }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Templates")
                        .font(TTFont.workSans(20, weight: .bold))
                    Text(exercise.name)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(Color.white)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard

                    if previous.isEmpty {
                        emptyTemplates
                    } else {
                        sectionTitle("Previous templates")
                        ForEach(previous) { template in
                            templateCard(template)
                        }
                    }

                    if let starter, previous.allSatisfy({ $0.fingerprint != starter.fingerprint }) {
                        sectionTitle("Starter")
                        templateCard(starter)
                    }

                    Button {
                        let base = previous.first ?? starter
                        var draft = base.map(ExerciseDraft.init(template:)) ?? ExerciseDraft(exerciseId: exercise.id)
                        draft.exerciseId = exercise.id
                        templateName = "Custom \(exercise.name)"
                        saveAsTemplate = true
                        customizeDraft = draft
                    } label: {
                        HStack(spacing: 10) {
                            TTIcon(icon: .sliderLineThreeHorizontal, filled: true, size: 16)
                            Text("Customize new template")
                                .font(TTFont.workSans(15, weight: .semibold))
                            Spacer()
                            TTIcon(icon: .chevronRight, size: 14)
                        }
                        .foregroundStyle(TTColor.ink)
                        .padding(16)
                        .background(cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(TTSearchPressStyle(scale: 0.99))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .sheet(item: $customizeDraft) { draft in
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

    private var heroCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(orange.opacity(0.12))
                TTIcon(icon: .kettlebell, filled: true, size: 22)
                    .foregroundStyle(orange)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text("\(exercise.muscleGroup) · \(exercise.equipment) · \(exercise.difficulty)")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyTemplates: some View {
        VStack(spacing: 10) {
            TTIcon(icon: .layerThree, filled: true, size: 28)
                .foregroundStyle(orange)
            Text("No saved templates yet")
                .font(TTFont.workSans(15, weight: .bold))
            Text("Use a starter, or customize and save for next time.")
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(TTFont.workSans(14, weight: .bold))
            .foregroundStyle(TTColor.inkMuted)
            .padding(.top, 4)
    }

    private func templateCard(_ template: ExerciseTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(TTFont.workSans(15, weight: .bold))
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

            HStack(spacing: 10) {
                Button {
                    templateName = template.name
                    saveAsTemplate = true
                    customizeDraft = ExerciseDraft(template: template)
                } label: {
                    Text("Customize")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.98))

                Button {
                    commit(ExerciseDraft(template: template), name: template.name, persist: true)
                } label: {
                    Text("Use")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.98))
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func commit(_ draft: ExerciseDraft, name: String, persist: Bool) {
        var finished = draft
        finished.templateName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Custom template"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        finished.isExpanded = true
        if persist, let trainerId = store.currentTrainer?.id {
            store.saveExerciseTemplate(finished.asTemplate(name: finished.templateName, trainerId: trainerId))
        }
        onSelect(finished)
    }
}

struct ExerciseTemplateCustomizeView: View {
    let exercise: Exercise
    @State var draft: ExerciseDraft
    @Binding var templateName: String
    @Binding var saveAsTemplate: Bool
    let onDone: (ExerciseDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TTBackButton(style: .onLight) { dismiss() }
                Text(exercise.name)
                    .font(TTFont.workSans(18, weight: .bold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(Color.white)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TEMPLATE NAME")
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkMuted)
                        TextField("e.g. Strength 5×5", text: $templateName)
                            .font(TTFont.body(16))
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Toggle(isOn: $saveAsTemplate) {
                        Text("Save for next time")
                            .font(TTFont.workSans(15, weight: .semibold))
                    }
                    .tint(orange)
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    ExerciseDraftEditor(draft: $draft)

                    Button {
                        onDone(draft)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Add to plan")
                                .font(TTFont.workSans(16, weight: .bold))
                            TTIcon(icon: .plus, filled: true, size: 14)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(TTSearchPressStyle(scale: 0.98))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }
}

extension ExerciseDraft {
    init(template: ExerciseTemplate) {
        self.init(exerciseId: template.exerciseId, templateName: template.name)
        id = UUID()
        exerciseId = template.exerciseId
        templateName = template.name
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
        isExpanded = true
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
