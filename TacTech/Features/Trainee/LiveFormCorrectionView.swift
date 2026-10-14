import SwiftUI

// MARK: - Live Form (Sandow / TacTech system design)

struct LiveFormCorrectionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var analyzer = PoseAnalyzer()
    var initialExerciseId: String?
    @State private var exerciseId = "ex-squat"
    @State private var didSave = false

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let panelFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = TTColor.actionOrange

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                CameraPreview(session: analyzer.session)
                    .background(Color.black)

                skeleton

                if !analyzer.cameraAuthorized {
                    permissionOverlay
                }

                topChrome
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomPanel
        }
        .background(charcoal.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .overlay(alignment: .top) {
            if let notice = store.planChangeNotice {
                Text(notice)
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(.top, 58)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            store.beginTraineeSessionUI()
            if let initialExerciseId { exerciseId = initialExerciseId }
            analyzer.exerciseId = exerciseId
            analyzer.start()
        }
        .onDisappear {
            analyzer.stop()
            store.endTraineeSessionUI()
        }
    }

    // MARK: - Top chrome

    private var topChrome: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                TTIcon(icon: .chevronLeft, size: 16)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Live form")
                .font(TTFont.workSans(18, weight: .bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.screen)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Menu {
                ForEach(store.exercises) { exercise in
                    Button(exercise.name) {
                        exerciseId = exercise.id
                        analyzer.exerciseId = exercise.id
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedExerciseName)
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(orange)
                        .lineLimit(1)
                    TTIcon(icon: .chevronUpDown, size: 14)
                        .foregroundStyle(orange)
                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(analyzer.feedback.cue)
                        .font(TTFont.workSans(20, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("Live AI estimate · compare against trainer cues")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }

                Spacer(minLength: 8)

                VStack(spacing: 2) {
                    Text("\(analyzer.feedback.score)")
                        .font(TTFont.workSans(28, weight: .bold))
                        .foregroundStyle(orange)
                    Text("score")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    TTIcon(icon: .kettlebell, filled: true, size: 14)
                        .foregroundStyle(orange)
                    Text("Reps \(analyzer.feedback.repCount)")
                        .font(TTFont.workSans(15, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                }

                Spacer(minLength: 8)

                Button {
                    saveForTrainer()
                } label: {
                    HStack(spacing: 8) {
                        TTIcon(
                            icon: didSave ? .check : .cloudUpload1,
                            filled: true,
                            size: 14
                        )
                        Text(didSave ? "Saved" : "Save for trainer")
                            .font(TTFont.workSans(14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(didSave ? TTColor.success : orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(didSave)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelFill)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: TTSheetChrome.pageTopRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: TTSheetChrome.pageTopRadius,
                style: .continuous
            )
        )
    }

    private var selectedExerciseName: String {
        store.exercise(id: exerciseId)?.name ?? "Exercise"
    }

    private func saveForTrainer() {
        guard let trainee = store.currentTrainee else { return }
        let snap = analyzer.snapshotReport()
        Task {
            try? await store.saveFormReport(
                FormReport(
                    id: UUID().uuidString,
                    traineeId: trainee.id,
                    exerciseId: exerciseId,
                    createdAt: .now,
                    score: snap.score,
                    cues: snap.cues,
                    repCount: snap.reps
                )
            )
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                didSave = true
            }
        }
    }

    // MARK: - Overlays

    private var skeleton: some View {
        GeometryReader { geo in
            ForEach(Array(analyzer.feedback.joints.enumerated()), id: \.offset) { _, joint in
                Circle()
                    .fill(orange)
                    .frame(width: 8, height: 8)
                    .position(x: joint.x * geo.size.width, y: joint.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(orange.opacity(0.12))
                    .frame(width: 56, height: 56)
                TTIcon(icon: .camera1, filled: true, size: 22)
                    .foregroundStyle(orange)
            }

            Text("Camera access needed")
                .font(TTFont.workSans(18, weight: .bold))
                .foregroundStyle(TTColor.ink)

            Text("Enable the camera to run live form correction.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)

            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Open Settings")
                        .font(TTFont.workSans(14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(panelFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Live Form") {
    NavigationStack {
        LiveFormCorrectionView(initialExerciseId: "ex-squat")
            .ttPreviewTrainee()
    }
}
