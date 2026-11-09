import SwiftUI

// MARK: - Workout Overview (session preview)

/// A single-session preview. Pushed from Home (standard nav bar + back button).
/// The guided session itself is started from the sticky bottom bar.
struct WorkoutOverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let plan: WorkoutPlan
    @State private var expandedExerciseIds: Set<String> = []

    private let canvas = Color(white: 0.97)

    private var session: PlanDay? {
        plan.session(on: Date()) ?? plan.nextSession(from: Date())
    }

    private var exercises: [WorkoutExercise] {
        session?.exercises ?? []
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if let session {
                    SessionHeader(session: session, level: plan.level)
                }

                BeforeYouStartCard(
                    equipment: equipmentList,
                    formExerciseId: exercises.first?.exerciseId
                )

                if let warmup = session?.warmup, !warmup.isEmpty {
                    BlockCard(title: "Warm-up", icon: "figure.flexibility", text: warmup)
                }

                if !exercises.isEmpty {
                    exercisesSection
                }

                if let cooldown = session?.cooldown, !cooldown.isEmpty {
                    BlockCard(title: "Cool-down", icon: "wind", text: cooldown)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)   // sticky bar adds its own inset via safeAreaInset
        }
        .background(canvas.ignoresSafeArea())
        .navigationTitle(session?.title ?? plan.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Home")
                    }
                }
                .accessibilityLabel("Back")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let session {
                StickyStartBar(summary: summaryLine, plan: plan, day: session)
            }
        }
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(TTFont.workSans(16, weight: .medium))
                .foregroundStyle(TTColor.ink)

            VStack(spacing: 10) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    ExerciseRow(
                        index: index,
                        exercise: exercise,
                        data: store.exercise(id: exercise.exerciseId),
                        isExpanded: expandedExerciseIds.contains(exercise.id),
                        onToggle: { toggle(exercise.id) }
                    )
                }
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedExerciseIds.contains(id) {
                expandedExerciseIds.remove(id)
            } else {
                expandedExerciseIds.insert(id)
            }
        }
    }

    // MARK: - Derived

    /// Unique equipment across the session's exercises (skips bodyweight / unknown).
    private var equipmentList: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for ex in exercises {
            guard let eq = store.exercise(id: ex.exerciseId)?.equipment else { continue }
            let trimmed = eq.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard !trimmed.isEmpty, lower != "bodyweight", lower != "none" else { continue }
            if seen.insert(lower).inserted { result.append(trimmed) }
        }
        return result
    }

    private var summaryLine: String {
        let totalSets = exercises.reduce(0) { $0 + $1.workingSets.count }
        let minutes = session?.durationMinutes ?? plan.durationMinutes
        return "\(exercises.count) exercises · \(totalSets) sets · \(minutes) min"
    }
}

// MARK: - Session header (meta line under the large title)

struct SessionHeader: View {
    let session: PlanDay
    let level: String

    var body: some View {
        FlowLayout(spacing: 10) {
            metaItem(icon: "clock", text: session.timeLabel)
            metaItem(icon: "timer", text: "\(session.durationMinutes) min")
            metaItem(icon: "mappin.and.ellipse", text: session.location ?? "Gym")
            Text(level.capitalized)
                .font(TTFont.workSans(12, weight: .medium))
                .foregroundStyle(OverviewTheme.textOrange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(OverviewTheme.orangeTint)
                .clipShape(Capsule())
        }
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OverviewTheme.brandOrange)
            Text(text)
                .font(TTFont.workSans(13, weight: .regular))
                .foregroundStyle(OverviewTheme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Before you start (equipment + form camera)

struct BeforeYouStartCard: View {
    let equipment: [String]
    let formExerciseId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before you start")
                .font(TTFont.workSans(16, weight: .medium))
                .foregroundStyle(TTColor.ink)

            VStack(alignment: .leading, spacing: 6) {
                Text("Equipment")
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(OverviewTheme.muted)
                if equipment.isEmpty {
                    Text("No equipment needed")
                        .font(TTFont.workSans(14, weight: .regular))
                        .foregroundStyle(TTColor.ink)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(equipment, id: \.self) { item in
                            Text(item)
                                .font(TTFont.workSans(13, weight: .medium))
                                .foregroundStyle(TTColor.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(OverviewTheme.field)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Divider()

            // Moved from the old bottom "Live Form Correction" row — same behavior (opens live form).
            NavigationLink {
                LiveFormCorrectionView(initialExerciseId: formExerciseId)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(OverviewTheme.brandOrange)
                        .frame(width: 40, height: 40)
                        .background(OverviewTheme.orangeTint)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Form camera")
                            .font(TTFont.workSans(15, weight: .medium))
                            .foregroundStyle(TTColor.ink)
                        Text("Real-time feedback on your form")
                            .font(TTFont.workSans(13, weight: .regular))
                            .foregroundStyle(OverviewTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OverviewTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the form camera")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Warm-up / Cool-down block

struct BlockCard: View {
    let title: String
    let icon: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OverviewTheme.brandOrange)
                Text(title)
                    .font(TTFont.workSans(16, weight: .medium))
                    .foregroundStyle(TTColor.ink)
            }
            Text(text)
                .font(TTFont.workSans(14, weight: .regular))
                .foregroundStyle(OverviewTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Exercise row

struct ExerciseRow: View {
    let index: Int
    let exercise: WorkoutExercise
    let data: Exercise?
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Number circle — distinct per row, never overlapping an icon.
                Text("\(index + 1)")
                    .font(TTFont.workSans(15, weight: .medium))
                    .foregroundStyle(OverviewTheme.textOrange)
                    .frame(width: 36, height: 36)
                    .background(OverviewTheme.orangeTint)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(data?.name ?? "Exercise")
                        .font(TTFont.workSans(15, weight: .medium))
                        .foregroundStyle(TTColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(TTFont.workSans(13, weight: .regular))
                        .foregroundStyle(OverviewTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OverviewTheme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let tempo = exercise.tempo, !tempo.isEmpty, let explained = tempoExplanation(tempo) {
                        Text(explained)
                            .font(TTFont.workSans(13, weight: .regular))
                            .foregroundStyle(OverviewTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let cues = data?.cues, !cues.isEmpty {
                        Text(cues.joined(separator: "\n"))
                            .font(TTFont.workSans(13, weight: .regular))
                            .foregroundStyle(OverviewTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let notes = exercise.notes, !notes.isEmpty {
                        Text(notes)
                            .font(TTFont.workSans(13, weight: .regular))
                            .foregroundStyle(OverviewTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 48)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// "{sets} sets × {reps} reps · {weight} · rest {sec} s".
    private var subtitle: String {
        // TODO: no timed-exercise flag in the model — reps unit is assumed. Use "sec" when a timed flag exists.
        let setsReps = "\(exercise.sets) sets × \(exercise.reps) reps"
        let weight: String
        if let w = exercise.recommendedWeightKg, w > 0 {
            weight = "\(w.cleanKg) kg"
        } else {
            weight = "Bodyweight"
        }
        return "\(setsReps) · \(weight) · rest \(exercise.restSeconds) s"
    }

    /// Expands "3-1-1-0" → "Tempo 3-1-1-0: 3 s down, 1 s pause, 1 s up, no pause at the top".
    private func tempoExplanation(_ tempo: String) -> String? {
        let parts = tempo.split { $0 == "-" || $0 == "/" }.compactMap { Int($0) }
        guard parts.count == 4 else { return "Tempo \(tempo)" }
        let down = "\(parts[0]) s down"
        let pauseBottom = parts[1] == 0 ? "no pause" : "\(parts[1]) s pause"
        let up = "\(parts[2]) s up"
        let pauseTop = parts[3] == 0 ? "no pause at the top" : "\(parts[3]) s pause at the top"
        return "Tempo \(tempo): \(down), \(pauseBottom), \(up), \(pauseTop)"
    }
}

// MARK: - Sticky start bar

struct StickyStartBar: View {
    let summary: String
    let plan: WorkoutPlan
    let day: PlanDay

    var body: some View {
        VStack(spacing: 10) {
            Text(summary)
                .font(TTFont.workSans(13, weight: .regular))
                .foregroundStyle(OverviewTheme.muted)
                .frame(maxWidth: .infinity, alignment: .center)

            NavigationLink {
                ActiveWorkoutView(plan: plan, day: day)
            } label: {
                Text("Start session")
                    .font(TTFont.workSans(16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(OverviewTheme.textOrange)   // #C2410C — ≥4.5:1 behind white
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Theme

private enum OverviewTheme {
    static let brandOrange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)   // icons/decoration only
    static let textOrange  = Color(red: 194 / 255, green: 65 / 255, blue: 12 / 255)    // #C2410C — text/fills behind white
    static let orangeTint  = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255).opacity(0.12)
    static let muted       = Color(red: 74 / 255, green: 78 / 255, blue: 86 / 255)     // secondary ≥4.5:1
    static let field       = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
}

// MARK: - Previews

private extension WorkoutExercise {
    static func sample(id: String, exerciseId: String, sets: Int, reps: Int, weight: Double?, rest: Int, tempo: String? = nil, notes: String? = nil) -> WorkoutExercise {
        WorkoutExercise(id: id, exerciseId: exerciseId, sets: sets, reps: reps, restSeconds: rest, recommendedWeightKg: weight, tempo: tempo, notes: notes)
    }
}

#Preview("Overview") {
    NavigationStack {
        WorkoutOverviewView(plan: TTPreview.samplePlan)
    }
    .ttPreviewTrainee()
}

#Preview("ExerciseRow · weighted / bodyweight / timed") {
    VStack(spacing: 10) {
        ExerciseRow(index: 0, exercise: .sample(id: "a", exerciseId: "x", sets: 4, reps: 8, weight: 60, rest: 90, tempo: "3-1-1-0"), data: nil, isExpanded: false, onToggle: {})
        ExerciseRow(index: 1, exercise: .sample(id: "b", exerciseId: "y", sets: 3, reps: 12, weight: nil, rest: 60), data: nil, isExpanded: false, onToggle: {})
        ExerciseRow(index: 2, exercise: .sample(id: "c", exerciseId: "z", sets: 3, reps: 30, weight: nil, rest: 45), data: nil, isExpanded: false, onToggle: {})
    }
    .padding().background(Color(white: 0.96))
}

#Preview("ExerciseRow · expanded") {
    ExerciseRow(
        index: 0,
        exercise: .sample(id: "a", exerciseId: "x", sets: 4, reps: 8, weight: 60, rest: 90, tempo: "3-1-1-0", notes: "Keep your core braced."),
        data: nil,
        isExpanded: true,
        onToggle: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("Overview · large type") {
    NavigationStack {
        WorkoutOverviewView(plan: TTPreview.samplePlan)
    }
    .ttPreviewTrainee()
    .environment(\.dynamicTypeSize, .accessibility3)
}
