import SwiftUI

struct FitnessAssessmentFlowView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var draft = FitnessAssessment()
    @State private var isSaving = false
    @State private var error: String?
    @State private var avatarSelection = TTAvatarCatalog.default

    private let total = 23
    /// Handoff screen shown right after the 8 essential questions.
    private let allSetIndex = 8

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                // ── Essentials ──────────────────────────────
                case 0: GoalStep(draft: $draft)
                case 1: AgeStep(draft: $draft)
                case 2: HeightStep(draft: $draft)
                case 3: WeightStep(draft: $draft)
                case 4: ExperienceLevelStep(draft: $draft)
                case 5: WorkoutLocationStep(draft: $draft)
                case 6: DaysStep(draft: $draft)
                case 7: WorkoutDurationStep(draft: $draft)
                // ── Handoff ─────────────────────────────────
                case 8: AllSetStep(
                    draft: $draft,
                    isSaving: isSaving,
                    onCreatePlan: { Task { await save() } },
                    onAddDetails: { withAnimation(.easeInOut(duration: 0.25)) { step = 9 } }
                )
                // ── Optional ────────────────────────────────
                case 9: GenderStep(draft: $draft)
                case 10: ActivityLevelStep(draft: $draft)
                case 11: TargetWeightStep(draft: $draft)
                case 12: EquipmentStep(draft: $draft)
                case 13: ExercisePrefStep(draft: $draft)
                case 14: LimitationsStep(draft: $draft)
                case 15: DietStep(draft: $draft)
                case 16: SupplementYesNoStep(draft: $draft)
                case 17: SupplementPickStep(draft: $draft)
                case 18: SleepStep(draft: $draft)
                case 19: WaterStep(draft: $draft)
                case 20: ProgressPhotosStep(draft: $draft)
                case 21: TextAnalysisStep(draft: $draft)
                default: AssessmentAvatarStep(
                    selection: $avatarSelection,
                    userId: store.currentUser?.id,
                    remoteAvatarUrl: store.remoteAvatarURL
                )
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error {
                Text(error)
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.danger)
                    .padding(.horizontal, 24)
            }

            // The handoff screen supplies its own buttons.
            if step != allSetIndex {
                footer
            }
        }
        .background(AssessmentColor.white.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
        .onAppear {
            if let saved = TTAvatarCatalog.saved(for: store.currentUser?.id) {
                avatarSelection = saved
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Text("Assessment")
                    .font(TTFont.workSans(17, weight: .bold))
                    .foregroundStyle(AssessmentColor.ink)

                HStack {
                    if step > 0 {
                        TTBackButton { goBack() }
                    } else {
                        Color.clear.frame(width: TTBackButton.size, height: TTBackButton.size)
                    }
                    Spacer()
                    if isOptional(step) {
                        Text("Optional")
                            .font(TTFont.workSans(12, weight: .semibold))
                            .foregroundStyle(AssessmentColor.slate)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AssessmentColor.surface)
                            .clipShape(Capsule())
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AssessmentColor.blueSoft)
                        .frame(height: 4)
                    Capsule()
                        .fill(AssessmentColor.blue)
                        .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(total), height: 4)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, TTSpace.screen)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - Footer (primary CTA + optional skip)

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().tint(.white) }
                    Text(ctaTitle)
                        .font(TTFont.workSans(17, weight: .semibold))
                    Image("OnboardingArrowRight")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                .foregroundStyle(AssessmentColor.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canContinue ? AssessmentColor.ink : AssessmentColor.ink.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .disabled(!canContinue || isSaving)

            if isOptional(step) {
                Button(action: skipCurrent) {
                    Text("Skip for Now")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(AssessmentColor.slate)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var ctaTitle: String {
        step == total - 1 ? "Finish" : "Continue"
    }

    // MARK: - Step classification

    /// Steps after the handoff screen (excluding the final avatar step, which
    /// carries its own skip control) are optional and skippable.
    private func isOptional(_ step: Int) -> Bool {
        step > allSetIndex && step < total - 1
    }

    private var wantsSupplementDetail: Bool {
        draft.supplementFrequency == "Yes" || draft.supplementFrequency == "Sometimes"
    }

    private var canContinue: Bool {
        switch step {
        case 0: !draft.goal.isEmpty
        case 4: !draft.experienceLevel.isEmpty
        case 5: !draft.workoutLocation.isEmpty
        case 7: !draft.workoutDuration.isEmpty
        default: true          // age/height/weight/days + all optional steps
        }
    }

    // MARK: - Navigation

    private func goBack() {
        // Skip over the supplement picker when it isn't relevant.
        if step == 18, !wantsSupplementDetail {
            step = 16
            return
        }
        step -= 1
    }

    private func advance() {
        // Supplement picker only applies to Yes / Sometimes.
        if step == 16, !wantsSupplementDetail {
            draft.supplements = []
            step = 18
            return
        }
        if step < total - 1 {
            step += 1
            return
        }
        Task { await save() }
    }

    /// Clears the current optional answer, then advances.
    private func skipCurrent() {
        switch step {
        case 9: draft.gender = ""
        case 10: draft.activityLevel = ""
        case 11: draft.hasTargetWeight = nil
        case 12: draft.equipment = []
        case 13: draft.exercisePreferences = []
        case 14: draft.limitations = []
        case 15: draft.diet = ""
        case 16:
            draft.supplementFrequency = ""
            draft.takesSupplements = nil
            draft.supplements = []
        case 17: draft.supplements = []
        case 18:
            draft.sleepHours = ""
            draft.sleepQuality = ""
        case 19: draft.waterIntake = ""
        case 20:
            draft.frontPhotoCaptured = false
            draft.sidePhotoCaptured = false
            draft.backPhotoCaptured = false
        case 21: draft.concerns = ""
        default: break
        }
        advance()
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            TTAvatarCatalog.persistSelection(avatarSelection, for: store.currentUser?.id)
            try await store.submitAssessment(draft)
        } catch {
            TTAvatarCatalog.persistSelection(avatarSelection, for: store.currentUser?.id)
            store.persistAssessment(draft)
            store.markAssessmentCompleted()
            self.error = error.localizedDescription
        }
    }
}

#Preview("Fitness Assessment") {
    FitnessAssessmentFlowView()
        .ttPreviewTrainee()
}
