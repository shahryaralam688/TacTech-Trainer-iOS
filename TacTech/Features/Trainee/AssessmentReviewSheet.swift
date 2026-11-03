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

    private let orange  = Color(red: 249/255, green: 115/255, blue: 22/255)
    private let amber   = Color(red: 180/255, green: 83/255,  blue: 9/255)
    private let amberBg = Color(red: 255/255, green: 247/255, blue: 237/255)

    // True when "None" is the only exercise preference selected
    private var exerciseNoneSelected: Bool {
        draft.exercisePreferences == ["None"]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // ── Open-ended context (initially empty) ─────────────────
                    concernsField
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 24)

                    Divider().padding(.horizontal, 20)

                    // ── Section 1: About You ─────────────────────────────────
                    sectionHeader("About You", icon: "person.fill")
                    VStack(spacing: 14) {
                        goalMenu        // ✅ Menu — works everywhere
                        weightField
                        ageInfoRow      // read-only — age is set once in onboarding
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    Divider().padding(.horizontal, 20)

                    // ── Section 2: Your Fitness ──────────────────────────────
                    sectionHeader("Your Fitness", icon: "figure.strengthtraining.traditional")
                    VStack(spacing: 14) {
                        fitnessSlider
                        experienceToggle
                        daysPerWeekStepper
                        limitationsTags
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    Divider().padding(.horizontal, 20)

                    // ── Section 3: Preferences ───────────────────────────────
                    sectionHeader("Preferences", icon: "heart.fill")
                    VStack(spacing: 14) {
                        dietMenu        // ✅ Menu — works everywhere
                        exercisePrefTags
                        calorieField
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }

                    buttons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
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

    // MARK: - Section header

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(orange)
            Text(title)
                .font(TTFont.workSans(11, weight: .bold))
                .foregroundStyle(Color(white: 0.45))
                .textCase(.uppercase)
                .kerning(0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Concerns (top, optional)

    private var concernsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Anything we should know?")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.12))
                Spacer()
                Text("Optional")
                    .font(TTFont.workSans(11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.93))
                    .clipShape(Capsule())
            }
            TextField("Injuries, goals, anything on your mind…", text: $draft.concerns, axis: .vertical)
                .lineLimit(2...5)
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(Color(white: 0.12))
                .padding(13)
                .background(Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(white: 0.87), lineWidth: 1)
                )
        }
    }

    // MARK: - About You fields

    /// Goal uses Menu so the full row is tappable and the dropdown works correctly.
    private var goalMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Goal")
            Menu {
                ForEach(AssessmentCatalog.goals, id: \.self) { goal in
                    Button(goal) { draft.goal = goal }
                }
            } label: {
                HStack {
                    Text(draft.goal.isEmpty ? "Select your goal…" : draft.goal)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(draft.goal.isEmpty ? Color(white: 0.55) : Color(white: 0.12))
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(white: 0.87), lineWidth: 1)
                )
            }
        }
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Weight")
            HStack {
                TextField("0", value: $draft.weightKg, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .font(TTFont.workSans(16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.12))
                Spacer()
                Text("kg")
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(white: 0.87), lineWidth: 1)
            )
        }
    }

    /// Age is read-only — entered via wheel in onboarding; changing it here
    /// would silently drift the AI model's calibration without a proper re-assessment.
    private var ageInfoRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                fieldLabel("Age")
                Text("\(draft.age) years old")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(Color(white: 0.12))
            }
            Spacer()
            // Subtle lock to signal this field is intentionally fixed
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(white: 0.87), lineWidth: 1)
        )
    }

    // MARK: - Your Fitness fields

    private var fitnessSlider: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                fieldLabel("Fitness Level")
                Spacer()
                Text(fitnessLevelLabel)
                    .font(TTFont.workSans(12, weight: .bold))
                    .foregroundStyle(orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 255/255, green: 247/255, blue: 237/255))
                    .clipShape(Capsule())
            }
            Slider(value: Binding(
                get: { Double(draft.fitnessLevel) },
                set: { draft.fitnessLevel = Int($0) }
            ), in: 1...10, step: 1)
            .tint(orange)
            HStack {
                Text("Beginner")
                Spacer()
                Text("Advanced")
            }
            .font(TTFont.workSans(11, weight: .medium))
            .foregroundStyle(Color(white: 0.55))
        }
    }

    private var fitnessLevelLabel: String {
        switch draft.fitnessLevel {
        case 1...3: "Beginner"
        case 4...6: "Intermediate"
        case 7...9: "Advanced"
        default:    "Elite"
        }
    }

    private var experienceToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                fieldLabel("Gym Experience")
                Text(draft.hasExperience == true ? "Has gym experience" : "No gym experience")
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.12))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { draft.hasExperience ?? false },
                set: { draft.hasExperience = $0 }
            ))
            .labelsHidden()
            .tint(orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(white: 0.87), lineWidth: 1)
        )
    }

    private var daysPerWeekStepper: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                fieldLabel("Days per Week")
                Text("\(draft.daysPerWeek) days / week")
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.12))
            }
            Spacer()
            // Custom stepper with 44pt touch targets (Apple HIG)
            HStack(spacing: 0) {
                Button {
                    if draft.daysPerWeek > 1 { draft.daysPerWeek -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(draft.daysPerWeek > 1 ? Color(white: 0.15) : Color(white: 0.7))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Text("\(draft.daysPerWeek)")
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(orange)
                    .frame(width: 26, alignment: .center)

                Button {
                    if draft.daysPerWeek < 7 { draft.daysPerWeek += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(draft.daysPerWeek < 7 ? Color(white: 0.15) : Color(white: 0.7))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .background(Color(white: 0.91))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(white: 0.87), lineWidth: 1)
        )
    }

    private var limitationsTags: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("Physical Limitations")
                Spacer()
                Text("Select all that apply")
                    .font(TTFont.workSans(11, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
            }
            ARSFlowLayout(spacing: 8) {
                ForEach(AssessmentCatalog.limitations, id: \.self) { item in
                    limitationChip(item)
                }
            }
        }
    }

    private func limitationChip(_ item: String) -> some View {
        let isNone     = item == "None"
        let isSelected = draft.limitations.contains(item)
        let noneActive = draft.limitations.contains("None")
        // Disable real limitations when "None" is selected
        let isDisabled = !isNone && noneActive

        return Button {
            if isNone {
                // "None" is mutually exclusive
                draft.limitations = isSelected ? [] : ["None"]
            } else {
                // Remove "None" when picking a real limitation
                draft.limitations.removeAll { $0 == "None" }
                if isSelected {
                    draft.limitations.removeAll { $0 == item }
                } else {
                    draft.limitations.append(item)
                }
            }
        } label: {
            Text(item)
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(
                    isDisabled  ? Color(white: 0.75) :
                    isSelected  ? amber              : Color(white: 0.3)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isDisabled  ? Color(white: 0.96) :
                    isSelected  ? amberBg            : Color(white: 0.93)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected && !isDisabled ? amber.opacity(0.45) : Color.clear, lineWidth: 1.5)
                )
                .clipShape(Capsule())
                .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Preferences fields

    private var dietMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Diet Preference")
            Menu {
                ForEach(AssessmentCatalog.diets, id: \.self) { diet in
                    Button(diet) { draft.diet = diet }
                }
            } label: {
                HStack {
                    Text(draft.diet.isEmpty ? "Select your diet…" : draft.diet)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(draft.diet.isEmpty ? Color(white: 0.55) : Color(white: 0.12))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(white: 0.87), lineWidth: 1)
                )
            }
        }
    }

    private var exercisePrefTags: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("Exercise Preferences")
                Spacer()
                if exerciseNoneSelected {
                    Text("No preference set")
                        .font(TTFont.workSans(11, weight: .medium))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            ARSFlowLayout(spacing: 8) {
                ForEach(AssessmentCatalog.exercises, id: \.self) { item in
                    exerciseChip(item)
                }
            }
        }
    }

    private func exerciseChip(_ item: String) -> some View {
        let isNone     = item == "None"
        let isSelected = draft.exercisePreferences.contains(item)
        // When "None" is active, disable all other chips
        let isDisabled = !isNone && exerciseNoneSelected

        return Button {
            if isNone {
                draft.exercisePreferences = isSelected ? [] : ["None"]
            } else {
                draft.exercisePreferences.removeAll { $0 == "None" }
                if isSelected {
                    draft.exercisePreferences.removeAll { $0 == item }
                } else {
                    draft.exercisePreferences.append(item)
                }
            }
        } label: {
            Text(item)
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(
                    isDisabled ? Color(white: 0.75) :
                    isSelected ? .white              : Color(white: 0.3)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    isDisabled ? Color(white: 0.96) :
                    isSelected ? Color.black         : Color(white: 0.93)
                )
                .clipShape(Capsule())
                .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var calorieField: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                fieldLabel("Daily Calorie Goal")
                Text("Adjust your target intake")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
            }
            Spacer()
            HStack(spacing: 4) {
                TextField("0", value: $draft.calorieGoal, format: .number)
                    .keyboardType(.numberPad)
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(Color(white: 0.12))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 68)
                Text("kcal")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(white: 0.87), lineWidth: 1)
        )
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: 16) {
            Button {
                Task { await generateWithUpdate() }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(isGenerating ? "Generating…" : "Update & Generate Plan")
                        .font(TTFont.workSans(17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isGenerating ? Color.black.opacity(0.45) : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(isGenerating)

            Button {
                Task { await generateWithCurrent() }
            } label: {
                Text("Skip update, generate with current data")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
                    .underline()
            }
            .disabled(isGenerating)
        }
    }

    // MARK: - Actions

    @MainActor private func generateWithUpdate() async {
        isGenerating = true; errorMessage = nil
        defer { isGenerating = false }
        do {
            try await store.submitAssessment(draft)
            _ = try await store.generateAIProgram(horizonDays: 7)
            dismiss(); onGenerated()
        } catch let e as AppError where e.isAIRequired {
            dismiss(); _ = store.presentAIPaywallIfNeeded(for: e)
        } catch let e as AppError where e.isConflict { errorMessage = e.localizedDescription
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func generateWithCurrent() async {
        isGenerating = true; errorMessage = nil
        defer { isGenerating = false }
        do {
            _ = try await store.generateAIProgram(horizonDays: 7)
            dismiss(); onGenerated()
        } catch let e as AppError where e.isAIRequired {
            dismiss(); _ = store.presentAIPaywallIfNeeded(for: e)
        } catch let e as AppError where e.isConflict { errorMessage = e.localizedDescription
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Style helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(TTFont.workSans(11, weight: .bold))
            .foregroundStyle(Color(white: 0.5))
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

// MARK: - Flow layout

private struct ARSFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (i, sub) in subviews.enumerated() {
            sub.place(at: CGPoint(x: bounds.minX + result.positions[i].x,
                                  y: bounds.minY + result.positions[i].y),
                       proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return (positions, CGSize(width: maxW, height: y + rowH))
    }
}
