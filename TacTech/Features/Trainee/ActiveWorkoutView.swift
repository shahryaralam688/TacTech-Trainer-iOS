import SwiftUI

// MARK: - Active workout (overview launcher)

struct ActiveWorkoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let plan: WorkoutPlan
    var day: PlanDay?
    /// Home "Start workout": open the guided session as soon as the session is ready.
    var autoStart = false
    @State private var didAutoStart = false
    @State private var logs: [WorkoutSetLog] = []
    @State private var showGuided = false
    @State private var guidedStartIndex = 0
    @State private var guidedElapsed = 0
    @State private var guidedTotalRest = 0
    @State private var showComplete = false
    @State private var pendingComplete = false
    /// Server-side session id — set once session is started or resumed.
    @State private var sessionId: String?
    @State private var sessionError: String?
    @State private var isStartingSession = false

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = TTColor.charcoal
    private let orange = TTColor.actionOrange

    private var exercises: [WorkoutExercise] { day?.exercises ?? plan.exercises }
    private var completedExerciseCount: Int { Set(logs.map(\.exerciseId)).count }
    /// Every working set of every exercise is logged (100%).
    private var allExercisesDone: Bool {
        !exercises.isEmpty && exercises.allSatisfy { item in
            item.workingSets.allSatisfy { set in
                logs.contains { $0.exerciseId == item.exerciseId && $0.setNumber == set.setNumber }
            }
        }
    }

    private static func relativeDay(_ weekday: Weekday) -> String {
        let todayIdx = Weekday.from(date: Date()).sortIndex
        let targetIdx = weekday.sortIndex
        switch (targetIdx - todayIdx + 7) % 7 {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 6: return "Yesterday"
        default: return weekday.title
        }
    }

    private var activeExerciseIndex: Int {
        for (i, item) in exercises.enumerated() {
            let allDone = item.workingSets.allSatisfy { set in
                logs.contains { $0.exerciseId == item.exerciseId && $0.setNumber == set.setNumber }
            }
            if !allDone { return i }
        }
        return max(0, exercises.count - 1)
    }

    var body: some View {
        TTCollapsingHeaderScreen(
            sheetFill: canvas,
            headerBackground: TTColor.charcoal,
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            header: { progress in
                TTDarkPageHeader(title: day?.title ?? plan.title, collapseProgress: progress) { dismiss() }
            }
        ) {
                VStack(alignment: .leading, spacing: 14) {
                    if let sessionError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255))
                            Text(sessionError)
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 254 / 255, green: 226 / 255, blue: 226 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Progress summary card
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.map { "\(Self.relativeDay($0.weekday)) · \($0.timeLabel)" } ?? "Session")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                            Text("\(completedExerciseCount) of \(exercises.count) done")
                                .font(TTFont.workSans(22, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                        }
                        Spacer()
                        ZStack {
                            Circle().stroke(Color(white: 0.88), lineWidth: 3).frame(width: 52, height: 52)
                            Circle().trim(from: 0, to: exercises.isEmpty ? 0 : CGFloat(completedExerciseCount) / CGFloat(exercises.count))
                                .stroke(orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 52, height: 52)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.4), value: completedExerciseCount)
                            Text("\(exercises.isEmpty ? 0 : Int(Double(completedExerciseCount) / Double(exercises.count) * 100))%")
                                .font(TTFont.workSans(12, weight: .bold))
                                .foregroundStyle(TTColor.ink)
                        }
                    }
                    .padding(16)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))

                    // Coach notes
                    if let notes = day?.coachNotes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(orange)
                            Text(notes)
                                .font(TTFont.body(13))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        .padding(14)
                        .background(orange.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Start / Continue button — a calm "Completed" state at 100%.
                    if allExercisesDone {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Completed ✓")
                                .font(TTFont.workSans(16, weight: .bold))
                        }
                        .foregroundStyle(TTColor.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityElement(children: .combine)
                    } else {
                        Button {
                            guidedStartIndex = activeExerciseIndex
                            showGuided = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: completedExerciseCount == 0 ? "play.fill" : "arrow.right.circle.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text(completedExerciseCount == 0 ? "Start Workout" : "Continue Workout")
                                    .font(TTFont.workSans(16, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: orange.opacity(0.35), radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                    }

                    // Exercise list header
                    Text("Today's exercises")
                        .font(TTFont.workSans(11, weight: .bold))
                        .foregroundStyle(TTColor.inkMuted)
                        .kerning(0.8)
                        .textCase(.uppercase)
                        .padding(.top, 4)

                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, item in
                        if let exercise = store.exercise(id: item.exerciseId) {
                            let isDone = item.workingSets.allSatisfy { set in
                                logs.contains { $0.exerciseId == item.exerciseId && $0.setNumber == set.setNumber }
                            }
                            let isActive = index == activeExerciseIndex && !isDone
                            overviewRow(exercise: exercise, item: item, index: index, isActive: isActive, isDone: isDone)
                        }
                    }
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        .background(charcoal.ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .task {
            await ensureSession()
            if autoStart, !didAutoStart, !allExercisesDone {
                didAutoStart = true
                guidedStartIndex = activeExerciseIndex
                showGuided = true
            }
        }
        .fullScreenCover(isPresented: $showGuided, onDismiss: {
            if pendingComplete {
                pendingComplete = false
                showComplete = true
            }
        }) {
            GuidedWorkoutFlow(
                exercises: exercises,
                planTitle: plan.title,
                startIndex: guidedStartIndex,
                sessionId: sessionId,
                logs: $logs
            ) { elapsed, rest in
                guidedElapsed = elapsed
                guidedTotalRest = rest
                pendingComplete = true
                showGuided = false
            }
        }
        .sheet(isPresented: $showComplete) {
            WorkoutCompleteSheet(
                duration: guidedElapsed,
                exercisesCount: completedExerciseCount,
                setsCount: logs.count
            ) {
                // Throws on failure: sessionId, `logs` and the store session stay exactly as they are,
                // so the sheet can offer Try again. Only clear/dismiss after the server confirmed.
                if let sid = sessionId {
                    // Session API path: complete via backend, which saves the log server-side.
                    try await store.completeWorkoutSession(
                        sessionId: sid,
                        durationMinutes: max(guidedElapsed / 60, 1),
                        durationSeconds: guidedElapsed,
                        totalRestSeconds: guidedTotalRest
                    )
                    sessionId = nil
                } else {
                    // Fallback: save a local log when session API was unavailable.
                    guard let trainee = store.currentTrainee else {
                        showComplete = false
                        dismiss()
                        return
                    }
                    try await store.saveWorkoutLog(
                        WorkoutLog(
                            id: UUID().uuidString,
                            traineeId: trainee.id,
                            planId: plan.id,
                            completedAt: .now,
                            durationMinutes: max(guidedElapsed / 60, 1),
                            sets: logs,
                            planDayId: day?.id,
                            sessionTitle: day?.title,
                            durationSeconds: guidedElapsed,
                            totalRestSeconds: guidedTotalRest
                        )
                    )
                }
                showComplete = false
                dismiss()
            }
        }
    }

    /// Starts a fresh session or resumes the active one if it belongs to this plan/day.
    private func ensureSession() async {
        guard sessionId == nil, !isStartingSession else { return }
        isStartingSession = true
        defer { isStartingSession = false }

        // Check if there is already an active session for this plan.
        if let existing = store.activeWorkoutSession, existing.planId == plan.id {
            logs = existing.sets
            sessionId = existing.id
            return
        }

        // Fetch from server in case the app was relaunched.
        await store.refreshActiveSession()
        if let existing = store.activeWorkoutSession, existing.planId == plan.id {
            logs = existing.sets
            sessionId = existing.id
            return
        }

        // No matching active session — start one (best-effort; if it fails, workout continues locally).
        do {
            let session = try await store.startWorkoutSession(planId: plan.id, dayId: day?.id)
            sessionId = session.id
        } catch {
            sessionError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func overviewRow(exercise: Exercise, item: WorkoutExercise, index: Int, isActive: Bool, isDone: Bool) -> some View {
        Button {
            guidedStartIndex = index
            showGuided = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(isDone ? orange : isActive ? orange.opacity(0.15) : Color(white: 0.88))
                        .frame(width: 36, height: 36)
                    if isDone {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)").font(TTFont.workSans(14, weight: .bold))
                            .foregroundStyle(isActive ? orange : Color(white: 0.55))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(TTFont.workSans(15, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isDone ? TTColor.inkMuted : TTColor.ink)
                    // One Text so the muscle group wraps with the prescription instead of floating beside it.
                    (Text(item.prescriptionLine).foregroundStyle(isActive ? orange : TTColor.inkMuted)
                        + Text(verbatim: " · ").foregroundStyle(TTColor.inkMuted)
                        + Text(exercise.muscleGroup).foregroundStyle(TTColor.inkMuted))
                        .font(TTFont.caption(12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isDone ? "checkmark.circle.fill" : isActive ? "play.circle.fill" : "chevron.right")
                    .font(.system(size: isDone || isActive ? 22 : 13, weight: .semibold))
                    .foregroundStyle(isDone ? orange.opacity(0.5) : isActive ? orange : Color(white: 0.75))
            }
            .padding(14)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous)
                .stroke(isActive ? orange.opacity(0.3) : Color.clear, lineWidth: 1.5))
            .opacity(isDone ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: isDone)
    }
}

// MARK: - Guided workout flow (one set at a time)

struct GuidedWorkoutFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let exercises: [WorkoutExercise]
    let planTitle: String
    let startIndex: Int
    /// Nil when session API was unavailable; sets are still logged locally.
    let sessionId: String?
    @Binding var logs: [WorkoutSetLog]
    /// (elapsed seconds, total rest seconds)
    let onFinish: (Int, Int) -> Void

    enum Phase { case exercise, rest }

    @State private var exerciseIndex: Int
    @State private var setIndex = 0
    @State private var phase: Phase = .exercise
    @State private var restSeconds = 0
    /// Real timing: when the current set began, when the current rest began, and rest accumulated so far.
    @State private var setStartedAt: Date?
    @State private var restStartedAt: Date?
    @State private var restingAfter: (exerciseId: String, setNumber: Int)?
    @State private var totalRestSeconds = 0
    @State private var elapsed = 0
    @State private var timerRunning = false
    @State private var showExitConfirm = false  // C3
    @State private var isSavingSet = false
    @State private var saveError: String? = nil
    @State private var pendingSet: PendingSetInfo? = nil

    private struct PendingSetInfo {
        var sessionId: String
        var exerciseId: String
        var setNumber: Int
        var reps: Int
        var weightKg: Double
        var durationSeconds: Int?
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let orange = TTColor.actionOrange
    private let charcoal = TTColor.charcoal

    init(exercises: [WorkoutExercise], planTitle: String, startIndex: Int, sessionId: String?, logs: Binding<[WorkoutSetLog]>, onFinish: @escaping (Int, Int) -> Void) {
        self.exercises = exercises
        self.planTitle = planTitle
        self.startIndex = startIndex
        self.sessionId = sessionId
        self._logs = logs
        self.onFinish = onFinish
        self._exerciseIndex = State(initialValue: startIndex)
        // C2: resume at the first set not yet in logs for the starting exercise
        let currentLogs = logs.wrappedValue
        if exercises.indices.contains(startIndex) {
            let item = exercises[startIndex]
            let loggedSetNumbers = Set(currentLogs.filter { $0.exerciseId == item.exerciseId }.map { $0.setNumber })
            let resumeSet = item.workingSets.firstIndex { !loggedSetNumbers.contains($0.setNumber) } ?? 0
            self._setIndex = State(initialValue: resumeSet)
        } else {
            self._setIndex = State(initialValue: 0)
        }
    }

    private var currentItem: WorkoutExercise? {
        exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil
    }
    private var currentExercise: Exercise? {
        currentItem.flatMap { store.exercise(id: $0.exerciseId) }
    }
    private var currentSet: PrescribedSet? {
        guard let item = currentItem, item.workingSets.indices.contains(setIndex) else { return nil }
        return item.workingSets[setIndex]
    }
    private var totalSets: Int { currentItem?.workingSets.count ?? 0 }
    private var isLastSet: Bool { setIndex >= totalSets - 1 }
    private var isLastExercise: Bool { exerciseIndex >= exercises.count - 1 }

    // What comes after the current rest
    private var upNextExercise: Exercise? {
        if isLastSet {
            let ni = exerciseIndex + 1
            guard exercises.indices.contains(ni) else { return nil }
            return store.exercise(id: exercises[ni].exerciseId)
        }
        return currentExercise
    }
    private var upNextSet: PrescribedSet? {
        if isLastSet {
            let ni = exerciseIndex + 1
            guard exercises.indices.contains(ni) else { return nil }
            return exercises[ni].workingSets.first
        }
        guard let item = currentItem, item.workingSets.indices.contains(setIndex + 1) else { return nil }
        return item.workingSets[setIndex + 1]
    }

    private var overallProgress: Double {
        let total = exercises.reduce(0) { $0 + $1.workingSets.count }
        guard total > 0 else { return 0 }
        return Double(logs.count) / Double(total)
    }
    private var timeString: String { String(format: "%02d:%02d", elapsed / 60, elapsed % 60) }
    private var restString: String { String(format: "%d:%02d", restSeconds / 60, restSeconds % 60) }

    private func logSet() {
        guard let item = currentItem, let set = currentSet else { return }
        // C2: prevent re-logging a set already recorded (e.g. after leave-and-re-enter)
        guard !logs.contains(where: { $0.exerciseId == item.exerciseId && $0.setNumber == set.setNumber }) else {
            doAdvance()
            return
        }
        if !timerRunning { timerRunning = true }
        let weightKg = set.weightKg ?? item.recommendedWeightKg ?? 0
        let setSeconds = setStartedAt.map { max(0, Int(Date().timeIntervalSince($0))) }

        guard let sid = sessionId else {
            // No session active — no backend to confirm; append locally and advance immediately.
            let localLog = WorkoutSetLog(
                id: UUID().uuidString,
                exerciseId: item.exerciseId,
                setNumber: set.setNumber,
                reps: set.reps,
                weightKg: weightKg,
                durationSeconds: setSeconds
            )
            logs.append(localLog)
            doAdvance()
            return
        }

        let info = PendingSetInfo(
            sessionId: sid,
            exerciseId: item.exerciseId,
            setNumber: set.setNumber,
            reps: set.reps,
            weightKg: weightKg,
            durationSeconds: setSeconds
        )
        pendingSet = info
        isSavingSet = true
        saveError = nil
        Task { await commitSet(info) }
    }

    private func commitSet(_ info: PendingSetInfo) async {
        do {
            let confirmed = try await store.logSet(
                sessionId: info.sessionId,
                exerciseId: info.exerciseId,
                setNumber: info.setNumber,
                reps: info.reps,
                weightKg: info.weightKg,
                durationSeconds: info.durationSeconds
            )
            if !logs.contains(where: { $0.exerciseId == confirmed.exerciseId && $0.setNumber == confirmed.setNumber }) {
                logs.append(confirmed)
            }
            pendingSet = nil
            isSavingSet = false
            doAdvance()
        } catch {
            isSavingSet = false
            saveError = "Couldn't save set — check your connection."
        }
    }

    private func retryPendingSet() {
        guard let info = pendingSet else { return }
        isSavingSet = true
        saveError = nil
        Task { await commitSet(info) }
    }

    private func doAdvance() {
        if isLastSet && isLastExercise {
            onFinish(elapsed, totalRestSeconds)
            dismiss()
        } else {
            if let item = currentItem, let set = currentSet {
                restingAfter = (item.exerciseId, set.setNumber)
            }
            restStartedAt = Date()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .rest }
            restSeconds = max(0, currentItem?.restSeconds ?? 90)
        }
    }

    /// Rest ended (countdown hit 0 or Skip): record the real seconds on the set it followed.
    private func finishRestTiming() {
        defer { restStartedAt = nil; restingAfter = nil }
        guard let started = restStartedAt else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(started)))
        totalRestSeconds += seconds
        if let key = restingAfter,
           let i = logs.firstIndex(where: { $0.exerciseId == key.exerciseId && $0.setNumber == key.setNumber }) {
            logs[i].restSeconds = seconds
        }
    }

    private func advanceAfterRest() {
        finishRestTiming()
        setStartedAt = Date()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if isLastSet {
                exerciseIndex += 1
                setIndex = 0
            } else {
                setIndex += 1
            }
            phase = .exercise
        }
    }
    var body: some View {
        ZStack {
            charcoal.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Minimal header ───────────────────────────────────────
                HStack {
                    Button { showExitConfirm = true } label: {  // C3: confirm before leaving
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(timerRunning ? timeString : "– : –")
                            .font(.system(size: 18, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(timerRunning ? .white : .white.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Workout time"))
                    .accessibilityValue(Text(timerRunning ? timeString : "–"))
                    Spacer(minLength: 8)
                    Text("\(exerciseIndex + 1) / \(exercises.count)")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(minWidth: 34, alignment: .trailing)
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Overall progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                        Capsule().fill(orange)
                            .frame(width: geo.size.width * overallProgress, height: 3)
                            .animation(.easeInOut(duration: 0.5), value: overallProgress)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, TTSpace.screen)
                .padding(.bottom, 16)

                // ── Phase content ────────────────────────────────────────
                ZStack {
                    if phase == .exercise {
                        exerciseScreen
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        restScreen
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.85), value: phase == .exercise)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ttHideSystemNavigationBar()
        .sensoryFeedback(.success, trigger: logs.count)
        .onAppear { timerRunning = true; if setStartedAt == nil { setStartedAt = Date() } }
        .onReceive(timer) { _ in
            if timerRunning { elapsed += 1 }
            if restSeconds > 0 {
                restSeconds -= 1
                if restSeconds == 0 { advanceAfterRest() }
            }
        }
        // C3: exit confirmation — timer, rest countdown and progress are not reset on Cancel
        .confirmationDialog("Leave workout?", isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button("Leave workout", role: .destructive) { dismiss() }
            Button("Stay in workout", role: .cancel) {}
        } message: {
            Text("Sets you've completed are saved. Your timer will reset if you return.")
        }
    }

    // ── Exercise screen ──────────────────────────────────────────────────
    @ViewBuilder
    private var exerciseScreen: some View {
        if let exercise = currentExercise, let set = currentSet {
            VStack(spacing: 0) {
                Spacer()

                // Exercise name + muscle group
                VStack(spacing: 10) {
                    Text(exercise.name)
                        .font(TTFont.workSans(34, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TTSpace.screen)

                    HStack(spacing: 8) {
                        label(exercise.muscleGroup)
                        label(exercise.equipment)
                    }
                }

                Spacer()

                // Set target — big and clear
                VStack(spacing: 6) {
                    Text("Set \(setIndex + 1) of \(totalSets)")
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))

                    Text("\(set.reps)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text("reps")
                        .font(TTFont.workSans(18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))

                    if let kg = set.weightKg {
                        Text("\(kg.cleanKg) kg")
                            .font(TTFont.workSans(24, weight: .bold))
                            .foregroundStyle(orange)
                            .padding(.top, 4)
                    }
                }

                Spacer()

                // Trainer note (compact)
                if let notes = currentItem?.notes, !notes.isEmpty {
                    Text(notes)
                        .font(TTFont.body(13))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TTSpace.screen)
                        .padding(.bottom, 12)
                }

                // Done button
                VStack(spacing: 12) {
                    Button { logSet() } label: {
                        ZStack {
                            Text("Done")
                                .font(TTFont.workSans(20, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(isSavingSet ? 0 : 1)
                            if isSavingSet {
                                ProgressView().tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(isSavingSet ? orange.opacity(0.55) : orange)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: orange.opacity(0.4), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingSet)

                    if let err = saveError {
                        VStack(spacing: 6) {
                            Text(err)
                                .font(TTFont.caption(13))
                                .foregroundStyle(.white.opacity(0.65))
                                .multilineTextAlignment(.center)
                            Button("Retry") { retryPendingSet() }
                                .font(TTFont.workSans(15, weight: .semibold))
                                .foregroundStyle(orange)
                        }
                    }
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.bottom, 48)
            }
        }
    }

    // ── Rest screen ──────────────────────────────────────────────────────
    @ViewBuilder
    private var restScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Rest")
                .font(TTFont.workSans(20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(restString)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .monospacedDigit()
                .padding(.top, 4)

            Spacer()

            // Up next preview
            if let nextEx = upNextExercise, let nextSet = upNextSet {
                VStack(spacing: 6) {
                    Text("UP NEXT")
                        .font(TTFont.workSans(10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .kerning(1.2)
                    Text(isLastSet ? nextEx.name : nextEx.name)
                        .font(TTFont.workSans(18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("Set \(isLastSet ? 1 : setIndex + 2) · \(nextSet.reps) reps\(nextSet.weightKg.map { " · \($0.cleanKg) kg" } ?? "")")
                        .font(TTFont.caption(13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.bottom, 32)
            }

            // Skip button
            Button { advanceAfterRest() } label: {
                Text("Skip rest")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TTSpace.screen)
            .padding(.bottom, 48)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(TTFont.workSans(12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Workout complete sheet

private struct WorkoutCompleteSheet: View {
    let duration: Int
    let exercisesCount: Int
    let setsCount: Int
    /// Saves the workout. Throws if the server did not confirm.
    let onDone: () async throws -> Void

    @Environment(\.dismiss) private var sheetDismiss
    @State private var isSaving = false
    @State private var saveFailed = false
    private let orange = TTColor.actionOrange

    private func finish() {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Saving your workout…"))
        Task {
            do {
                try await onDone()
                isSaving = false
                sheetDismiss()
            } catch {
                isSaving = false
                saveFailed = true
                UIAccessibility.post(
                    notification: .announcement,
                    argument: String(localized: "Couldn't save your workout. Your sets are safe.")
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(white: 0.82))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(orange.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Text("🏆")
                        .font(.system(size: 52))
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Workout Complete!")
                        .font(TTFont.workSans(26, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text(motivationLine)
                        .font(TTFont.workSans(14, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 0) {
                    statBox(value: durationString, label: "Duration")
                    Divider().frame(height: 44)
                    statBox(value: "\(exercisesCount)", label: "Exercises")
                    Divider().frame(height: 44)
                    statBox(value: "\(setsCount)", label: "Sets")
                }
                .padding(.vertical, 16)
                .background(Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(spacing: 10) {
                    if saveFailed {
                        Text("Couldn't save your workout. Your sets are safe.")
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    Button { finish() } label: {
                        ZStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .accessibilityLabel(Text("Saving your workout…"))
                            } else {
                                Text(saveFailed ? "Try again" : "Done — back to home")
                                    .font(TTFont.workSans(16, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(orange.opacity(isSaving ? 0.6 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

                    if saveFailed && !isSaving {
                        // Closes the sheet only; the session and every logged set stay in place.
                        Button("Not now") { sheetDismiss() }
                            .font(TTFont.workSans(15, weight: .semibold))
                            .foregroundStyle(TTColor.inkMuted)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)  // C1: prevent swipe-dismiss bypassing log save
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(label)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationString: String {
        let mins = duration / 60
        if mins == 0 { return "\(duration)s" }
        return "\(mins)m"
    }

    private var motivationLine: String {
        let lines = [
            "Every rep counts. You showed up.",
            "That's another session in the bank.",
            "Consistency beats intensity every time.",
            "Your future self will thank you.",
            "One workout at a time. Keep going."
        ]
        return lines[abs(setsCount) % lines.count]
    }
}

#Preview("Active Workout") {
    NavigationStack {
        ActiveWorkoutView(plan: TTPreview.samplePlan, day: TTPreview.samplePlan.session(on: .now))
            .ttPreviewTrainee()
    }
}
