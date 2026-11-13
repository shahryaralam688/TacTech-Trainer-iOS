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
    @State private var showChat = false
    @State private var chatPeerUserId: String?
    @State private var showCreate = false
    @Bindable private var notificationStore = NotificationStore.shared
    @StateObject private var scrollCollapse: TTHomeScrollCollapseModel = {
        let model = TTHomeScrollCollapseModel()
        model.layoutTravel = TTHomeHeaderCollapse.homeLayoutTravel
        return model
    }()

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let blue   = Color(red: 37  / 255, green: 99  / 255, blue: 235 / 255)
    private let amber  = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    private let green  = Color(red: 34  / 255, green: 197 / 255, blue: 94  / 255)
    private let canvas = Color.white

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                darkHeader

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TTHomeScrollCollapseProbe(model: scrollCollapse, space: "trainerHome")

                        VStack(alignment: .leading, spacing: 16) {

                            // What needs doing right now — the only thing on Home
                            actionList
                                .ttHomeAppear(index: 0)
                        }
                        .padding(.horizontal, TTSpace.screen)
                        .padding(.top, 20)
                        .padding(.bottom, 48)
                    }
                }
                .refreshable {
                    await TrainerLiveSync.refresh(store: store, force: true)
                    await store.fetchTrainerJoinRequests()
                }
                .ttTopRoundedSheet(
                    radius: TTSheetChrome.homeTopRadius(collapseProgress: scrollCollapse.progress),
                    fill: canvas
                )
                .ttObserveHomeScrollCollapse(scrollCollapse, space: "trainerHome")
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
            .fullScreenCover(isPresented: $showChat) {
                HumanPeerChatView(audience: .trainer, preferredPeerUserId: chatPeerUserId)
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

    private var darkHeader: some View {
        TTHomeProfileHeader(
            name: firstName,
            avatarSymbol: store.displayAvatarAsset,
            avatarUrl: store.remoteAvatarURL,
            avatarUserId: store.session?.userId,
            badgeCount: notificationStore.unreadCount,
            showsAIPro: store.aiEntitlement?.active == true,
            metrics: [],
            collapseProgress: scrollCollapse.progress,
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
            let attention = attentionItems
            let training = trainingToday
            let pendingJoins = store.trainerJoinRequests.filter(\.isPending)
            let total = attention.count + (pendingJoins.isEmpty ? 0 : 1)

            if clients.isEmpty {
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

                if !training.isEmpty {
                    sectionHeader(
                        "Training today",
                        subtitle: "\(training.filter(\.done).count) of \(training.count) done"
                    )
                    ForEach(training, id: \.trainee.id) { row in
                        trainingRow(row.trainee, title: row.title, done: row.done)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(.black)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
        .padding(.top, 12)
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
        let peerId = trainee.userId
        let name = store.user(forTrainee: trainee)?.name ?? "there"
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let existing = HumanChatStore.shared.drafts[peerId] ?? ""
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HumanChatStore.shared.drafts[peerId] = "Hi \(first), how’s training going?"
        }
        chatPeerUserId = peerId
        showChat = true
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

    private func trainingRow(_ trainee: TraineeProfile, title: String, done: Bool) -> some View {
        Button {
            detailTrainee = trainee
        } label: {
            HStack(spacing: 12) {
                TTAvatar(name: store.user(forTrainee: trainee)?.name ?? "T", size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.user(forTrainee: trainee)?.name ?? "Trainee")
                        .font(TTFont.textMD(.semibold))
                        .foregroundStyle(.black)
                    Text(title)
                        .font(TTFont.textSM(.medium))
                        .foregroundStyle(Color(white: 0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Only "Done" is knowable from logs; never show "In progress".
                if done {
                    Text("Done")
                        .font(TTFont.textXS(.bold))
                        .foregroundStyle(green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(green.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TTHomeCardPressStyle())
    }

    // MARK: - Empty states

    private var emptyRosterCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No trainees yet")
                .font(TTFont.workSans(20, weight: .bold))
                .foregroundStyle(.black)
            Text("Share your invite code so athletes can join. Once they link to you, they'll appear here every day.")
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)

            if let code = store.currentTrainer?.inviteCode {
                HStack(spacing: 10) {
                    Text(code)
                        .font(TTFont.workSans(15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        TTHomeHaptics.success()
                    } label: {
                        Text("Copy")
                            .font(TTFont.textSM(.semibold))
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
    private var attentionItems: [QueueItem] {
        let checkIns = actionQueue.filter { $0.priority == 0 }
            .sorted { ($0.inactiveDays ?? .max) > ($1.inactiveDays ?? .max) }
        return checkIns + actionQueue.filter { $0.priority == 2 }
    }

    /// Trainees with a session today or who already trained today.
    private var trainingToday: [(trainee: TraineeProfile, title: String, done: Bool)] {
        let today = Date()
        return clients.compactMap { trainee in
            let plan = store.assignedPlan(for: trainee)
            let session = plan?.session(on: today)
            let done = didTrain(trainee, on: today)
            guard session != nil || done else { return nil }
            return (trainee, session?.title ?? plan?.title ?? "Workout", done)
        }
    }

    private var actionQueue: [QueueItem] {
        let today = Date()
        return clients.compactMap { trainee -> QueueItem? in
            let plan    = store.assignedPlan(for: trainee)
            let session = plan?.session(on: today)
            let trained = didTrain(trainee, on: today)
            let days    = daysSinceLastWorkout(trainee)

            if trained {
                return QueueItem(trainee: trainee, detail: "Completed today's session", tint: green, priority: 3)
            }
            if session != nil {
                return QueueItem(trainee: trainee, detail: session?.title ?? plan?.title ?? "Session scheduled", tint: orange, priority: 1)
            }
            if plan == nil {
                return QueueItem(trainee: trainee, detail: "No workout plan assigned", tint: Color(white: 0.25), priority: 2)
            }
            if days == nil || (days ?? 0) >= 3 {
                let wait = days.map { "\($0) days without a log" } ?? "No logs yet"
                return QueueItem(trainee: trainee, detail: wait, tint: amber, priority: 0, inactiveDays: days)
            }
            return nil
        }
        .sorted { $0.priority < $1.priority }
    }

    private func didTrain(_ trainee: TraineeProfile, on day: Date) -> Bool {
        store.logs(for: trainee.id).contains {
            Calendar.current.isDate($0.completedAt, inSameDayAs: day)
        }
    }

    private func daysSinceLastWorkout(_ trainee: TraineeProfile) -> Int? {
        guard let last = store.logs(for: trainee.id).map(\.completedAt).max() else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}

#Preview("Trainer Home") {
    TrainerDashboardView()
        .ttPreviewTrainer()
}
