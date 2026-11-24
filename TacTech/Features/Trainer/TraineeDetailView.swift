import SwiftUI

/// The three tabs of the trainee profile.
private enum TraineeProfileTab: String, CaseIterable, Identifiable {
    case today, plan, progress
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .plan: "Plan"
        case .progress: "Progress"
        }
    }
}

/// Sections of the Progress tab.
private enum TraineeProgressChip: String, CaseIterable, Identifiable {
    case overview, history, meals, form
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .history: "History"
        case .meals: "Meals"
        case .form: "Form"
        }
    }
}

/// Three equal-width flexible buttons plus one fixed 44pt button ("...") at the right end.
/// Its natural width is 3 x the WIDEST button + the fixed one, so `ViewThatFits` only picks a level when every
/// label really fits in an equal share (a plain HStack let the longest label be squeezed into "Change...").
private struct TraineeActionRowLayout: Layout {
    var spacing: CGFloat = 8
    var fixedWidth: CGFloat = 44

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 4 else { return .zero }
        let flexible = subviews.dropLast().map { $0.sizeThatFits(.unspecified) }
        let widest = flexible.map(\.width).max() ?? 0
        let height = max(flexible.map(\.height).max() ?? 0, fixedWidth)
        let natural = widest * 3 + fixedWidth + spacing * 3
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        let share = max(0, (bounds.width - fixedWidth - spacing * 3) / 3)
        var x = bounds.minX
        for index in 0..<3 {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: share, height: bounds.height)
            )
            x += share + spacing
        }
        subviews[3].place(
            at: CGPoint(x: bounds.maxX - fixedWidth, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: fixedWidth, height: fixedWidth)
        )
    }
}

struct TraineeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trainee: TraineeProfile
    @State private var note = ""
    @State private var selectedDay = Date()
    @State private var showAssignSheet = false
    @State private var previousPlanId: String?
    @State private var viewedPlan: WorkoutPlan?
    @State private var celebrateAssign = false
    @State private var feedbackToast: TTToastMessage?
    @State private var unassignConfirm = false
    @State private var isUnassigning = false
    @State private var removeConfirm = false
    @State private var isRemoving = false
    @State private var progressChip: TraineeProgressChip = .overview
    @State private var detailMeal: Meal?
    @State private var showAllNotes = false
    @State private var isRefreshingPerformance = false
    @State private var performanceError: String?
    /// False until the first performance load has finished (skeleton on first load only).
    @State private var didLoadPerformance = false
    @State private var selectedTab: TraineeProfileTab = .today
    @State private var chatTarget: TTChatTarget?
    @State private var expandedDayIds: Set<String> = []
    /// Last live session seen for this trainee, and the one the card keeps showing until the logs reload.
    @State private var lastLiveSession: WorkoutSession?
    @State private var lingeringLive: WorkoutSession?
    @State private var showNoteSheet = false
    @State private var noteSheetError: String?
    @FocusState private var noteSheetFocused: Bool

    /// How long the "Training now" card is held after the live session ends, while the logs reload.
    /// After this the card shows whatever the data says (Finished, or "Not logged yet") — no error banner.
    private static let liveHoldLimit: TimeInterval = 5

    /// A live session with no activity for this long is shown as "Session open", not "Training now"
    /// (the server only stops reporting a session after 4 hours of silence).
    private static let staleLiveAfter: TimeInterval = 30 * 60

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var displayName: String {
        store.user(forTrainee: trainee)?.name ?? "Trainee"
    }

    private var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    private var currentAssignedPlan: WorkoutPlan? {
        store.assignedPlan(for: trainee)
    }

    private var analytics: TraineeAnalytics? {
        store.analytics(for: trainee.id)
    }

    var body: some View {
        // Header is drawn over the scroll view; the content size never depends on its collapse.
        // The action row + tab control pin directly under the collapsed header.
        ScrollViewReader { proxy in
        TTCollapsingHeaderScreen(
            sheetFill: canvas,
            headerBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
            topRadius: { _ in TTSheetChrome.pageTopRadius },
            pinsBelowCollapsedHeader: true,
            topAnchorID: "profileTop",
            onRefresh: {
                await reloadPerformance(forceErrorSurface: true)
                await store.refreshDay(for: trainee.id, on: selectedDay)
            },
            header: { progress in profileHeader(progress: progress) }
        ) {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                Section {
                    tabContent
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                } header: {
                    pinnedBar(proxy: proxy)
                }
            }
        }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
        .ttHideSystemNavigationBar()
        .perfTempScreen("Trainee Detail") // PERF-TEMP
        // Open-profile bookkeeping for the live "Training now" feed. A sheet or cover presented from this
        // screen must not clear it, so onDisappear only clears when nothing is presented from here.
        .onAppear { store.setOpenTraineeProfile(trainee.id) }
        .onDisappear {
            if !(chatTarget != nil || showNoteSheet || showAssignSheet), store.openTraineeProfileId == trainee.id {
                store.setOpenTraineeProfile(nil)
            }
        }
        // (i) The Today tab appears → fetch this trainee's live session (one request, never polled).
        .task(id: selectedTab) {
            if selectedTab == .today { await store.refreshLiveSession(traineeId: trainee.id) }
        }
        .onChange(of: liveStamp) { _, _ in handleLiveChange() }
        .onChange(of: store.trainees.map(\.id)) { _, ids in
            // Peer leave / remote remove — detail is stale; pop without force-quit.
            if !ids.contains(trainee.id) {
                dismiss()
            }
        }
        .task(id: trainee.id) {
            await reloadPerformance(forceErrorSurface: false)
        }
        .task(id: selectedDay) {
            await store.refreshDay(for: trainee.id, on: selectedDay)
        }
        .sheet(item: $detailMeal) { meal in
            TTMealDetailSheet(meal: meal)
                .ttModalSheetPresentation()
        }
        // A meal was logged (realtime): refresh this trainee's meals for the day on screen.
        .onReceive(NotificationCenter.default.publisher(for: .ttMealLogged)) { note in
            guard (note.userInfo?["traineeId"] as? String) == trainee.id else { return }
            Task { await store.refreshDay(for: trainee.id, on: selectedDay) }
        }
        // Opened from a "meal logged" notification: Progress > Meals on the day of that meal.
        .onReceive(NotificationCenter.default.publisher(for: .ttOpenTraineeMeals)) { _ in
            Task { await consumeMealDeepLink() }
        }
        .task { await consumeMealDeepLink() }
        .ttAssignSuccessChrome(toast: $feedbackToast, celebrate: $celebrateAssign)
        .navigationDestination(item: $viewedPlan) { plan in
            WorkoutPlanDetailView(plan: plan)
        }
        .sheet(isPresented: $showAssignSheet) {
            PlanQuickAssignSheet(preselectedTraineeId: trainee.id, onAssigned: {
                showAssignedToast()
            })
            .ttModalSheetPresentation()
        }
        .fullScreenCover(item: $chatTarget) { target in
            HumanPeerChatView(audience: .trainer, preferredPeerUserId: target.id, preferredPeerName: target.name)
        }
        .sheet(isPresented: $showNoteSheet) {
            noteSheet
                .ttModalSheetPresentation(detents: [.medium, .large])
        }
        .confirmationDialog(
            "Unassign this plan?",
            isPresented: $unassignConfirm,
            titleVisibility: .visible
        ) {
            Button("Unassign", role: .destructive) {
                Task { await unassignCurrentPlan() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(displayName) will no longer see this plan as their assigned program.")
        }
        .confirmationDialog(
            "Remove from roster?",
            isPresented: $removeConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove from roster", role: .destructive) {
                guard !isRemoving else { return }
                Task { @MainActor in
                    await removeFromRoster()
                }
            }
            .disabled(isRemoving)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(displayName) from your roster? Their assigned plan will be cleared. Chat stays.")
        }
    }

    // MARK: - Header (avatar, name, "goal · weight · height")

    /// "goal · weight · height" — empty parts are skipped, so there is never a dangling separator.
    private var headerSubtitle: String {
        var parts: [String] = []
        let goal = trainee.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty { parts.append(goal) }
        if trainee.weightKg > 0 { parts.append("\(Int(trainee.weightKg)) kg") }
        if trainee.heightCm > 0 { parts.append("\(trainee.heightCm) cm") }
        return parts.joined(separator: " · ")
    }

    private func profileHeader(progress: CGFloat) -> some View {
        let p = min(1, max(0, progress))
        let expand = 1 - p
        let subtitle = headerSubtitle
        return HStack(alignment: .center, spacing: 12) {
            TTBackButton(style: .onDark) { dismiss() }
                .scaleEffect(1 - 0.06 * p, anchor: .center)
            TTAvatar(name: displayName, size: 52 - 16 * p)
            VStack(alignment: .leading, spacing: 3 * expand) {
                Text(displayName)
                    .font(TTFont.workSans(24 - 6 * p, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TTFont.textSM(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .opacity(Double(expand))
                        .frame(height: 18 * expand, alignment: .top)
                        .clipped()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TTSpace.screen)
        .padding(.top, 10 - 2 * p)
        .padding(.bottom, 16 - 6 * p)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background {
            Rectangle()
                .fill(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255))
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pinned action row + tab control

    private func pinnedBar(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            actionRow

            Picker("Profile section", selection: Binding(
                get: { selectedTab },
                set: { newValue in
                    // Every tab change returns to the top (same scrollTo approach as the Plans list).
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = newValue
                        proxy.scrollTo("profileTop", anchor: .top)
                    }
                }
            )) {
                ForEach(TraineeProfileTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(canvas)
    }

    /// How much room the action row has. The first level whose natural width fits is used (no horizontal scrolling,
    /// so the "..." button can never be pushed off the edge).
    private enum ActionLevel {
        /// Icon + label side by side, full labels ("Change plan").
        case full
        /// Icon + label side by side, shorter labels ("Plan").
        case short
        /// Icon above a small label (Contacts style). Always fits.
        case stacked
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            actionRowLayout(.full)
            actionRowLayout(.short)
            actionRowLayout(.stacked)
        }
    }

    /// Message, Note and Plan share the remaining width equally; "..." is fixed 44 x 44 at the right end.
    private func actionRowLayout(_ level: ActionLevel) -> some View {
        TraineeActionRowLayout {
            Button {
                let name = store.user(forTrainee: trainee)?.name
                let peerId = TTTraineeChatOpener.prepare(for: trainee, name: name)
                chatTarget = TTChatTarget(id: peerId, name: name)
            } label: {
                actionLabel("Message", systemImage: "bubble.left.fill", primary: true, level: level)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Message \(firstName)")

            Button {
                noteSheetError = nil
                showNoteSheet = true
            } label: {
                actionLabel("Note", systemImage: "square.and.pencil", primary: false, level: level)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Write a note for \(firstName)")

            Button {
                openAssignSheet()
            } label: {
                actionLabel(planActionTitle(level), systemImage: "calendar.badge.plus", primary: false, level: level)
            }
            .buttonStyle(.plain)
            // The full name at every level, so VoiceOver never reads the short label.
            .accessibilityLabel(currentAssignedPlan == nil ? "Assign plan" : "Change plan")

            moreMenu
        }
    }

    private func planActionTitle(_ level: ActionLevel) -> LocalizedStringKey {
        switch (level, currentAssignedPlan == nil) {
        case (.full, true): "Assign plan"
        case (.full, false): "Change plan"
        case (_, true): "Assign"
        case (_, false): "Plan"
        }
    }

    private var moreMenu: some View {
        Menu {
            if let plan = currentAssignedPlan {
                Button { viewedPlan = plan } label: { Label("View full plan", systemImage: "doc.text") }
            }
            if currentAssignedPlan != nil {
                Button(role: .destructive) { unassignConfirm = true } label: { Label("Unassign plan…", systemImage: "minus.circle") }
            }
            Button(role: .destructive) { removeConfirm = true } label: { Label("Remove from roster…", systemImage: "person.crop.circle.badge.minus") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .frame(width: 44, height: 44)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .fixedSize()
        .accessibilityLabel("More actions")
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String, primary: Bool, level: ActionLevel) -> some View {
        Group {
            if level == .stacked {
                VStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                    Text(title)
                        .font(TTFont.workSans(11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 48)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                    Text(title)
                        .font(TTFont.workSans(14, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, level == .full ? 14 : 8)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(primary ? Color.white : TTColor.ink)
        .background(primary ? Color.black : cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .today:
            VStack(alignment: .leading, spacing: 12) { todayTab }
                .animation(.easeInOut(duration: 0.2), value: (store.liveSessionByTrainee[trainee.id] ?? lingeringLive) != nil)
        case .plan:
            VStack(alignment: .leading, spacing: 12) {
                if let plan = currentAssignedPlan {
                    planTab(plan: plan)
                } else {
                    assignCard
                }
            }
        case .progress:
            VStack(alignment: .leading, spacing: 12) {
                progressChips

                TTLoadGate(
                    isLoading: isRefreshingPerformance || !didLoadPerformance,
                    hasData: progressHasData,
                    loadingLabel: "Loading progress"
                ) {
                    progressSkeleton
                } content: {
                    if let performanceError, !progressHasData {
                        TTLoadError(title: "Couldn’t load progress", message: LocalizedStringKey(performanceError)) {
                            Task { await reloadPerformance(forceErrorSurface: true) }
                        }
                        .padding(.vertical, 16)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if performanceError != nil {
                                // Stale data stays visible; the failure is a quiet notice.
                                TTStaleNotice { Task { await reloadPerformance(forceErrorSurface: true) } }
                            }
                            switch progressChip {
                            case .overview:
                                TraineeDetailAnalyticsSection(
                                    trainee: trainee,
                                    analytics: analytics,
                                    loadError: performanceError
                                )
                            case .history:
                                TraineeDetailHistorySection(trainee: trainee, analytics: analytics)
                            case .meals:
                                nutritionCard
                            case .form:
                                formCard
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Today

    private struct TodayRow: Identifiable {
        let id: String
        let name: String
        let prescription: String
        /// nil while nothing is logged yet.
        let logged: (done: Int, total: Int, weight: String?)?
    }

    private func weekdayName(_ weekday: Weekday) -> String {
        var calendar = Calendar.current
        calendar.locale = LocalizationController.shared.locale
        return calendar.weekdaySymbols[(weekday.sortIndex + 1) % 7]
    }

    /// Small Equatable fingerprint of the live session (the session type itself isn't Equatable).
    private var liveStamp: String? {
        store.liveSessionByTrainee[trainee.id].map { "\($0.id)|\($0.sets.count)|\($0.sets.last?.id ?? "")" }
    }

    /// Live session appeared / changed / ended. When it ends, the "Training now" card stays until the logs
    /// have reloaded, so "Not logged yet" never flashes; then it eases into the Finished (or rest) state.
    private func handleLiveChange() {
        if let live = store.liveSessionByTrainee[trainee.id] {
            lastLiveSession = live
            lingeringLive = nil
        } else if let ended = lastLiveSession {
            lastLiveSession = nil
            lingeringLive = ended
            Task {
                // The reload keeps running on its own; we only stop WAITING for it after the hold limit.
                let reload = Task { await reloadPerformance(forceErrorSurface: false) }
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await reload.value }
                    group.addTask { try? await Task.sleep(for: .seconds(Self.liveHoldLimit)) }
                    _ = await group.next()
                    group.cancelAll()
                }
                withAnimation(.easeInOut(duration: 0.2)) { lingeringLive = nil }
            }
        }
    }

    @ViewBuilder
    private var todayTab: some View {
        if let live = store.liveSessionByTrainee[trainee.id] ?? lingeringLive {
            // "Training now" takes priority over every other Today state.
            trainingNowCard(live: live)
        } else if let plan = currentAssignedPlan {
            todayContent(plan: plan)
        } else {
            // "No plan yet" + Assign plan.
            assignCard
        }
    }

    /// Honest states only: what the plan says for today and what today's log (if any) shows.
    /// The app cannot know whether a workout is in progress, so it never says so.
    private func todayContent(plan: WorkoutPlan) -> some View {
        let now = Date()
        let session = plan.session(on: now)
        // `store.logs(for:)` is newest first, so `first` is the LATEST log today when there are several.
        let todayLog = store.logs(for: trainee.id).first { Calendar.current.isDate($0.completedAt, inSameDayAs: now) }
        let loggedByExercise = Dictionary(grouping: todayLog?.sets ?? [], by: \.exerciseId)

        let rows: [TodayRow] = (session?.exercises ?? []).map { item in
            let name = store.exercise(id: item.exerciseId)?.name ?? String(localized: "Exercise")
            let prescription = Self.prescriptionText(item)
            var logged: (done: Int, total: Int, weight: String?)?
            if todayLog != nil, let sets = loggedByExercise[item.exerciseId], !sets.isEmpty {
                let top = sets.map(\.weightKg).max() ?? 0
                logged = (sets.count, max(item.sets, 1), top > 0 ? "\(top.cleanKg) kg" : nil)
            }
            return TodayRow(id: item.id, name: name, prescription: prescription, logged: logged)
        }

        return VStack(alignment: .leading, spacing: 12) {
            if let log = todayLog {
                finishedCard(log: log, session: session, rows: rows)
            } else if let session {
                notLoggedCard(session: session, rows: rows)
            } else {
                restDayCard(plan: plan, now: now)
            }
        }
    }

    // MARK: - Training now (live session)

    private struct LiveRow: Identifiable {
        let id: String
        let name: String
        let prescription: String?
        let done: Int
        let total: Int?
        let weight: String?
    }

    private func trainingNowCard(live: WorkoutSession) -> some View {
        let plan = currentAssignedPlan
        var day: PlanDay?
        var hint: String?
        if let plan, plan.id == live.planId {
            if let dayId = live.dayId {
                day = plan.days.first { $0.id == dayId }
                if day == nil { hint = String(localized: "The plan changed since this workout started, so only logged sets are shown.") }
            } else {
                day = plan.session(on: Date())
                if day == nil { hint = String(localized: "This workout doesn’t match a plan day, so only logged sets are shown.") }
            }
        } else {
            hint = String(localized: "The plan changed since this workout started, so only logged sets are shown.")
        }

        let setsByExercise = Dictionary(grouping: live.sets, by: \.exerciseId)
        func topWeight(_ id: String) -> String? {
            let top = (setsByExercise[id] ?? []).map(\.weightKg).max() ?? 0
            return top > 0 ? "\(top.cleanKg) kg" : nil
        }
        func name(_ id: String) -> String { store.exercise(id: id)?.name ?? String(localized: "Exercise") }

        let planned: [LiveRow] = (day?.exercises ?? []).map { item in
            LiveRow(
                id: "p-" + item.id,
                name: name(item.exerciseId),
                prescription: Self.prescriptionText(item),
                done: Set((setsByExercise[item.exerciseId] ?? []).map(\.setNumber)).count,
                total: max(item.sets, 1),
                weight: topWeight(item.exerciseId)
            )
        }
        // Sets for exercises that are not in the matched day (or all sets when there is no day).
        let plannedIds = Set((day?.exercises ?? []).map(\.exerciseId))
        var seen = Set<String>()
        let extraIds = live.sets.map(\.exerciseId).filter { !plannedIds.contains($0) && seen.insert($0).inserted }
        let extra: [LiveRow] = extraIds.map { id in
            LiveRow(id: "x-" + id, name: name(id), prescription: nil,
                    done: Set((setsByExercise[id] ?? []).map(\.setNumber)).count, total: nil, weight: topWeight(id))
        }

        let started = live.startedAt.formatted(date: .omitted, time: .shortened)
        let lastSet = live.sets.compactMap(\.finishedAt).max()
        // Last activity = latest set, else the start. Computed when the card is built (no timer).
        let idleSeconds = Date().timeIntervalSince(lastSet ?? live.startedAt)
        let isStale = idleSeconds > Self.staleLiveAfter
        let idleMinutes = max(Int((idleSeconds / 60).rounded()), 0)
        let pillText: String = isStale
            ? (lastSet != nil
                ? String(localized: "Session open · last set \(idleMinutes) min ago")
                : String(localized: "Session open · started \(idleMinutes) min ago"))
            : String(localized: "Training now · started \(started)")
        let pillSpoken: String = isStale
            ? (lastSet != nil
                ? String(localized: "Session open, last set \(idleMinutes) minutes ago")
                : String(localized: "Session open, started \(idleMinutes) minutes ago"))
            : String(localized: "Training now, started \(started)")
        let pillColor: Color = isStale ? Color(white: 0.5) : TTColor.success
        let progressLine: String = live.sets.isEmpty
            ? String(localized: "Just started")
            : [String(localized: "\(live.sets.count) sets logged"),
               lastSet.map { String(localized: "Last set \($0.formatted(date: .omitted, time: .shortened))") }]
                .compactMap { $0 }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day?.title ?? String(localized: "Workout"))
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    if let day {
                        Text("\(day.exercises.count) exercises")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
                Spacer(minLength: 8)
                // Static dot + words (never colour alone), no animation. Grey and "Session open" when stale.
                HStack(spacing: 6) {
                    Circle().fill(pillColor).frame(width: 8, height: 8)
                    Text(pillText)
                        .font(TTFont.caption(11))
                        .fontWeight(.bold)
                        .foregroundStyle(pillColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(pillColor.opacity(0.12))
                .clipShape(Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(pillSpoken)
            }

            Text(progressLine)
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)

            if let hint {
                Text(hint)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !planned.isEmpty {
                VStack(spacing: 8) { ForEach(planned) { liveRow($0) } }
            }
            if !extra.isEmpty {
                // Without a matched day everything is "extra"; the label only helps next to planned rows.
                if !planned.isEmpty {
                    Text("Extra")
                        .font(TTFont.workSans(13, weight: .bold))
                        .foregroundStyle(TTColor.inkMuted)
                        .padding(.top, 4)
                }
                VStack(spacing: 8) { ForEach(extra) { liveRow($0) } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Tick when all prescribed sets are logged, half-filled ring when partly done, empty ring when none.
    /// Never marks an exercise as "current" — the app cannot know that.
    private func liveRow(_ row: LiveRow) -> some View {
        let complete = row.total.map { row.done >= $0 } ?? (row.done > 0)
        let partial = !complete && row.done > 0
        let progress: String = {
            if let total = row.total {
                return row.weight.map { String(localized: "\(row.done) of \(total) sets · \($0)") }
                    ?? String(localized: "\(row.done) of \(total) sets")
            }
            return row.weight.map { String(localized: "\(row.done) sets · \($0)") } ?? String(localized: "\(row.done) sets")
        }()

        return HStack(spacing: 12) {
            ZStack {
                if complete {
                    Circle().fill(TTColor.success)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else if partial {
                    Circle().strokeBorder(TTColor.success, lineWidth: 2)
                    Circle().trim(from: 0.25, to: 0.75).fill(TTColor.success).padding(4)
                } else {
                    Circle().strokeBorder(Color(white: 0.78), lineWidth: 2)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                if let prescription = row.prescription {
                    Text(prescription)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            Spacer(minLength: 8)
            Text(progress)
                .font(TTFont.caption(12))
                .fontWeight(.semibold)
                .foregroundStyle(complete || partial ? TTColor.success : TTColor.inkSubtle)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .frame(minHeight: 44)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(row.prescription.map { $0 + ", " } ?? "")\(progress)")
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(TTFont.caption(11))
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func notLoggedCard(session: PlanDay, rows: [TodayRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("\(rows.count) exercises")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 8)
                statusPill(String(localized: "Not logged yet"), color: TTColor.inkMuted)
            }
            Text("Sets show here once \(firstName) finishes the workout.")
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            exerciseList(rows, hasLogToday: false)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func finishedCard(log: WorkoutLog, session: PlanDay?, rows: [TodayRow]) -> some View {
        let time = log.completedAt.formatted(date: .omitted, time: .shortened)
        let loggedCount = rows.filter { $0.logged != nil }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session?.title ?? String(localized: "Workout"))
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    if session != nil {
                        Text("\(loggedCount) of \(rows.count) exercises logged")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
                Spacer(minLength: 8)
                statusPill(String(localized: "Finished \(time) · \(log.durationMinutes) min"), color: TTColor.success)
            }
            if session != nil {
                exerciseList(rows, hasLogToday: true)
            } else {
                // Trained on a day the plan has no session for: show what the log itself contains.
                logOnlyList(log)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// "3 × 12 · 90s rest". With no rest time it is just "1 × 15" (never "0s rest").
    private static func prescriptionText(_ item: WorkoutExercise) -> String {
        if item.restSeconds > 0 {
            return String(localized: "\(item.sets) × \(item.reps) · \(item.restSeconds)s rest")
        }
        return String(localized: "\(item.sets) × \(item.reps)")
    }

    private func restDayCard(plan: WorkoutPlan, now: Date) -> some View {
        let next = plan.scheduledDays.isEmpty ? nil : plan.nextSession(from: now)
        let last = store.logs(for: trainee.id).first?.completedAt
        return VStack(alignment: .leading, spacing: 8) {
            Text(plan.scheduledDays.isEmpty ? "No schedule" : "Rest day")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(TTColor.ink)
            if let next {
                Text("Next: \(weekdayName(next.weekday)) · \(next.title)")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.ink)
            } else if plan.scheduledDays.isEmpty {
                Text("This plan has no scheduled days.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
            if let last {
                Text("Last workout: \(last.formatted(date: .abbreviated, time: .omitted))")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Text("No workouts logged")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func exerciseList(_ rows: [TodayRow], hasLogToday: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    // Tick when today's log has sets for it; otherwise an empty ring.
                    ZStack {
                        if row.logged != nil {
                            Circle().fill(TTColor.success)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle().strokeBorder(Color(white: 0.78), lineWidth: 2)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(TTFont.workSans(14, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                        Text(row.prescription)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer(minLength: 8)
                    if let logged = row.logged {
                        Text(logged.weight.map { String(localized: "\(logged.done) of \(logged.total) sets · \($0)") }
                             ?? String(localized: "\(logged.done) of \(logged.total) sets"))
                            .font(TTFont.caption(12))
                            .fontWeight(.semibold)
                            .foregroundStyle(TTColor.success)
                            .multilineTextAlignment(.trailing)
                    } else if hasLogToday {
                        Text("Not logged")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                }
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func logOnlyList(_ log: WorkoutLog) -> some View {
        let grouped = Dictionary(grouping: log.sets, by: \.exerciseId)
        let ids = log.sets.map(\.exerciseId).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(spacing: 8) {
            ForEach(ids, id: \.self) { id in
                let sets = grouped[id] ?? []
                let top = sets.map(\.weightKg).max() ?? 0
                HStack {
                    Text(store.exercise(id: id)?.name ?? String(localized: "Exercise"))
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                    Spacer(minLength: 8)
                    Text(top > 0 ? String(localized: "\(sets.count) sets · \(top.cleanKg) kg") : String(localized: "\(sets.count) sets"))
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Note sheet (same saveFeedback behaviour as the Feedback card)

    private var noteSheet: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(title: "Note", subtitle: displayName, background: .white)

            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // The last 3 notes next to the Note action; "Show all" needs no new data
                // (the store already holds every loaded note).
                let notes = store.feedback(for: trainee.id)
                if !notes.isEmpty {
                    sectionLabel("Previous notes")
                    ForEach(showAllNotes ? notes : Array(notes.prefix(3))) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.message)
                                .font(TTFont.body(14))
                                .foregroundStyle(TTColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkSubtle)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if notes.count > 3 {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { showAllNotes.toggle() }
                        } label: {
                            Text(showAllNotes ? "Show less" : "Show all")
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(TTColor.actionOrange)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Write a note for this trainee", text: $note, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($noteSheetFocused)
                    .tint(TTColor.actionOrange)
                    .padding(12)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(noteSheetFocused ? TTColor.actionOrange : Color.clear, lineWidth: 1.5)
                    )

                if let noteSheetError {
                    Text(noteSheetError)
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.danger)
                }

                let canSend = !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    Task {
                        // On failure the text stays, so nothing the coach wrote is lost.
                        if await sendFeedback() {
                            showNoteSheet = false
                        } else {
                            noteSheetError = String(localized: "Couldn’t send. Try again.")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Send feedback")
                            .font(TTFont.workSans(16, weight: .semibold))
                        TTIcon(icon: .paperPlaneDiagonal, filled: true, size: 14)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSend ? Color.black : Color(white: 0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, TTModalSheetChrome.contentTopPadding)
            .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.white)
        .onAppear { noteSheetFocused = true }
    }

    // MARK: - Progress chips

    private var progressChips: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TraineeProgressChip.allCases) { chip in
                        let on = progressChip == chip
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { progressChip = chip }
                        } label: {
                            Text(chip.title)
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(on ? Color.white : TTColor.ink)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(on ? Color.black : cardFill)
                                .clipShape(Capsule())
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if isRefreshingPerformance {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    /// The store already has data for the selected Progress chip (then no skeleton; refresh quietly).
    private var progressHasData: Bool {
        switch progressChip {
        case .overview: analytics != nil
        case .history: !store.logs(for: trainee.id).isEmpty || (analytics?.recentLogs.isEmpty == false)
        case .meals: !store.meals(for: trainee.id, on: selectedDay).isEmpty
        case .form: !store.formReports(for: trainee.id).isEmpty
        }
    }

    /// Placeholder card (same paddings and radii as the real cards) shown on the first load of a Progress chip.
    private var progressSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Section title").font(TTFont.workSans(15, weight: .bold))
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout").font(TTFont.workSans(15, weight: .bold))
                    Text(verbatim: "Nov 23, 2026 at 9:00 AM").font(TTFont.caption(12))
                    Text(verbatim: "12 sets · 3.4k kg").font(TTFont.caption(12))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .ttSkeleton()
    }

    private func reloadPerformance(forceErrorSurface: Bool) async {
        isRefreshingPerformance = true
        defer { isRefreshingPerformance = false; didLoadPerformance = true }
        do {
            try await store.refreshTraineePerformance(traineeId: trainee.id)
            performanceError = nil
        } catch let error as AppError where error == .unauthorized {
            performanceError = error.localizedDescription
        } catch let error as AppError {
            if case .notFound = error {
                performanceError = "This trainee isn’t available on your roster."
            } else if forceErrorSurface || analytics == nil {
                performanceError = error.localizedDescription
            }
        } catch {
            if forceErrorSurface || analytics == nil {
                performanceError = error.localizedDescription
            }
        }
    }

    /// One plan card: assigning / changing always goes through PlanQuickAssignSheet.
    private var assignCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if currentAssignedPlan == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No plan yet")
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    Text("Assign a plan so \(firstName) can start training. Their sessions will show up below.")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    openAssignSheet()
                } label: {
                    // Standard primary button (same as the assign sheet): label left, arrow right.
                    HStack(spacing: 8) {
                        Text("Assign plan")
                            .font(TTFont.workSans(16, weight: .bold))
                        Spacer(minLength: 8)
                        TTIcon(icon: .chevronRight, size: 14)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.98))
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func openAssignSheet() {
        previousPlanId = currentAssignedPlan?.id
        showAssignSheet = true
    }

    /// Same pattern as Home: toast after the sheet closes, Undo restores the previous state.
    private func showAssignedToast() {
        guard let newPlan = store.assignedPlan(for: trainee) else { return }
        let first = displayName.split(separator: " ").first.map(String.init) ?? displayName
        let previous = previousPlanId
        feedbackToast = TTToastMessage(
            text: "“\(newPlan.title)” assigned to \(first)",
            action: TTToastAction(title: "Undo") {
                Task {
                    do {
                        if let previous {
                            try await store.assign(planId: previous, to: trainee.id)
                        } else {
                            try await store.unassign(planId: newPlan.id, from: trainee.id)
                        }
                        feedbackToast = TTToastMessage(text: "Undone")
                    } catch {
                        feedbackToast = TTToastMessage(text: "Couldn’t undo", style: .error, subtitle: error.localizedDescription)
                    }
                }
            }
        )
    }

    // MARK: - Plan tab

    private func weekRow(_ training: Set<Weekday>) -> some View {
        var calendar = Calendar.current
        calendar.locale = LocalizationController.shared.locale
        let veryShort = calendar.veryShortStandaloneWeekdaySymbols // index 0 = Sunday
        let short = calendar.shortStandaloneWeekdaySymbols
        let today = Weekday.from(date: Date())
        let names = Weekday.allCases.filter { training.contains($0) }.map { short[($0.sortIndex + 1) % 7] }.joined(separator: ", ")

        return HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let on = training.contains(day)
                Text(veryShort[(day.sortIndex + 1) % 7])
                    .font(TTFont.workSans(10, weight: .bold))
                    .foregroundStyle(on ? Color.white : TTColor.inkSubtle)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(on ? Color.black : Color.clear))
                    .overlay(Circle().strokeBorder(on ? Color.clear : TTColor.ink.opacity(0.15), lineWidth: 1))
                    // Today is ringed, whether or not it is a training day.
                    .overlay(Circle().strokeBorder(day == today ? TTColor.actionOrange : Color.clear, lineWidth: 2).padding(-3))
            }
        }
        .padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Training days: \(names)"))
    }

    private func planTab(plan: WorkoutPlan) -> some View {
        let status = store.planFollowStatus(traineeId: trainee.id, plan: plan)
        let adherence = store.planAdherencePercent(traineeId: trainee.id, plan: plan)
        let statusColor = followStatusColor(status)
        let last = store.lastPlanWorkoutDate(traineeId: trainee.id, planId: plan.id)
        let assignedAt = store.assignments
            .filter { $0.traineeId == trainee.id && $0.planId == plan.id }
            .map(\.assignedAt)
            .max()
        let trainingDays = Set(plan.scheduledDays.map(\.weekday))

        // "level · N days a week · assigned <date>" — empty parts are skipped, so no dangling "·".
        var parts: [String] = []
        let level = plan.level.trimmingCharacters(in: .whitespacesAndNewlines)
        if !level.isEmpty { parts.append(level) }
        if plan.daysPerWeek > 0 { parts.append(String(localized: "\(plan.daysPerWeek) days a week")) }
        if let assignedAt { parts.append(String(localized: "Assigned \(assignedAt.formatted(date: .abbreviated, time: .omitted))")) }
        let subtitle = parts.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.title)
                            .font(TTFont.workSans(17, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(TTFont.body(13))
                                .foregroundStyle(TTColor.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    // "Due today" lives on the Today tab.
                    if status != .dueToday {
                        Text(status.title)
                            .font(TTFont.caption(11))
                            .fontWeight(.bold)
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if !trainingDays.isEmpty {
                    weekRow(trainingDays)
                }

                HStack(spacing: 10) {
                    Text("\(adherence)% follow")
                        .font(TTFont.caption(12))
                        .fontWeight(.semibold)
                        .foregroundStyle(TTColor.inkMuted)
                    Text("·")
                        .foregroundStyle(TTColor.inkSubtle)
                    if let last {
                        Text("Last \(last.formatted(date: .abbreviated, time: .omitted))")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    } else {
                        Text("No workouts logged")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }

                Button {
                    openAssignSheet()
                } label: {
                    Text("Change plan")
                        .font(TTFont.workSans(14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button {
                        viewedPlan = plan
                    } label: {
                        Text("View full plan")
                            .font(TTFont.workSans(13, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Danger, text style; the existing confirm dialog does the rest.
                    Button {
                        unassignConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            if isUnassigning {
                                ProgressView()
                            } else {
                                Text("Unassign plan…")
                                    .font(TTFont.workSans(13, weight: .bold))
                            }
                        }
                        .foregroundStyle(TTColor.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnassigning)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if plan.scheduledDays.isEmpty {
                sectionLabel("Exercises")
                VStack(spacing: 8) {
                    ForEach(plan.exercises) { exercise in planExerciseRow(exercise) }
                }
            } else {
                sectionLabel("Plan days")
                VStack(spacing: 8) {
                    ForEach(plan.scheduledDays) { day in planDayRow(day) }
                }
            }
        }
    }

    private func planExerciseRow(_ item: WorkoutExercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(store.exercise(id: item.exerciseId)?.name ?? String(localized: "Exercise"))
                .font(TTFont.workSans(14, weight: .semibold))
                .foregroundStyle(TTColor.ink)
            Spacer(minLength: 8)
            Text(Self.prescriptionText(item))
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func planDayRow(_ day: PlanDay) -> some View {
        let expanded = expandedDayIds.contains(day.id)
        // A time only when the plan really has one — never "Time TBD".
        let time = day.startTime.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.clockDisplay }

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if expanded { expandedDayIds.remove(day.id) } else { expandedDayIds.insert(day.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(weekdayName(day.weekday) + (time.map { " · \($0)" } ?? ""))
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                        Text(day.title)
                            .font(TTFont.workSans(15, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Text("\(day.exercises.count) exercises")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TTColor.inkSubtle)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(expanded ? .isSelected : [])

            if expanded {
                VStack(spacing: 6) {
                    ForEach(day.exercises) { exercise in planExerciseRow(exercise) }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func followStatusColor(_ status: PlanFollowStatus) -> Color {
        switch status {
        case .trainedToday: TTColor.success
        case .following: TTColor.actionOrange
        case .dueToday: Color(red: 0.95, green: 0.55, blue: 0.15)
        case .behind: TTColor.danger
        case .notStarted: TTColor.inkMuted
        }
    }

    private func unassignCurrentPlan() async {
        guard let plan = currentAssignedPlan else { return }
        isUnassigning = true
        defer { isUnassigning = false }
        do {
            try await store.unassign(planId: plan.id, from: trainee.id)
            TTAssignSuccessFeedback.playUnassign(toast: $feedbackToast, traineeName: displayName)
        } catch {
            feedbackToast = TTToastMessage(
                text: "Couldn’t unassign",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func removeFromRoster() async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        do {
            try await store.removeTrainee(traineeId: trainee.id)
            feedbackToast = TTToastMessage(
                text: "\(displayName) removed from roster",
                style: .success
            )
            // Brief pause so the success toast is visible before dismiss.
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        } catch {
            let detail = (error as? AppError)?.errorDescription
                ?? error.localizedDescription
            feedbackToast = TTToastMessage(
                text: detail.isEmpty ? "Couldn't remove trainee" : detail,
                style: .error
            )
        }
    }

    @MainActor
    private func consumeMealDeepLink() async {
        guard let target = TTMealDeepLink.pending, target.traineeId == trainee.id else { return }
        TTMealDeepLink.pending = nil
        selectedTab = .progress
        progressChip = .meals
        // The notification carries the meal id only; find its day once today's list is fresh.
        // TODO: the event/notification has no meal date; a meal logged for another day opens on today.
        await store.refreshDay(for: trainee.id, on: Date())
        if let mealId = target.mealId,
           let meal = store.meals.first(where: { $0.id == mealId && $0.traineeId == trainee.id }) {
            selectedDay = meal.eatenAt
        } else {
            selectedDay = Date()
        }
    }

    private var nutritionCard: some View {
        let macros = store.dailyMacros(for: trainee.id, on: selectedDay)
        // The trainer sees what was eaten only (planned entries stay private for now).
        let meals = store.meals(for: trainee.id, on: selectedDay)
            .filter { !$0.isPlanned }
            .sorted { $0.eatenAt < $1.eatenAt }
        let target = trainee.dailyCalorieTarget
        let diff = macros.calories - target
        let isOver = target > 0 && diff > 0
        let progress = target > 0 ? min(1.0, Double(macros.calories) / Double(target)) : 0

        return VStack(alignment: .leading, spacing: 12) {
            TTWeekStrip(selected: $selectedDay)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    if target > 0 {
                        Text(verbatim: "\(macros.calories.formatted()) / \(target.formatted()) kcal")
                            .font(TTFont.workSans(16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(TTColor.ink)
                        Spacer(minLength: 4)
                        Text(isOver
                             ? "\(diff.formatted()) over"
                             : "\(abs(diff).formatted()) under")
                            .font(TTFont.workSans(11, weight: .semibold))
                            .foregroundStyle(isOver ? Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255) : Color(red: 22 / 255, green: 101 / 255, blue: 52 / 255))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isOver ? Color(red: 253 / 255, green: 236 / 255, blue: 236 / 255) : Color(red: 228 / 255, green: 245 / 255, blue: 233 / 255))
                            .clipShape(Capsule())
                    } else {
                        Text("\(macros.calories) kcal eaten")
                            .font(TTFont.workSans(16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(TTColor.ink)
                    }
                }

                if target > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255))
                            Capsule()
                                .fill(isOver ? Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255) : TTColor.actionOrange)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                }

                HStack(spacing: 12) {
                    compactMacro("Protein", macros.protein, TTColor.protein)
                    compactMacro("Carbs", macros.carbs, TTColor.carbs)
                    compactMacro("Fat", macros.fat, TTColor.fat)
                }
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if meals.isEmpty {
                Text("No meals logged on this day")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
            ForEach(meals) { meal in
                // Same row as the trainee's own list (read-only here); tap opens the detail.
                TTMealRow(meal: meal, onTap: { detailMeal = meal })
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func compactMacro(_ title: LocalizedStringKey, _ value: Double, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(title)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            Text(verbatim: "\(Int(value.rounded())) g")
                .font(TTFont.workSans(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(TTColor.ink)
        }
    }

    private var formCard: some View {
        let reports = store.formReports(for: trainee.id)
        return VStack(alignment: .leading, spacing: 12) {
            if reports.isEmpty {
                Text("No live form sessions yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(store.exercise(id: report.exerciseId)?.name ?? "Exercise")
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(TTColor.ink)
                            Spacer()
                            HStack(spacing: 6) {
                                Text("\(report.score)/100")
                                    .font(TTFont.workSans(16, weight: .bold))
                                    .foregroundStyle(report.score >= 80 ? TTColor.success : TTColor.actionOrange)
                                Text(report.score >= 80 ? "Good" : report.score >= 60 ? "Fair" : "Needs work")
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(TTColor.inkMuted)
                            }
                        }
                        Text(report.cues.joined(separator: " · "))
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Keeps the text on failure so nothing the coach wrote is lost.
    @discardableResult
    private func sendFeedback() async -> Bool {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trainer = store.currentTrainer, !text.isEmpty else { return false }
        do {
            try await store.saveFeedback(
                TrainerFeedback(
                    id: UUID().uuidString,
                    trainerId: trainer.id,
                    traineeId: trainee.id,
                    message: text,
                    createdAt: .now,
                    relatedExerciseId: nil
                )
            )
            note = ""
            feedbackToast = TTToastMessage(text: "Note sent to \(firstName)")
            return true
        } catch {
            feedbackToast = TTToastMessage(text: "Couldn’t send. Try again.", style: .error)
            return false
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(TTFont.workSans(15, weight: .bold))
            .foregroundStyle(TTColor.ink)
            .padding(.top, 4)
    }
}

#Preview("Trainee Detail") {
    NavigationStack {
        TraineeDetailView(trainee: TTPreview.sampleTrainee)
            .ttPreviewTrainer()
    }
}
