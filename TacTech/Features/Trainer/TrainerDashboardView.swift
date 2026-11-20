import SwiftUI

struct TrainerDashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.selectTrainerTab) private var selectTrainerTab
    @State private var showProfile = false
    @State private var showNotifications = false
    @State private var showJoinRequests = false
    @State private var isLoadingJoinRequests = true
    @State private var showAssignSheet = false
    @State private var assignTrainee: TraineeProfile?
    @State private var detailTrainee: TraineeProfile?
    @State private var previousPlanId: String?
    @State private var toast: TTToastMessage?
    @State private var chatTarget: TTChatTarget?
    @State private var showCreate = false
    @State private var showRoster = false
    @Bindable private var notificationStore = NotificationStore.shared
    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let blue   = Color(red: 37  / 255, green: 99  / 255, blue: 235 / 255)
    private let amber  = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    private let green  = Color(red: 34  / 255, green: 197 / 255, blue: 94  / 255)
    private let canvas = Color.white

    var body: some View {
        #if DEBUG || PERF_TEMP
        let _ = PerfTemp.trace("TrainerDashboardView") { Self._printChanges() } // PERF-TEMP
        #endif
        NavigationStack {
            // Header is drawn over the scroll view; content size never depends on its collapse.
            TTCollapsingHeaderScreen(
                sheetFill: canvas,
                onRefresh: {
                    await TrainerLiveSync.refresh(store: store, force: true)
                    await store.fetchTrainerJoinRequests()
                },
                header: { progress in darkHeader(progress: progress) }
            ) {
                VStack(alignment: .leading, spacing: 16) {

                    // What needs doing right now — the only thing on Home
                    actionList
                        .ttHomeAppear(index: 0)
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
            .background(Color.black.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .ttSyncRootTabBarWithNavigationDepth()
            .sheet(isPresented: $showProfile) {
                TrainerProfileView(showsBack: true)
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsInboxView()
                    .ttModalSheetPresentation()
            }
            .sheet(isPresented: $showJoinRequests) {
                JoinRequestsView()
                    .ttModalSheetPresentation()
            }
            .sheet(isPresented: $showAssignSheet) {
                PlanQuickAssignSheet()
                    .ttModalSheetPresentation()
            }
            .sheet(isPresented: $showRoster) {
                // Roster pre-filtered to Today; closing returns to Home.
                MyTraineesView(initialFilter: .today)
                    .ttModalSheetPresentation()
            }
            .navigationDestination(item: $detailTrainee) { trainee in
                TraineeDetailView(trainee: trainee)
            }
            .sheet(item: $assignTrainee) { trainee in
                PlanQuickAssignSheet(preselectedTraineeId: trainee.id, onAssigned: {
                    showAssignedToast(for: trainee)
                })
                .ttModalSheetPresentation()
            }
            .ttToast($toast)
            .fullScreenCover(item: $chatTarget) { target in
                HumanPeerChatView(audience: .trainer, preferredPeerUserId: target.id)
            }
            .sheet(isPresented: $showCreate) {
                CreatePlanView()
                    .ttModalSheetPresentation()
            }
            .task {
                isLoadingJoinRequests = true
                await store.fetchTrainerJoinRequests()
                isLoadingJoinRequests = false
                // Home shows "Completed today" per trainee — don't rely on launch-time logs.
                await TrainerLiveSync.refresh(store: store)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttJoinRequestRealtime)) { note in
                let type = (note.userInfo?["type"] as? String) ?? ""
                Task { await store.handleJoinRequestRealtime(type: type) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttOpenJoinRequests)) { _ in
                showJoinRequests = true
            }
        }
    }

    // MARK: - Header

    private func darkHeader(progress: CGFloat) -> some View {
        TTHomeProfileHeader(
            name: firstName,
            avatarSymbol: store.displayAvatarAsset,
            avatarUrl: store.remoteAvatarURL,
            avatarUserId: store.session?.userId,
            badgeCount: notificationStore.unreadCount,
            showsAIPro: store.aiEntitlement?.active == true,
            metrics: [],
            collapseProgress: progress,
            onProfileTap: {
                TTHomeHaptics.light()
                showProfile = true
            },
            onNotificationTap: {
                TTHomeHaptics.light()
                showNotifications = true
            }
        )
    }

    // MARK: - Action list (the only thing on Home)

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Each trainee's status is worked out ONCE per redraw; everything below reads this lookup.
            let roster = clients
            let today = Date()
            let statuses = statusLookup(for: roster, today: today)
            let attention = attentionItems(queue: actionQueue(roster: roster, statuses: statuses))
            let training = trainingToday(roster: roster, statuses: statuses, today: today)
            let pendingJoins = store.trainerJoinRequests.filter(\.isPending)
            let total = attention.count + (pendingJoins.isEmpty ? 0 : 1)

            if roster.isEmpty {
                if !pendingJoins.isEmpty { joinRequestsCard(pendingJoins) }
                emptyRosterCard
            } else {
                if total == 0 {
                    allClearCard
                } else {
                    // Section title
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(total) thing\(total == 1 ? "" : "s") to do")
                            .font(TTFont.workSans(20, weight: .bold))
                            .foregroundStyle(.black)
                        Spacer()
                        Text(Date(), format: .dateTime.weekday(.wide))
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    .padding(.bottom, 4)

                    // Join requests first, then each card with ONE real action.
                    if !pendingJoins.isEmpty {
                        joinRequestsCard(pendingJoins)
                    }
                    ForEach(attention) { item in
                        actionCard(item)
                    }
                }

                // One summary card instead of a second roster; the list lives in My Trainees (Today filter).
                if !training.isEmpty {
                    trainingSummaryCard(training, statuses: statuses)
                }
            }
        }
    }

    // MARK: - Action card (ONE button, ONE job)

    private func actionCard(_ item: QueueItem) -> some View {
        Button {
            detailTrainee = item.trainee
        } label: {
            HStack(spacing: 0) {
                // Colour strip = urgency at a glance
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(item.tint)
                    .frame(width: 4)
                    .padding(.vertical, 12)
                    .padding(.leading, 4)

                HStack(spacing: 12) {
                    TTAvatar(
                        name: store.user(forTrainee: item.trainee)?.name ?? "T",
                        size: 46
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.priority == 0 ? "NEEDS A CHECK-IN" : "NO PLAN")
                            .font(TTFont.workSans(11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(item.priority == 0 ? amber : Color(white: 0.5))
                        Text(store.user(forTrainee: item.trainee)?.name ?? "Trainee")
                            .font(TTFont.textLG(.bold))
                            .foregroundStyle(.black)
                        Text(item.detail)
                            .font(TTFont.textSM(.medium))
                            .foregroundStyle(Color(white: 0.45))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    // The one action for this card
                    actionButton(item)
                }
                .padding(.vertical, 14)
                .padding(.trailing, 14)
                .padding(.leading, 10)
            }
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(item.tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(TTHomeCardPressStyle())
        // Sibling of the card button, so the two taps can never both fire.
        .overlay(alignment: .trailing) {
            let name = store.user(forTrainee: item.trainee)?.name ?? "trainee"
            if item.priority == 0 {
                Button {
                    openMessage(item.trainee)
                } label: {
                    actionPill("Message")
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
                .accessibilityLabel("Message \(name)")
            } else if item.priority == 2 {
                Button {
                    previousPlanId = store.assignedPlan(for: item.trainee)?.id
                    assignTrainee = item.trainee
                } label: {
                    actionPill("Assign plan")
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
                .accessibilityLabel("Assign plan to \(name)")
            }
        }
    }

    /// Prefills a friendly opener only when the coach has no draft yet; never sends.
    private func openMessage(_ trainee: TraineeProfile) {
        let peerId = TTTraineeChatOpener.prepare(for: trainee, name: store.user(forTrainee: trainee)?.name)
        chatTarget = TTChatTarget(id: peerId)
    }

    /// Toast after the assign sheet closes, with Undo back to the previous state.
    private func showAssignedToast(for trainee: TraineeProfile) {
        guard let newPlan = store.assignedPlan(for: trainee) else { return }
        let name = store.user(forTrainee: trainee)?.name ?? "Trainee"
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let previous = previousPlanId
        toast = TTToastMessage(
            text: "“\(newPlan.title)” assigned to \(first)",
            action: TTToastAction(title: "Undo") {
                Task {
                    do {
                        if let previous {
                            try await store.assign(planId: previous, to: trainee.id)
                        } else {
                            try await store.unassign(planId: newPlan.id, from: trainee.id)
                        }
                        toast = TTToastMessage(text: "Undone")
                    } catch {
                        toast = TTToastMessage(text: "Couldn’t undo", style: .error, subtitle: error.localizedDescription)
                    }
                }
            }
        )
    }

    /// Standard small black action button (44pt min tap area).
    private func actionPill(_ title: String) -> some View {
        Text(title)
            .font(TTFont.textXS(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black)
            .clipShape(Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    /// Invisible spacer that reserves room for the overlaid real button.
    @ViewBuilder
    private func actionButton(_ item: QueueItem) -> some View {
        switch item.priority {
        case 0: actionPill("Message").hidden()
        case 2: actionPill("Assign plan").hidden()
        default: EmptyView()
        }
    }

    // MARK: - Training today / You did today rows

    private func trainingSummaryCard(
        _ rows: [(trainee: TraineeProfile, title: String, done: Bool)],
        statuses: [String: TraineeTodayStatus]
    ) -> some View {
        let total = rows.count
        let done = rows.filter(\.done).count
        let progress = total == 0 ? 0 : CGFloat(done) / CGFloat(total)
        // Not done first, done last, otherwise the existing order; at most 4 rows.
        let ordered = rows.filter { !$0.done } + rows.filter(\.done)
        let visible = Array(ordered.prefix(4))

        return VStack(alignment: .leading, spacing: 0) {
            // Header: tapping it opens the roster on Today.
            Button {
                TTHomeHaptics.light()
                showRoster = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Training today")
                            .textCase(.uppercase)
                            .font(TTFont.workSans(11, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(Color(white: 0.5))
                        Spacer(minLength: 8)
                        TTIcon(icon: .chevronRight, size: 14)
                            .foregroundStyle(Color(white: 0.55))
                    }

                    Text("\(done) of \(total) done")
                        .font(TTFont.workSans(20, weight: .bold))
                        .foregroundStyle(.black)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.90))
                            Capsule().fill(green).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(TTHomeCardPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Training today, \(done) of \(total) done"))
            .accessibilityHint(Text("Opens your trainees."))
            .accessibilityAddTraits(.isButton)

            ForEach(visible, id: \.trainee.id) { row in
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.horizontal, 16)
                todayTraineeRow(row, status: statuses[row.trainee.id] ?? TraineeTodayStatus.none)
            }

            if rows.count > 4 {
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.horizontal, 16)
                Button {
                    TTHomeHaptics.light()
                    showRoster = true
                } label: {
                    HStack {
                        Text("See all trainees")
                            .font(TTFont.workSans(15, weight: .semibold))
                        Spacer(minLength: 8)
                        TTIcon(icon: .chevronRight, size: 14)
                    }
                    .foregroundStyle(TTColor.actionOrange)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.top, 12)
    }

    /// One trainee training today: name, session title (only what the status helper gives), done indicator.
    private func todayTraineeRow(_ row: (trainee: TraineeProfile, title: String, done: Bool), status: TraineeTodayStatus) -> some View {
        let name = store.user(forTrainee: row.trainee)?.name ?? String(localized: "Trainee")
        // TODO: done rows have no session title from the status helper, so they show none.
        var session = ""
        if case .sessionToday(let title) = status { session = title }

        return Button {
            detailTrainee = row.trainee
        } label: {
            HStack(spacing: 12) {
                TTAvatar(name: name, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(TTFont.workSans(16, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    if !session.isEmpty {
                        Text(session)
                            .font(TTFont.workSans(13, weight: .regular))
                            .foregroundStyle(Color(white: 0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // Done = green filled circle with a white check; not yet = empty grey ring.
                ZStack {
                    if row.done {
                        Circle().fill(green)
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Color(white: 0.78), lineWidth: 2)
                    }
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.isEmpty ? name : "\(name), \(session)")
        .accessibilityValue(row.done ? Text("Done") : Text("Not done yet"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Empty states

    private var emptyRosterCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No trainees yet")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(.black)
            Text("Share your invite code so trainees can join. Once they join, they appear here.")
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)

            if let code = store.currentTrainer?.inviteCode {
                HStack(spacing: 10) {
                    Text(code)
                        .font(TTFont.workSans(15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .textSelection(.enabled)
                    Spacer()
                    TTCopyCodeButton(code: code) { copied in
                        TTCopyCodeLabel(copied: copied, font: TTFont.textSM(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(orange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(TTHomeCardPressStyle())
                }
                .padding(16)
                .background(Color(white: 0.96))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(20)
        .background(Color(white: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(white: 0.9), lineWidth: 1)
        )
    }

    private var allClearCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(green)
            Text("You're all caught up")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(.black)
            Text("All \(clients.count) trainees are on track. Check back tomorrow.")
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color(white: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(green.opacity(0.25), lineWidth: 1.5)
        )
    }

    // MARK: - Join requests card

    /// Same card anatomy as the attention cards: tag, names, one "Review" button.
    private func joinRequestsCard(_ requests: [JoinRequestDTO]) -> some View {
        let names = requests.compactMap { $0.trainee?.name }.filter { !$0.isEmpty }
        let shown = names.prefix(2).joined(separator: ", ")
        let extra = requests.count - min(names.count, 2)
        let line = shown.isEmpty
            ? "\(requests.count) waiting for your approval"
            : extra > 0 ? "\(shown) + \(extra) more" : shown
        return Button {
            showJoinRequests = true
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(orange)
                    .frame(width: 4)
                    .padding(.vertical, 12)
                    .padding(.leading, 4)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JOIN REQUESTS")
                            .font(TTFont.workSans(11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(orange)
                        Text(line)
                            .font(TTFont.textLG(.bold))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    actionPill("Review")
                }
                .padding(.vertical, 14)
                .padding(.trailing, 14)
                .padding(.leading, 10)
            }
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(orange.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(TTHomeCardPressStyle())
        .accessibilityLabel("Review join requests: \(line)")
    }

    // MARK: - Data

    private var firstName: String {
        store.currentUser?.name.components(separatedBy: " ").first ?? "Coach"
    }

    private var clients: [TraineeProfile] {
        store.currentTrainer.map { store.trainees(for: $0) } ?? []
    }

    private var activePlanCount: Int {
        clients.filter { store.assignedPlan(for: $0) != nil }.count
    }

    private var formAvgLabel: String {
        let reports = clients.flatMap { store.formReports(for: $0.id) }
        guard !reports.isEmpty else { return "—" }
        let avg = reports.map(\.score).reduce(0, +) / reports.count
        return "\(avg)%"
    }

    private struct QueueItem: Identifiable {
        var id: String { trainee.id }
        let trainee: TraineeProfile
        let detail: String
        let tint: Color
        let priority: Int  // 0=check-in, 1=session today, 2=no plan, 3=done
        var inactiveDays: Int? = nil
    }

    /// Check-ins (longest inactive first, never-logged first of all), then no plan.
    private func attentionItems(queue: [QueueItem]) -> [QueueItem] {
        let checkIns = queue.filter { $0.priority == 0 }
            .sorted { ($0.inactiveDays ?? .max) > ($1.inactiveDays ?? .max) }
        return checkIns + queue.filter { $0.priority == 2 }
    }

    /// One status per trainee, computed once per redraw.
    private func statusLookup(for roster: [TraineeProfile], today: Date) -> [String: TraineeTodayStatus] {
        Dictionary(roster.map { ($0.id, todayStatus($0, today: today)) }, uniquingKeysWith: { first, _ in first })
    }

    private func todayStatus(_ trainee: TraineeProfile, today: Date) -> TraineeTodayStatus {
        TraineeTodayStatus.make(
            plan: store.assignedPlan(for: trainee),
            logs: store.logs(for: trainee.id),
            today: today
        )
    }

    /// Trainees with a session today or who already trained today.
    private func trainingToday(
        roster: [TraineeProfile],
        statuses: [String: TraineeTodayStatus],
        today: Date
    ) -> [(trainee: TraineeProfile, title: String, done: Bool)] {
        roster.compactMap { trainee in
            let status = statuses[trainee.id] ?? TraineeTodayStatus.none
            guard status.isTrainingToday else { return nil }
            // A session today already carries its title; only "done" rows need the plan lookup.
            if case .sessionToday(let title) = status { return (trainee, title, false) }
            let plan = store.assignedPlan(for: trainee)
            return (trainee, plan?.session(on: today)?.title ?? plan?.title ?? "Workout", status == .doneToday)
        }
    }

    private func actionQueue(roster: [TraineeProfile], statuses: [String: TraineeTodayStatus]) -> [QueueItem] {
        roster.compactMap { trainee -> QueueItem? in
            switch statuses[trainee.id] ?? TraineeTodayStatus.none {
            case .doneToday:
                return QueueItem(trainee: trainee, detail: "Completed today's session", tint: green, priority: 3)
            case .sessionToday(let title):
                return QueueItem(trainee: trainee, detail: title, tint: orange, priority: 1)
            case .noPlan:
                return QueueItem(trainee: trainee, detail: "No workout plan assigned", tint: Color(white: 0.25), priority: 2)
            case .inactive(let days):
                let wait = days.map { "\($0) days without a log" } ?? "No logs yet"
                return QueueItem(trainee: trainee, detail: wait, tint: amber, priority: 0, inactiveDays: days)
            case .none:
                return nil
            }
        }
        .sorted { $0.priority < $1.priority }
    }
}

// MARK: - Trainee status for today (shared by Home and the roster)

/// One definition of "where is this trainee today". Pure: no store access.
/// Precedence matches Home's action queue: done today > session today > no plan > check-in > none.
/// Shared by Trainer Home and the trainee profile: prepares a chat with a trainee.
/// Prefills a friendly opener only when the coach has no draft yet; never sends. Returns the peer id —
/// the trainee's USER id (not the profile id), which is what `HumanPeerChatView(preferredPeerUserId:)` expects.
@MainActor
enum TTTraineeChatOpener {
    static func prepare(for trainee: TraineeProfile, name: String?) -> String {
        let peerId = trainee.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trainee.id : trainee.userId
        let name = name ?? "there"
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let existing = HumanChatStore.shared.drafts[peerId] ?? ""
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let draft = "Hi \(first), how’s training going?"
            HumanChatStore.shared.drafts[peerId] = draft
            if !trainee.id.isEmpty {
                HumanChatStore.shared.drafts[trainee.id] = draft
            }
        }
        return peerId
    }
}

enum TraineeTodayStatus: Equatable {
    case doneToday
    /// Only when the assigned plan has a day scheduled for today's weekday; `title` is that day's title.
    case sessionToday(title: String)
    /// Has a plan, nothing today, and no log for 3+ days (`days == nil` → never logged).
    case inactive(days: Int?)
    case noPlan
    case none

    /// Home's "Training today" count and the roster's Today filter both use this.
    var isTrainingToday: Bool {
        switch self {
        case .doneToday, .sessionToday: return true
        default: return false
        }
    }

    /// Days without a log that make a trainee a check-in.
    static let checkInThresholdDays = 3

    static func make(plan: WorkoutPlan?, logs: [WorkoutLog], today: Date) -> TraineeTodayStatus {
        let calendar = Calendar.current
        if logs.contains(where: { calendar.isDate($0.completedAt, inSameDayAs: today) }) {
            return .doneToday
        }
        if let session = plan?.session(on: today) {
            return .sessionToday(title: session.title)
        }
        if plan == nil { return .noPlan }
        let days: Int? = logs.map(\.completedAt).max().flatMap {
            calendar.dateComponents([.day], from: $0, to: today).day
        }
        if days == nil || (days ?? 0) >= checkInThresholdDays {
            return .inactive(days: days)
        }
        return .none
    }
}

#Preview("Trainer Home") {
    TrainerDashboardView()
        .ttPreviewTrainer()
}
