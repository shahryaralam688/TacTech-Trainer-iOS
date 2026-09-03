import SwiftUI

// MARK: - Preview helpers
//
// Open any screen file in Xcode and use the Canvas (⌥⌘↩) to edit visually.
// Prefer named previews: Trainee / Trainer where both roles matter.

enum TTPreview {
    @MainActor
    static var traineeStore: AppStore { .preview(role: .trainee) }

    @MainActor
    static var trainerStore: AppStore { .preview(role: .trainer) }

    @MainActor
    static var sampleTrainee: TraineeProfile {
        traineeStore.trainees[0]
    }

    @MainActor
    static var samplePlan: WorkoutPlan {
        traineeStore.plans[0]
    }
}

extension View {
    /// Injects a seeded trainee session for Canvas previews.
    func ttPreviewTrainee() -> some View {
        environment(AppStore.preview(role: .trainee))
    }

    /// Injects a seeded trainer session for Canvas previews.
    func ttPreviewTrainer() -> some View {
        environment(AppStore.preview(role: .trainer))
    }
}
