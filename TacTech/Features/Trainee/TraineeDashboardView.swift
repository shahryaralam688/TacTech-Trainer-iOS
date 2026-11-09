import SwiftUI

/// Trainee Home — answers one question: "What should I do right now?"
/// Everything else is one tap away (Progress tab, Nutrition tab, Profile via avatar).
struct TraineeDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var showProfile = false
    @State private var showProgress = false
    @State private var showNutrition = false
    @State private var showWorkouts = false
    @State private var showNotifications = false
    @State private var showFindCoaches = false
    @State private var showAssessmentReview = false
    @State private var generateNotice: String?
    @State private var resumeTarget: ResumeTarget?
    @State private var overviewTarget: OverviewTarget?
    @Bindable private var notificationStore = NotificationStore.shared

    @StateObject private var scrollCollapse: TTHomeScrollCollapseModel = {
        let model = TTHomeScrollCollapseModel()
        model.layoutTravel = TTHomeHeaderCollapse.homeLayoutTravel
        return model
    }()

    private let canvas = Color(white: 0.98)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HomeHeader(
                    name: firstName,
                    avatarAsset: store.displayAvatarAsset,
                    avatarUrl: store.remoteAvatarURL,
                    avatarUserId: store.session?.userId,
                    unreadCount: notificationStore.unreadCount,
                    collapseProgress: scrollCollapse.progress,
                    onProfile: { TTHomeHaptics.light(); showProfile = true },
                    onNotifications: { TTHomeHaptics.light(); showNotifications = true }
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TTHomeScrollCollapseProbe(model: scrollCollapse, space: "traineeHome")

                        VStack(alignment: .leading, spacing: HomeTheme.gap) {
                            if isOffline {
                                OfflineBanner(onRetry: { Task { await refreshAll() } })
                            }
                            todayCard

                            sectionTitle("This week", linkTitle: "Progress") {
                                TTHomeHaptics.light(); showProgress = true
                            }
                            WeekStatsGrid(stats: weekStats)

                            if let next = nextStep {
                                NextStepCard(
                                    icon: next.icon,
                                    title: next.title,
                                    message: next.message,
                                    buttonTitle: next.button,
                                    action: { runNextStep(next) }
                                )
                            }

                            coachRowView
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)   // base; root adds tab-bar clearance via contentMargins
                    }
                }
                .refreshable { await refreshAll() }
                .ttTopRoundedSheet(
                    radius: TTSheetChrome.homeTopRadius(collapseProgress: scrollCollapse.progress),
                    fill: canvas
                )
                .ttObserveHomeScrollCollapse(scrollCollapse, space: "traineeHome")
            }
            .background(Color.black.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $resumeTarget) { target in
                ActiveWorkoutView(plan: target.plan, day: target.day)
            }
            .navigationDestination(item: $overviewTarget) { target in
                WorkoutOverviewView(plan: target.plan)
            }
            .ttSyncRootTabBarWithNavigationDepth()
            .task {
                if let trainee = store.currentTrainee {
                    await store.refreshDay(for: trainee.id, on: Date())
                }
            }
            .task { await store.refreshAICapabilities() }
            .task { await store.refreshActiveSession() }
            .task { await store.loadSandowScore() }
            .overlay(alignment: .top) { noticeOverlay }
            .sheet(isPresented: $showProfile) {
                TraineeProfileView(showsBack: true)
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showProgress) {
                TraineeProgressView().ttModalSheetPresentation()
            }
            .sheet(isPresented: $showNutrition) {
                NutritionView().ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showWorkouts) {
                WorkoutHubView(showsCloseChrome: true).ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsInboxView().ttModalSheetPresentation()
            }
            .sheet(isPresented: $showFindCoaches) {
                FindCoachesView().ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showAssessmentReview) {
                AssessmentReviewSheet(assessment: store.loadSavedFitnessAssessment()) {
                    flashGenerateNotice("AI week ready — open Workouts")
                    showWorkouts = true
                }
                .ttModalSheetPresentation()
            }
        }
    }

    @ViewBuilder private var noticeOverlay: some View {
        if let generateNotice {
            Text(generateNotice)
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.82))
                .clipShape(Capsule())
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Today card

    private var plan: WorkoutPlan? {
        store.currentTrainee.flatMap { store.assignedPlan(for: $0) }
    }

    private var todaySession: PlanDay? {
        guard let plan else { return nil }
        return plan.session(on: Date()) ?? plan.nextSession(from: Date())
    }

    private enum TodayMode { case ready, inProgress, done, noPlan, restDay }

    private var todayMode: TodayMode {
        guard let plan else { return .noPlan }
        // "Done today" wins — a finished log takes priority over a lingering/stale session.
        if hasCompletedTodayWorkout { return .done }
        // Only treat a session as in-progress if it's actually live (not already completed).
        if let session = store.activeWorkoutSession, session.completedAt == nil {
            return .inProgress
        }
        // Nothing scheduled for today → rest day (upcoming session still shown as "Next up").
        if plan.session(on: Date()) == nil { return .restDay }
        return .ready
    }

    /// A coach is linked → the Today card shows the "From Coach {name}" variant.
    private var isCoachAssigned: Bool { store.hasLinkedTrainer }

    /// Coach's note attached to *today's* actual session, if any.
    private var coachNoteToday: String? {
        guard let note = plan?.session(on: Date())?.coachNotes, !note.isEmpty else { return nil }
        return note
    }

    /// Brand-new account: no plan and nothing ever logged. Tiles show placeholders.
    private var isBrandNewAccount: Bool {
        guard plan == nil else { return false }
        guard let trainee = store.currentTrainee else { return true }
        return store.logs(for: trainee.id).isEmpty
    }

    // TODO: AppStore exposes no offline / refresh-error flag. Wire this to a real
    // connectivity or last-sync-failed signal when one exists; stays false for now.
    private var isOffline: Bool { false }

    private var sessionTitle: String {
        todaySession?.title ?? plan?.title ?? "Today’s training"
    }

    private var sessionMeta: String {
        let minutes = todaySession?.durationMinutes ?? plan?.durationMinutes ?? 25
        let count = todaySession?.exercises.count ?? plan?.allExercises.count ?? 0
        let level = plan?.level ?? "Training"
        return "\(minutes) min · \(count) exercises · \(level)"
    }

    private var exerciseChips: [String] {
        (todaySession?.exercises ?? []).compactMap { store.exercise(id: $0.exerciseId)?.name }
    }

    private var readyChip: String {
        // "Today · {time}" when a start time exists; otherwise just "Today".
        if let session = plan?.session(on: Date()), session.startTime != nil {
            return "Today · \(session.timeLabel)"
        }
        return "Today"
    }

    @ViewBuilder private var todayCard: some View {
        let coachName = isCoachAssigned ? coachFirstName : nil
        switch todayMode {
        case .ready:
            TodayCard(
                mode: .ready,
                sessionName: sessionTitle,
                meta: sessionMeta,
                exerciseChips: exerciseChips,
                statusChip: readyChip,
                fromCoachName: coachName,
                coachNote: coachNoteToday,
                onPrimary: startWorkout,
                onViewWorkout: viewWorkout
            )
        case .inProgress:
            let p = inProgressDisplay
            TodayCard(
                mode: .inProgress,
                sessionName: sessionTitle,
                meta: sessionMeta,
                fromCoachName: coachName,
                coachNote: coachNoteToday,
                elapsedText: p.elapsed,
                progressDetail: p.detail,
                setsDone: p.done,
                setsTotal: p.total,
                onPrimary: continueWorkout
            )
        case .done:
            TodayCard(
                mode: .done,
                sessionName: sessionTitle,
                meta: sessionMeta,
                fromCoachName: coachName,
                coachNote: coachNoteToday,
                nextUpText: nextUpText,
                onPrimary: {},
                onViewSummary: { TTHomeHaptics.light(); viewWorkout() },  // TODO: no dedicated summary screen — reuse overview preview
                onRepeat: { TTHomeHaptics.medium(); viewWorkout() },
                onShare: { /* TODO: share summary — no share sheet/export wired in current app */ },
                onNextUp: { TTHomeHaptics.light(); NotificationCenter.default.post(name: .ttOpenWorkoutHub, object: nil) }
            )
        case .restDay:
            TodayCard(
                mode: .restDay,
                sessionName: "Rest day",
                meta: "Recovery is part of the plan. Take it easy today.",
                nextUpText: nextUpText,
                onPrimary: { TTHomeHaptics.light(); NotificationCenter.default.post(name: .ttOpenWorkoutHub, object: nil) },
                onNextUp: { TTHomeHaptics.light(); NotificationCenter.default.post(name: .ttOpenWorkoutHub, object: nil) }
            )
        case .noPlan:
            noPlanCard
        }
    }

    @ViewBuilder private var noPlanCard: some View {
        if store.canShowSoloAIGenerate {
            TodayCard(
                mode: .noPlan,
                sessionName: "Build your plan",
                meta: "We’ll turn your assessment into a personalised week of training.",
                noPlanButtonTitle: "Build my plan",
                noPlanButtonIcon: "wand.and.stars",
                onPrimary: { TTHomeHaptics.medium(); showAssessmentReview = true }
            )
        } else if store.hasLinkedTrainer {
            TodayCard(
                mode: .noPlan,
                sessionName: "Plan on the way",
                meta: "Your coach is preparing your first plan. You’ll be notified when it’s ready.",
                noPlanButtonTitle: "View coach",
                noPlanButtonIcon: "person.crop.circle",
                onPrimary: { TTHomeHaptics.light(); showProfile = true }
            )
        } else {
            TodayCard(
                mode: .noPlan,
                sessionName: "Get your first workouts",
                meta: "Connect with a coach to receive a personalised plan.",
                noPlanButtonTitle: "Find a coach",
                noPlanButtonIcon: "link",
                onPrimary: { TTHomeHaptics.medium(); showFindCoaches = true }
            )
        }
    }

    /// In-progress numbers. Exercise index / set are derived from logged sets —
    /// TODO: `WorkoutSession` stores no explicit active-exercise index.
    private var inProgressDisplay: (elapsed: String, detail: String, done: Int, total: Int) {
        guard let session = store.activeWorkoutSession else {
            return ("In progress", "", 0, 0)
        }
        let plan = store.plans.first { $0.id == session.planId }
            ?? store.currentTrainee.flatMap { store.assignedPlan(for: $0) }
        let day = session.dayId.flatMap { id in plan?.days.first { $0.id == id } }
            ?? plan?.session(on: Date())
        let exercises = day?.exercises ?? []
        let total = exercises.reduce(0) { $0 + $1.workingSets.count }
        let done = session.sets.count

        let minutes = max(0, Int(Date().timeIntervalSince(session.startedAt) / 60))
        // A live workout spanning many hours is implausible — drop the minutes rather than show a stale count.
        let elapsed = minutes <= 600 ? "In progress · \(minutes) min" : "In progress"

        var acc = 0
        var idx = 0
        var setInEx = 1
        var name = exercises.first.flatMap { store.exercise(id: $0.exerciseId)?.name } ?? "Exercise"
        for (i, ex) in exercises.enumerated() {
            let c = ex.workingSets.count
            if done < acc + c {
                idx = i
                setInEx = done - acc + 1
                name = store.exercise(id: ex.exerciseId)?.name ?? "Exercise"
                break
            }
            acc += c
            idx = min(i + 1, max(exercises.count - 1, 0))
        }
        let detail = exercises.isEmpty
            ? "Keep going"
            : "Exercise \(min(idx + 1, exercises.count)) of \(exercises.count) · \(name) · Set \(setInEx)"
        return (elapsed, detail, done, total)
    }

    private var nextUpText: String? {
        guard let plan else { return nil }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        guard let next = plan.nextSession(from: tomorrow) else { return nil }
        return "Next up: \(next.weekday.short) · \(next.title) · \(next.durationMinutes) min"
    }

    // MARK: - This week

    private var weekStats: [WeekStatsGrid.Stat] {
        [scoreStat, waterStat, caloriesStat]
    }

    private var scoreStat: WeekStatsGrid.Stat {
        // Brand-new account: no data yet → placeholder.
        if isBrandNewAccount {
            return .init(id: "score", title: "Score", value: "—", subtext: "After your first workout") {
                TTHomeHaptics.light(); showProgress = true
            }
        }
        let score = store.sandowScore?.summaryScore
        let value = score.map(String.init) ?? "—"
        // Delta derived from the score trend; omitted when there aren't two points.
        var subtext = "This week"
        if let points = store.sandowScore?.points, points.count >= 2 {
            let delta = points.last!.score - points.first!.score
            if delta != 0 {
                subtext = "\(delta > 0 ? "↑" : "↓") \(abs(delta)) this week"
            } else {
                subtext = "No change"
            }
        }
        return .init(id: "score", title: "Score", value: value, subtext: subtext) {
            TTHomeHaptics.light(); showProgress = true
        }
    }

    private var waterStat: WeekStatsGrid.Stat {
        // TODO: no daily water-logging data source exists (only an assessment preference
        // string). Showing a clear placeholder until hydration logging is added.
        .init(id: "water", title: "Water", value: "—", subtext: "Not tracked yet") {
            TTHomeHaptics.light(); showNutrition = true
        }
    }

    private var caloriesStat: WeekStatsGrid.Stat {
        if isBrandNewAccount {
            return .init(id: "calories", title: "Calories", value: "—", subtext: "After your first workout") {
                TTHomeHaptics.light(); showNutrition = true
            }
        }
        let target = store.currentTrainee?.dailyCalorieTarget ?? 0
        let subtext = target > 0 ? "of \(target.formatted()) kcal" : "logged today"
        return .init(id: "calories", title: "Calories", value: "\(caloriesToday)", subtext: subtext) {
            TTHomeHaptics.light(); showNutrition = true
        }
    }

    // MARK: - Next step (context meal suggestion)

    private enum NextStepTarget { case nutrition, profile }

    private struct NextStep {
        var icon: String
        var title: String
        var message: String
        var button: String
        var target: NextStepTarget
    }

    /// First rule that applies wins; always hidden while a workout is in progress.
    private var nextStep: NextStep? {
        if todayMode == .inProgress { return nil }

        // 1. A coach request was just accepted or declined.
        //    TODO: no dedicated "recently responded" flag — reusing the lingering
        //    join-request status, which clears once the relationship reconciles.
        if let request = store.pendingJoinRequest {
            let name = pendingCoachName(request)
            switch request.status.lowercased() {
            case "accepted":
                return .init(icon: "checkmark.seal.fill",
                             title: "Coach \(name) accepted your request",
                             message: "You’re connected. Say hello and get your first plan.",
                             button: "View", target: .profile)
            case "rejected":
                return .init(icon: "xmark.seal.fill",
                             title: "\(name) can’t take you on right now",
                             message: "No worries — you can try another coach or invite code.",
                             button: "View", target: .profile)
            default: break
            }
        }

        // 2. Workout done today → recovery nutrition.
        if todayMode == .done {
            return .init(icon: "fork.knife",
                         title: "Refuel after your session",
                         message: "Only \(caloriesToday) kcal logged today. A protein-rich meal helps you recover.",
                         button: "Add a meal", target: .nutrition)
        }

        // 3. Workout scheduled and not started → pre-workout fuel.
        if todayMode == .ready {
            return .init(icon: "fork.knife",
                         title: "Fuel today’s session",
                         message: "Log breakfast or scan a meal so your macros stay on track with your plan.",
                         button: "Add a meal", target: .nutrition)
        }

        // 4. Low water in the afternoon.
        //    TODO: no hydration logging data source — this rule can't fire yet.
        //    Structure kept so it activates once daily water tracking exists.

        // 5. Otherwise hidden.
        return nil
    }

    private func runNextStep(_ step: NextStep) {
        TTHomeHaptics.medium()
        switch step.target {
        case .nutrition: showNutrition = true
        case .profile:   showProfile = true
        }
    }

    // MARK: - Coach row

    @ViewBuilder private var coachRowView: some View {
        if store.hasLinkedTrainer {
            let notes = store.currentTrainee.map { store.feedback(for: $0.id) } ?? []
            CoachRow(
                mode: .linked,
                coachName: coachFirstName,
                avatarUserId: coachUserId,
                detail: coachNotesDetail(notes),
                unread: notes.count,   // TODO: no unread/read flag on TrainerFeedback — using total note count
                action: {
                    TTHomeHaptics.light()
                    NotificationCenter.default.post(name: .ttOpenHumanChat, object: nil)
                }
            )
        } else if let pending = store.pendingJoinRequest, pending.isPending {
            CoachRow(
                mode: .pending,
                coachName: pendingCoachName(pending),
                detail: "Usually replies within a day",
                action: {}
            )
        } else if let request = store.pendingJoinRequest, request.status.lowercased() == "rejected" {
            CoachRow(
                mode: .declined,
                coachName: pendingCoachName(request),
                detail: "Try another code",
                action: { TTHomeHaptics.light(); showProfile = true }
            )
        } else {
            CoachRow(
                mode: .none,
                detail: "Enter an invite code",
                action: { TTHomeHaptics.medium(); showFindCoaches = true }
            )
        }
    }

    private func coachNotesDetail(_ notes: [TrainerFeedback]) -> String {
        guard let latest = notes.first else { return "No new notes yet" }
        if let exId = latest.relatedExerciseId, let name = store.exercise(id: exId)?.name {
            return notes.count == 1 ? "1 note on your \(name)" : "\(notes.count) notes on your \(name)"
        }
        return notes.count == 1 ? "1 coaching note" : "\(notes.count) coaching notes"
    }

    private var coachFirstName: String {
        let name = store.currentTrainee
            .flatMap { store.trainer(for: $0)?.userId }
            .flatMap { id in store.users.first { $0.id == id }?.name } ?? "Coach"
        return name.components(separatedBy: " ").first ?? name
    }

    private var coachUserId: String? {
        store.currentTrainee.flatMap { store.trainer(for: $0)?.userId }
    }

    private func pendingCoachName(_ pending: JoinRequestDTO) -> String {
        (pending.trainer?.name).map { $0.components(separatedBy: " ").first ?? $0 } ?? "your coach"
    }

    // MARK: - Actions

    /// Home "Start workout" → open the guided session directly (no overview in between).
    private func startWorkout() {
        TTHomeHaptics.medium()
        guard let plan,
              let day = plan.session(on: Date()) ?? plan.nextSession(from: Date()) else {
            showWorkouts = true
            return
        }
        resumeTarget = ResumeTarget(plan: plan, day: day)
    }

    /// Card "View workout" / done-state links → open the Workout Overview preview.
    private func viewWorkout() {
        guard let plan else { return }
        overviewTarget = OverviewTarget(plan: plan)
    }

    /// Resumes the live session in `ActiveWorkoutView` at its current exercise.
    private func continueWorkout() {
        TTHomeHaptics.medium()
        if let session = store.activeWorkoutSession,
           let plan = store.plans.first(where: { $0.id == session.planId })
                ?? store.currentTrainee.flatMap({ store.assignedPlan(for: $0) }),
           let day = session.dayId.flatMap({ id in plan.days.first(where: { $0.id == id }) })
                ?? plan.session(on: Date()) {
            resumeTarget = ResumeTarget(plan: plan, day: day)
        } else {
            showWorkouts = true
        }
    }

    /// Pull-to-refresh and offline-banner "Retry" both refresh the same background data.
    private func refreshAll() async {
        if let trainee = store.currentTrainee {
            await store.refreshDay(for: trainee.id, on: Date())
        }
        await store.refreshActiveSession()
        await store.loadSandowScore()
    }

    private func flashGenerateNotice(_ text: String) {
        withAnimation(.snappy(duration: 0.25)) { generateNotice = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { generateNotice = nil }
            }
        }
    }

    // MARK: - Shared chrome

    private func sectionTitle(_ title: String, linkTitle: String, link: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(TTFont.workSans(20, weight: .medium))
                .foregroundStyle(HomeTheme.ink)
            Spacer()
            Button(action: link) {
                Text(linkTitle)
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(HomeTheme.textOrange)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Derived data

    private var firstName: String {
        store.currentUser?.name.components(separatedBy: " ").first ?? "Athlete"
    }

    private var caloriesToday: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        return store.dailyMacros(for: trainee.id, on: Date()).calories
    }

    private var hasCompletedTodayWorkout: Bool {
        guard let trainee = store.currentTrainee else { return false }
        return store.logs(for: trainee.id).contains { Calendar.current.isDateInToday($0.completedAt) }
    }

    private var workoutsThisWeek: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return store.logs(for: trainee.id).filter { week.contains($0.completedAt) }.count
    }
}

// MARK: - Resume target

private struct ResumeTarget: Identifiable, Hashable {
    let plan: WorkoutPlan
    let day: PlanDay
    var id: String { "\(plan.id)#\(day.id)" }
}

private struct OverviewTarget: Identifiable, Hashable {
    let plan: WorkoutPlan
    var id: String { plan.id }
}

#Preview("Trainee Home") {
    TraineeDashboardView()
        .ttPreviewTrainee()
}

// MARK: - Shared theme (contrast-safe)

/// Home palette. Bright orange is for graphics/progress only; `textOrange`
/// (#C2410C) is the accessible variant for text and fills behind white.
enum HomeTheme {
    static let brandOrange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)   // #F97316 — graphics only
    static let textOrange  = Color(red: 194 / 255, green: 65 / 255, blue: 12 / 255)    // #C2410C — text / fills ≥4.5:1
    static let ink   = Color(red: 17 / 255, green: 18 / 255, blue: 20 / 255)
    static let muted = Color(red: 74 / 255, green: 78 / 255, blue: 86 / 255)           // secondary text ≥4.5:1 on white
    static let card  = Color.white
    static let field = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    static let line  = Color(red: 225 / 255, green: 227 / 255, blue: 232 / 255)

    static let cardCorner: CGFloat = 20
    static let buttonCorner: CGFloat = 16
    static let gap: CGFloat = 16
}

// MARK: - Home header (reuses the dark profile header, without the extra scores)

/// Dark Home header: avatar → Profile, greeting + date, bell with unread badge.
/// Trainee/Pro/health-score chips are intentionally omitted (see redesign brief).
struct HomeHeader: View {
    var name: String
    var avatarAsset: String?
    var avatarUrl: String?
    var avatarUserId: String?
    var unreadCount: Int
    var collapseProgress: CGFloat = 0
    var onProfile: () -> Void
    var onNotifications: () -> Void

    var body: some View {
        TTHomeProfileHeader(
            name: name,
            avatarSymbol: avatarAsset,
            avatarUrl: avatarUrl,
            avatarUserId: avatarUserId,
            badgeCount: unreadCount,
            showsAIPro: false,
            metrics: [],                       // no "Trainee", "Pro" or "82% Healthy" on Home
            collapseProgress: collapseProgress,
            onProfileTap: onProfile,
            onNotificationTap: onNotifications
        )
    }
}

// MARK: - Today card

/// The single "what should I do right now?" card. One primary action per state.
struct TodayCard: View {
    enum Mode { case ready, inProgress, done, noPlan, restDay }

    var mode: Mode
    var sessionName: String
    /// "{min} min · {n} exercises · {level}"
    var meta: String
    var exerciseChips: [String] = []

    /// Ready-state status chip, e.g. "Today · 7:30 AM".
    var statusChip: String = "Today"
    /// When set, the card shows the "From Coach {name}" variant.
    var fromCoachName: String? = nil
    /// Optional one-line note the coach left for today.
    var coachNote: String? = nil

    // In progress
    var elapsedText: String = ""          // "In progress · 12 min"
    var progressDetail: String = ""       // "Exercise 2 of 6 · Squat · Set 1"
    var setsDone: Int = 0
    var setsTotal: Int = 0

    // Done
    var nextUpText: String?               // "Next up: Wed · Upper body · 40 min"

    // No plan
    var noPlanButtonTitle: String = "Build my plan"
    var noPlanButtonIcon: String = "wand.and.stars"

    var onPrimary: () -> Void
    var onViewWorkout: (() -> Void)? = nil
    var onViewSummary: () -> Void = {}
    var onRepeat: () -> Void = {}
    var onShare: () -> Void = {}
    var onNextUp: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch mode {
            case .ready:       readyBody
            case .inProgress:  inProgressBody
            case .done:        doneBody
            case .noPlan:      noPlanBody
            case .restDay:     restDayBody
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: HomeTheme.cardCorner, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    // Ready ───────────────────────────────
    private var readyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusPill(fromCoachName.map { "From Coach \($0)" } ?? statusChip,
                       systemImage: fromCoachName == nil ? "calendar" : "person.crop.circle")
            titleBlock
            coachNoteLine
            if !exerciseChips.isEmpty { chipRow }
            primaryButton("Start workout", systemImage: "play.fill", action: onPrimary)
            if let onViewWorkout {
                Button(action: onViewWorkout) {
                    Text("View workout")
                        .font(TTFont.workSans(14, weight: .medium))
                        .foregroundStyle(HomeTheme.textOrange)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens a preview of today’s workout")
            }
        }
    }

    // In progress ─────────────────────────
    private var inProgressBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(fromCoachName.map { "From Coach \($0) · " + elapsedText } ?? elapsedText)
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(HomeTheme.textOrange)
            Text(sessionName)
                .font(TTFont.workSans(20, weight: .medium))
                .foregroundStyle(HomeTheme.ink)
            Text(progressDetail)
                .font(TTFont.workSans(14, weight: .regular))
                .foregroundStyle(HomeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: setsTotal > 0 ? Double(setsDone) / Double(setsTotal) : 0)
                .tint(HomeTheme.brandOrange)
            Text("\(setsDone) of \(setsTotal) sets done")
                .font(TTFont.workSans(12, weight: .medium))
                .foregroundStyle(HomeTheme.muted)

            primaryButton("Continue workout", systemImage: "arrow.right.circle.fill", action: onPrimary)
        }
    }

    // Done ────────────────────────────────
    private var doneBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(fromCoachName.map { "Done · Coach \($0)" } ?? "Done today")
                    .font(TTFont.workSans(13, weight: .medium))
            }
            .foregroundStyle(Color(red: 21 / 255, green: 128 / 255, blue: 61 / 255))  // green ≥4.5:1, with icon (not color alone)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 220 / 255, green: 252 / 255, blue: 231 / 255))
            .clipShape(Capsule())

            titleBlock
            coachNoteLine

            if let nextUpText {
                nextUpRow(nextUpText)
            }

            HStack(spacing: 10) {
                Button(action: onViewSummary) {
                    Text("View summary")
                        .font(TTFont.workSans(15, weight: .medium))
                        .foregroundStyle(HomeTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(HomeTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: HomeTheme.buttonCorner, style: .continuous))
                }
                .buttonStyle(.plain)

                Menu {
                    Button { onRepeat() } label: { Label("Repeat this workout", systemImage: "arrow.clockwise") }
                    Button { onShare() } label: { Label("Share summary", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HomeTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(HomeTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: HomeTheme.buttonCorner, style: .continuous))
                }
                .accessibilityLabel("More workout options")
            }
        }
    }

    // Rest day ─────────────────────────────
    private var restDayBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusPill("Rest day", systemImage: "moon.zzz.fill")
            titleBlock
            if let nextUpText {
                nextUpRow(nextUpText)
            }
            greyButton("See this week", systemImage: "calendar", action: onPrimary)
        }
    }

    // No plan ──────────────────────────────
    private var noPlanBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sessionName)
                .font(TTFont.workSans(20, weight: .medium))
                .foregroundStyle(HomeTheme.ink)
            Text(meta)
                .font(TTFont.workSans(14, weight: .regular))
                .foregroundStyle(HomeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            primaryButton(noPlanButtonTitle, systemImage: noPlanButtonIcon, action: onPrimary)
        }
    }

    // Shared pieces ────────────────────────
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sessionName)
                .font(TTFont.workSans(20, weight: .medium))
                .foregroundStyle(HomeTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(meta)
                .font(TTFont.workSans(14, weight: .regular))
                .foregroundStyle(HomeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chipRow: some View {
        FlowLayout(spacing: 8) {
            ForEach(exerciseChips.prefix(5), id: \.self) { chip in
                Text(chip)
                    .font(TTFont.workSans(12, weight: .medium))
                    .foregroundStyle(HomeTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HomeTheme.field)
                    .clipShape(Capsule())
            }
        }
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(TTFont.workSans(16, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(HomeTheme.brandOrange)      // orange fill behind white: kept for the single hero CTA
            .clipShape(RoundedRectangle(cornerRadius: HomeTheme.buttonCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Grey CTA — used by done / rest-day states (never two orange buttons at once).
    private func greyButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(TTFont.workSans(16, weight: .medium))
            }
            .foregroundStyle(HomeTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(HomeTheme.field)
            .clipShape(RoundedRectangle(cornerRadius: HomeTheme.buttonCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(TTFont.workSans(13, weight: .medium))
        }
        .foregroundStyle(HomeTheme.textOrange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(HomeTheme.brandOrange.opacity(0.12))
        .clipShape(Capsule())
        .fixedSize()
    }

    @ViewBuilder private var coachNoteLine: some View {
        if let coachNote {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HomeTheme.textOrange)
                Text(coachNote)
                    .font(TTFont.workSans(13, weight: .regular))
                    .foregroundStyle(HomeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func nextUpRow(_ text: String) -> some View {
        Button(action: onNextUp) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(HomeTheme.textOrange)
                Text(text)
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(HomeTheme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HomeTheme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeTheme.field)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your workouts")
    }
}

// MARK: - This week grid

struct WeekStatsGrid: View {
    struct Stat: Identifiable {
        var id: String
        var title: String
        var value: String
        var subtext: String
        var onTap: () -> Void
    }

    var stats: [Stat]

    var body: some View {
        // Fixed 3-column grid: no horizontal scroll, no cut-off cards.
        HStack(alignment: .top, spacing: 10) {
            ForEach(stats) { stat in
                Button(action: stat.onTap) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stat.title)
                            .font(TTFont.workSans(12, weight: .medium))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(stat.value)
                            .font(TTFont.workSans(24, weight: .medium))
                            .foregroundStyle(HomeTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(stat.subtext)
                            .font(TTFont.workSans(11, weight: .regular))
                            .foregroundStyle(HomeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .padding(12)
                    .background(HomeTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: HomeTheme.cardCorner, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stat.title): \(stat.value), \(stat.subtext)")
            }
        }
    }
}

// MARK: - Next step card

struct NextStepCard: View {
    var icon: String = "sparkles"
    var title: String
    var message: String
    var buttonTitle: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(HomeTheme.textOrange)
                .frame(width: 44, height: 44)
                .background(HomeTheme.brandOrange.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TTFont.workSans(15, weight: .medium))
                    .foregroundStyle(HomeTheme.ink)
                Text(message)
                    .font(TTFont.workSans(13, weight: .regular))
                    .foregroundStyle(HomeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: action) {
                Text(buttonTitle)
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(HomeTheme.textOrange)      // text/fill contrast-safe orange
                    .clipShape(RoundedRectangle(cornerRadius: HomeTheme.buttonCorner, style: .continuous))
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(HomeTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: HomeTheme.cardCorner, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

// MARK: - Coach row

struct CoachRow: View {
    enum Mode { case linked, none, pending, declined }

    var mode: Mode
    var coachName: String = ""
    var avatarUrl: String?
    var avatarUserId: String?
    var detail: String = ""
    var unread: Int = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText)
                        .font(TTFont.workSans(15, weight: .medium))
                        .foregroundStyle(HomeTheme.ink)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(TTFont.workSans(13, weight: .regular))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if mode == .linked, unread > 0 {
                    Text("\(unread)")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 5)
                        .background(HomeTheme.textOrange)
                        .clipShape(Capsule())
                }
                if mode != .pending {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(HomeTheme.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(HomeTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: HomeTheme.cardCorner, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(mode == .pending)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder private var leading: some View {
        switch mode {
        case .linked:
            TTUserAvatarView(
                avatarUrl: avatarUrl,
                avatarAsset: nil,
                userId: avatarUserId,
                name: coachName,
                size: 44,
                shape: .roundedRect,
                cornerRadius: 12
            )
        case .none:
            coachIcon("person.badge.plus")
        case .pending:
            coachIcon("clock")
        case .declined:
            coachIcon("person.crop.circle.badge.xmark")
        }
    }

    private func coachIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(HomeTheme.textOrange)
            .frame(width: 44, height: 44)
            .background(HomeTheme.field)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var primaryText: String {
        switch mode {
        case .linked:   "Coach \(coachName)"
        case .none:     "Train with a coach"
        case .pending:  "Request sent to \(coachName)"
        case .declined: "\(coachName) isn’t taking trainees"
        }
    }

    private var accessibility: String {
        switch mode {
        case .linked:   "Coach \(coachName). \(detail). \(unread) new. Opens coach chat."
        case .none:     "Train with a coach. Opens coach discovery."
        case .pending:  "Request sent to \(coachName). \(detail)."
        case .declined: "\(coachName) isn’t taking trainees. \(detail). Opens coach discovery."
        }
    }
}

// MARK: - Offline banner

/// Inline, non-blocking "can't refresh" banner shown under the header.
struct OfflineBanner: View {
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(HomeTheme.muted)
            Text("Can’t refresh. Showing your last update.")
                .font(TTFont.workSans(13, weight: .regular))
                .foregroundStyle(HomeTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onRetry) {
                Text("Retry")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(HomeTheme.textOrange)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 254 / 255, green: 243 / 255, blue: 199 / 255))  // soft amber
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Can’t refresh. Showing your last update. Double-tap Retry to try again.")
    }
}

// MARK: - Component previews

#Preview("TodayCard · ready") {
    TodayCard(
        mode: .ready,
        sessionName: "Upper Body Strength",
        meta: "45 min · 6 exercises · Intermediate",
        exerciseChips: ["Bench Press", "Row", "Shoulder Press", "Pull-up", "Curl"],
        statusChip: "Today · 7:30 AM",
        onPrimary: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("TodayCard · ready · from coach") {
    TodayCard(
        mode: .ready,
        sessionName: "Upper Body Strength",
        meta: "45 min · 6 exercises · Intermediate",
        exerciseChips: ["Bench Press", "Row", "Shoulder Press"],
        fromCoachName: "Sarah",
        coachNote: "Keep the tempo slow on the eccentric today.",
        onPrimary: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("TodayCard · rest day") {
    TodayCard(
        mode: .restDay,
        sessionName: "Rest day",
        meta: "Recovery is part of the plan. Take it easy today.",
        nextUpText: "Next up: Wed · Lower Body · 40 min",
        onPrimary: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("TodayCard · in progress") {
    TodayCard(
        mode: .inProgress,
        sessionName: "Upper Body Strength",
        meta: "45 min · 6 exercises · Intermediate",
        elapsedText: "In progress · 12 min",
        progressDetail: "Exercise 2 of 6 · Barbell Row · Set 1",
        setsDone: 4, setsTotal: 18,
        onPrimary: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("TodayCard · done") {
    TodayCard(
        mode: .done,
        sessionName: "Upper Body Strength",
        meta: "45 min · 6 exercises · Intermediate",
        nextUpText: "Next up: Wed · Lower Body · 40 min",
        onPrimary: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("TodayCard · no plan") {
    TodayCard(
        mode: .noPlan,
        sessionName: "Build your plan",
        meta: "We’ll turn your assessment into a personalised week.",
        onPrimary: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("NextStep · coach accepted") {
    NextStepCard(
        icon: "checkmark.seal.fill",
        title: "Coach Sarah accepted your request",
        message: "You’re connected. Say hello and get your first plan.",
        buttonTitle: "View",
        action: {}
    )
    .padding().background(Color(white: 0.96))
}

#Preview("CoachRow states") {
    VStack(spacing: 12) {
        CoachRow(mode: .linked, coachName: "Sarah", detail: "2 new notes on your Squat", unread: 2, action: {})
        CoachRow(mode: .none, detail: "Enter an invite code", action: {})
        CoachRow(mode: .pending, coachName: "Sarah", detail: "Usually replies within a day", action: {})
        CoachRow(mode: .declined, coachName: "Sarah", detail: "Try another code", action: {})
    }
    .padding().background(Color(white: 0.96))
}

#Preview("Offline banner") {
    OfflineBanner(onRetry: {})
        .padding().background(Color(white: 0.96))
}

#Preview("Week grid · brand-new account") {
    WeekStatsGrid(stats: [
        .init(id: "s", title: "Score", value: "—", subtext: "After your first workout", onTap: {}),
        .init(id: "w", title: "Water", value: "—", subtext: "Not tracked yet", onTap: {}),
        .init(id: "c", title: "Calories", value: "—", subtext: "After your first workout", onTap: {})
    ])
    .padding().background(Color(white: 0.96))
}

#Preview("Week grid · large type") {
    WeekStatsGrid(stats: [
        .init(id: "s", title: "Score", value: "82", subtext: "↑ 3 this week", onTap: {}),
        .init(id: "w", title: "Water", value: "—", subtext: "Not tracked yet", onTap: {}),
        .init(id: "c", title: "Calories", value: "480", subtext: "of 2,200 kcal", onTap: {})
    ])
    .padding().background(Color(white: 0.96))
    .environment(\.dynamicTypeSize, .accessibility3)
}
