import SwiftUI

struct AssessmentReviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FitnessAssessment
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private let onGenerated: () -> Void

    init(assessment: FitnessAssessment?, onGenerated: @escaping () -> Void) {
        _draft = State(initialValue: assessment ?? FitnessAssessment())
        self.onGenerated = onGenerated
    }

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Review your assessment before generating a plan.")
                        .font(TTFont.workSans(14, weight: .medium))
                        .foregroundStyle(Color(white: 0.4))

                    goalPicker
                    genderPicker
                    numberField("Weight (kg)", value: $draft.weightKg)
                    ageField
                    fitnessSlider
                    experienceToggle
                    daysPerWeekStepper
                    limitationsTags
                    dietPicker
                    exercisePrefTags
                    calorieField
                    concernsField

                    if let errorMessage {
                        Text(errorMessage)
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(.red)
                    }

                    buttons
                }
                .padding(20)
            }
            .navigationTitle("Your Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Fields

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Goal")
            Picker("Goal", selection: $draft.goal) {
                Text("Select…").tag("")
                ForEach(AssessmentCatalog.goals, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(orange)
        }
    }

    private var genderPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Gender")
            Picker("Gender", selection: $draft.gender) {
                Text("Select…").tag("")
                Text("Male").tag("Male")
                Text("Female").tag("Female")
                Text("Other").tag("Other")
            }
            .pickerStyle(.menu)
            .tint(orange)
        }
    }

    private func numberField(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var ageField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Age")
            TextField("Age", value: $draft.age, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var fitnessSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Fitness Level: \(draft.fitnessLevel)")
            Slider(value: Binding(
                get: { Double(draft.fitnessLevel) },
                set: { draft.fitnessLevel = Int($0) }
            ), in: 1...10, step: 1)
            .tint(orange)
        }
    }

    private var experienceToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Gym Experience")
            HStack {
                Text("Has gym experience")
                    .font(TTFont.workSans(15, weight: .medium))
                    .foregroundStyle(Color(white: 0.2))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { draft.hasExperience ?? false },
                    set: { draft.hasExperience = $0 }
                ))
                .labelsHidden()
                .tint(orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var daysPerWeekStepper: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Days per Week")
            HStack {
                Text("Days per week")
                    .font(TTFont.workSans(15, weight: .medium))
                    .foregroundStyle(Color(white: 0.2))
                Spacer()
                Stepper("\(draft.daysPerWeek)", value: $draft.daysPerWeek, in: 1...7)
                    .font(TTFont.workSans(15, weight: .semibold))
                    .labelsHidden()
                Text("\(draft.daysPerWeek)")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(orange)
                    .frame(minWidth: 20, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var limitationsTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Limitations")
            ARSFlowLayout(spacing: 8) {
                ForEach(AssessmentCatalog.limitations, id: \.self) { item in
                    tagButton(item, selected: draft.limitations.contains(item)) {
                        if draft.limitations.contains(item) {
                            draft.limitations.removeAll { $0 == item }
                        } else {
                            draft.limitations.append(item)
                        }
                    }
                }
            }
        }
    }

    private var dietPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Diet")
            Picker("Diet", selection: $draft.diet) {
                Text("Select…").tag("")
                ForEach(AssessmentCatalog.diets, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(orange)
        }
    }

    private var exercisePrefTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Exercise Preferences")
            ARSFlowLayout(spacing: 8) {
                ForEach(AssessmentCatalog.exercises, id: \.self) { item in
                    tagButton(item, selected: draft.exercisePreferences.contains(item)) {
                        if draft.exercisePreferences.contains(item) {
                            draft.exercisePreferences.removeAll { $0 == item }
                        } else {
                            draft.exercisePreferences.append(item)
                        }
                    }
                }
            }
        }
    }

    private var calorieField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Calorie Goal")
            TextField("Calorie goal", value: $draft.calorieGoal, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var concernsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Concerns")
            TextField("Any concerns…", text: $draft.concerns, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await generateWithUpdate() }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView().tint(.white)
                    }
                    Text(isGenerating ? "Generating…" : "Update & Generate")
                        .font(TTFont.textLG(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isGenerating ? Color.black.opacity(0.45) : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(isGenerating)

            Button {
                Task { await generateWithCurrent() }
            } label: {
                Text("Generate with current")
                    .font(TTFont.textLG(.semibold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(white: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(isGenerating)
        }
    }

    // MARK: - Actions

    @MainActor
    private func generateWithUpdate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            try await store.submitAssessment(draft)
            _ = try await store.generateAIProgram(horizonDays: 7)
            dismiss()
            onGenerated()
        } catch let error as AppError where error.isAIRequired {
            dismiss()
            _ = store.presentAIPaywallIfNeeded(for: error)
        } catch let error as AppError where error.isConflict {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func generateWithCurrent() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            _ = try await store.generateAIProgram(horizonDays: 7)
            dismiss()
            onGenerated()
        } catch let error as AppError where error.isAIRequired {
            dismiss()
            _ = store.presentAIPaywallIfNeeded(for: error)
        } catch let error as AppError where error.isConflict {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(TTFont.workSans(13, weight: .bold))
            .foregroundStyle(Color(white: 0.35))
            .textCase(.uppercase)
    }

    private func tagButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(selected ? .white : Color(white: 0.3))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Color.black : Color(white: 0.93))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ARSFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, sub) in subviews.enumerated() {
            sub.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                  y: bounds.minY + result.positions[index].y),
                       proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return (positions, CGSize(width: maxW, height: y + rowH))
    }
}
