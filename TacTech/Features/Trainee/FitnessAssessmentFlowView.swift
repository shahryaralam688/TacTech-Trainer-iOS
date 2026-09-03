import SwiftUI

struct FitnessAssessmentFlowView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var draft = FitnessAssessment()
    @State private var isSaving = false
    @State private var error: String?

    private let total = 17

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch step {
                case 0: GoalStep(draft: $draft)
                case 1: GenderStep(draft: $draft, onSkip: skipGender)
                case 2: WeightStep(draft: $draft)
                case 3: AgeStep(draft: $draft)
                case 4: ExperienceStep(draft: $draft, onAnswer: answerExperience)
                case 5: FitnessLevelStep(draft: $draft)
                case 6: LimitationsStep(draft: $draft)
                case 7: DietStep(draft: $draft)
                case 8: DaysStep(draft: $draft)
                case 9: ExercisePrefStep(draft: $draft)
                case 10: SupplementYesNoStep(draft: $draft)
                case 11: SupplementPickStep(draft: $draft)
                case 12: CalorieStep(draft: $draft)
                case 13: SleepStep(draft: $draft)
                case 14: BodyScanStep(draft: $draft)
                case 15: VoiceStep(draft: $draft)
                default: TextAnalysisStep(draft: $draft)
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

            if step != 4 {
                Button(action: advance) {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white) }
                        Text(ctaTitle)
                            .font(.system(size: 17, weight: .semibold))
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
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                Color.clear.frame(height: 12)
            }
        }
        .background(AssessmentColor.white.ignoresSafeArea())
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }

    private var header: some View {
        ZStack {
            Text("Assessment")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AssessmentColor.ink)

            HStack {
                if step > 0 {
                    TTBackButton { step -= 1 }
                } else {
                    Color.clear.frame(width: TTBackButton.size, height: TTBackButton.size)
                }

                Spacer()

                Text("\(step + 1) of \(total)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AssessmentColor.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AssessmentColor.blueSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var ctaTitle: String {
        switch step {
        case 14: "Got it, let’s scan"
        case 16: "Finish"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: !draft.goal.isEmpty
        case 1: !draft.gender.isEmpty
        case 4: draft.hasExperience != nil
        case 6: !draft.limitations.isEmpty
        case 7: !draft.diet.isEmpty
        case 9: !draft.exercisePreferences.isEmpty
        case 10: draft.takesSupplements != nil
        case 11: draft.takesSupplements == false || !draft.supplements.isEmpty
        case 13: !draft.sleepQuality.isEmpty
        case 14: draft.bodyScanCaptured
        case 15: draft.voiceCaptured
        default: true
        }
    }

    private func skipGender() {
        draft.gender = ""
        step = 2
    }

    private func answerExperience(_ hasExperience: Bool) {
        draft.hasExperience = hasExperience
        withAnimation(.easeInOut(duration: 0.25)) {
            step = 5
        }
    }

    private func advance() {
        if step == 10, draft.takesSupplements == false {
            draft.supplements = []
            step = 12
            return
        }
        if step < total - 1 {
            step += 1
            return
        }
        Task { await save() }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await store.submitAssessment(draft)
        } catch {
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
