import SwiftUI

struct LiveFormCorrectionView: View {
    @Environment(AppStore.self) private var store
    @StateObject private var analyzer = PoseAnalyzer()
    var initialExerciseId: String?
    @State private var exerciseId = "ex-squat"

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreview(session: analyzer.session)
                    .ignoresSafeArea(edges: .top)
                skeleton
                if !analyzer.cameraAuthorized {
                    permissionOverlay
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Picker("Exercise", selection: $exerciseId) {
                    ForEach(store.exercises) { exercise in
                        Text(exercise.name).tag(exercise.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: exerciseId) { _, value in
                    analyzer.exerciseId = value
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(analyzer.feedback.cue)
                            .font(TTFont.title(20))
                        Text("Live AI estimate · compare against trainer cues")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer()
                    VStack {
                        Text("\(analyzer.feedback.score)")
                            .font(TTFont.display(28))
                            .foregroundStyle(TTColor.brand)
                        Text("score")
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }

                HStack {
                    Text("Reps \(analyzer.feedback.repCount)")
                        .font(TTFont.heading(15))
                    Spacer()
                    Button("Save for trainer") {
                        guard let trainee = store.currentTrainee else { return }
                        let snap = analyzer.snapshotReport()
                        store.saveFormReport(
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
                    }
                    .font(TTFont.heading(14))
                    .foregroundStyle(TTColor.brand)
                }
            }
            .padding(20)
            .background(TTColor.canvas)
        }
        .navigationTitle("Live form")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let initialExerciseId { exerciseId = initialExerciseId }
            analyzer.exerciseId = exerciseId
            analyzer.start()
        }
        .onDisappear { analyzer.stop() }
    }

    private var skeleton: some View {
        GeometryReader { geo in
            ForEach(Array(analyzer.feedback.joints.enumerated()), id: \.offset) { _, joint in
                Circle()
                    .fill(TTColor.energy)
                    .frame(width: 8, height: 8)
                    .position(x: joint.x * geo.size.width, y: joint.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }

    private var permissionOverlay: some View {
        VStack(spacing: 12) {
            Text("Camera access needed")
                .font(TTFont.title(20))
            Text("Enable the camera to run live form correction.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding()
    }
}
