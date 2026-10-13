import SwiftUI

/// Full-screen Form Studio 3D Mixamo demo for a single mapped exercise.
struct FormStudioDemoView: View {
    let exerciseName: String
    let formStudioId: String

    @Environment(\.dismiss) private var dismiss

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    var body: some View {
        ZStack(alignment: .top) {
            FormStudioWebView(
                formStudioExerciseId: formStudioId,
                onClose: { dismiss() }
            )
            .ignoresSafeArea()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("3D Form Demo")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(exerciseName)
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close 3D form demonstration")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(
                LinearGradient(
                    colors: [charcoal.opacity(0.92), charcoal.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
        }
        .background(charcoal.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .statusBarHidden(false)
    }
}

#Preview("Form Studio Demo") {
    FormStudioDemoView(exerciseName: "Push-Ups", formStudioId: "push_up")
}
