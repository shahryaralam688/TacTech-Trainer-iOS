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
    /// One item-based state: only one quick-message sheet can be open, a second tap does nothing.
    @State private var quickMessage: TTQuickMessageTarget?
    /// "Open chat" from the sheet: set by the sheet, presented in `onDismiss` (a cover can't open while a sheet closes).
    @State private var pendingChat: TTChatTarget?
    @State private var chatTarget: TTChatTarget?
    /// Contact times as they were when the sheet opened. While the sheet is up the board stays as it was, so the
    /// card's move to WAITING is seen after the sheet closes (it is cleared then, with the move animation).
    @State private var frozenContacts: [String: Date]?
    @State private var waitingExpanded = false
    @State private var showAllNeeds = false
    @Bindable private var contactLog = TTContactLog.shared
    private let chatStore = HumanChatStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .sheet(item: $quickMessage, onDismiss: {
                if let pending = pendingChat {
                    pendingChat = nil
                    chatTarget = pending
                }
                // The board catches up with the new contact time: the card moves to WAITING.
                withAnimation(boardAnimation) { frozenContacts = nil }
            }) { target in
                TTQuickMessageSheet(target: target, onOpenChat: {
                    pendingChat = TTChatTarget(id: target.peerId, name: target.name.isEmpty ? nil : target.name)
                })
                .ttModalSheetPresentation()
            }
            .fullScreenCover(item: $chatTarget) { target in
                HumanPeerChatView(audience: .trainer, preferredPeerUserId: target.id, preferredPeerName: target.name)
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
            .task {
                // One inbox load so Home can see replies. No polling here; realtime events update it once the
                // chat has been opened (HumanChatStore.bootstrap).
                await HumanChatStore.shared.refreshInbox(quiet: true)
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

    /// A check-in card with its follow-up state (see `followUpState`).
    private struct BoardEntry: Identifiable {
        var id: String { item.id }
        let item: QueueItem
        let state: TTFollowUpState
    }

    private var boardAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: TTFollowUp.moveDuration)
    }

    private var peerKeyFor: (TraineeProfile) -> String {
        { trainee in
            let userId = trainee.userId.trimmingCharacters(in: .whitespacesAndNewlines)
            return userId.isEmpty ? trainee.id : userId
        }
    }

    /// Where a check-in card belongs, from existing data only:
    ///  - contact time: the per-device `TTContactLog` (written when the trainer's text message was sent OK);
    ///  - a workout logged at or after that contact makes the contact stale (ignored);
    ///  - a reply: the chat inbox thread has unreadCount > 0 and lastAt later than the contact.
    private func followUpState(for item: QueueItem, contacts: [String: Date], today: Date) -> TTFollowUpState {
        guard item.priority == 0, let contacted = contacts[peerKeyFor(item.trainee)] else { return .needsYou }
        if let lastLog = store.logs(for: item.trainee.id).map(\.completedAt).max(), lastLog >= contacted {
            return .needsYou
        }
        let key = peerKeyFor(item.trainee)
        if let peer = chatStore.inbox.first(where: { $0.id == key }),
           peer.unreadCount > 0, let lastAt = peer.lastAt, lastAt > contacted {
            return .replied(at: lastAt)
        }
        let days = Calendar.current.dateComponents([.day], from: contacted, to: today).day ?? 0
        return days >= TTFollowUp.followUpQuietAfterDays
            ? .stillQuiet(contacted: contacted, days: days)
            : .waiting(contacted: contacted)
    }

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Each trainee's status is worked out ONCE per redraw; everything below reads this lookup.
            let roster = clients
            let today = Date()
            let statuses = statusLookup(for: roster, today: today)
            let contacts = frozenContacts ?? contactLog.contactedAt
            let entries = attentionItems(queue: actionQueue(roster: roster, statuses: statuses)).map {
                BoardEntry(item: $0, state: followUpState(for: $0, contacts: contacts, today: today))
            }
            let needs = entries.filter { !$0.state.isWaiting }
            let waiting = entries.filter { $0.state.isWaiting }
            let training = trainingToday(roster: roster, statuses: statuses, today: today)
            let pendingJoins = store.trainerJoinRequests.filter(\.isPending)
            let joinCards = pendingJoins.isEmpty ? 0 : 1
            let total = needs.count + joinCards

            if roster.isEmpty {
                if !pendingJoins.isEmpty { joinRequestsCard(pendingJoins) }
                emptyRosterCard
            } else {
                if total == 0 && waiting.isEmpty {
                    allClearCard
                } else {
                    // Section title
                    HStack(alignment: .firstTextBaseline) {
                        if total == 0 {
                            Text("Nothing needs you right now")
                                .font(TTFont.workSans(20, weight: .bold))
                                .foregroundStyle(.black)
                        } else {
                            Text("\(total) thing\(total == 1 ? "" : "s") to do")
                                .font(TTFont.workSans(20, weight: .bold))
                                .foregroundStyle(.black)
                        }
                        Spacer()
                        Text(Date(), format: .dateTime.weekday(.wide))
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    .padding(.bottom, 4)

                    if !waiting.isEmpty {
                        Text("\(total) need you · \(waiting.count) waiting on a reply")
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(Color(white: 0.45))
                    }

                    if total > 0 {
                        Text("NEEDS YOU")
                            .font(TTFont.workSans(11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color(white: 0.5))
                            .padding(.top, 4)

                        // At most 3 cards (the join-request card counts as one), then "See all N".
                        let limit = showAllNeeds ? Int.max : TTFollowUp.needsYouCardLimit
                        if !pendingJoins.isEmpty {
                            joinRequestsCard(pendingJoins)
                        }
                        ForEach(needs.prefix(max(0, limit - joinCards))) { entry in
                            actionCard(entry.item, state: entry.state)
                                .transition(boardTransition)
                        }
                        if total > TTFollowUp.needsYouCardLimit {
                            Button {
                                withAnimation(boardAnimation) { showAllNeeds.toggle() }
                            } label: {
                                Text(showAllNeeds ? "Show fewer" : "See all \(total)")
                                    .font(TTFont.workSans(14, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.35))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // One summary card instead of a second roster; the list lives in My Trainees (Today filter).
                if !training.isEmpty {
                    trainingSummaryCard(training, statuses: statuses)
                }

                if !waiting.isEmpty {
                    waitingSection(waiting)
                }
            }
        }
    }

    private var boardTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14))
    }

    // MARK: - Waiting on reply

    private func waitingSection(_ waiting: [BoardEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: TTFollowUp.expandDuration)) {
                    waitingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("WAITING ON REPLY")
                        .font(TTFont.workSans(11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color(white: 0.5))
                    Text("\(waiting.count)")
                        .font(TTFont.workSans(12, weight: .bold))
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(white: 0.93)))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.5))
                        .rotationEffect(.degrees(waitingExpanded ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Waiting on reply, \(waiting.count)"))
            .accessibilityValue(Text(LocalizedStringKey(waitingExpanded ? "Expanded" : "Collapsed")))
            .accessibilityAddTraits(.isButton)

            if waitingExpanded {
                VStack(spacing: 8) {
                    ForEach(waiting) { entry in
                        waitingCard(entry)
                            .transition(boardTransition)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    /// Compact card: tag, name, "Messaged yesterday · no log yet" and a quiet "Message again".
    private func waitingCard(_ entry: BoardEntry) -> some View {
        let name = store.user(forTrainee: entry.item.trainee)?.name ?? "Trainee"
        let line: String = {
            if case .waiting(let contacted) = entry.state { return TTFollowUpText.waiting(contacted) }
            return entry.item.detail
        }()
        return Button {
            detailTrainee = entry.item.trainee
        } label: {
            HStack(spacing: 12) {
                TTAvatar(name: name, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("WAITING")
                        .font(TTFont.workSans(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color(white: 0.5))
                    Text(name)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                    Text(line)
                        .font(TTFont.textSM(.medium))
                        .foregroundStyle(Color(white: 0.45))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                // Room for the overlaid real button.
                Color.clear.frame(width: 112, height: 44)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(TTHomeCardPressStyle())
        .overlay(alignment: .trailing) {
            Button {
                openQuickMessage(entry.item, state: entry.state)
            } label: {
                Text("Message again")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.3))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .accessibilityLabel(Text("Message \(name) again"))
        }
    }

    // MARK: - Action card (ONE button, ONE job)

    private func actionCard(_ item: QueueItem, state: TTFollowUpState = .needsYou) -> some View {
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
                        let tag = cardTag(item, state)
                        Text(tag.key)
                            .font(TTFont.workSans(11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(tag.color)
                        Text(store.user(forTrainee: item.trainee)?.name ?? "Trainee")
                            .font(TTFont.textLG(.bold))
                            .foregroundStyle(.black)
                        Text(cardLine(item, state))
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
                    openQuickMessage(item, state: state)
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

    private func cardTag(_ item: QueueItem, _ state: TTFollowUpState) -> (key: LocalizedStringKey, color: Color) {
        if item.priority != 0 { return ("NO PLAN", Color(white: 0.5)) }
        switch state {
        case .stillQuiet: return ("STILL QUIET", amber)
        case .replied: return ("REPLIED", blue)
        default: return ("NEEDS A CHECK-IN", amber)
        }
    }

    private func cardLine(_ item: QueueItem, _ state: TTFollowUpState) -> String {
        switch state {
        case .stillQuiet(_, let days): return TTFollowUpText.stillQuiet(days: days)
        case .replied(let at): return TTFollowUpText.replied(at)
        default: return item.detail
        }
    }

    /// Opens the review sheet for a card. Nothing is sent until the trainer taps Send there.
    private func openQuickMessage(_ item: QueueItem, state: TTFollowUpState) {
        guard quickMessage == nil else { return }
        let trainee = item.trainee
        let name = store.user(forTrainee: trainee)?.name ?? ""
        // The card decides the text. `inactiveDays == nil` means the trainee never logged.
        let situation: TTQuickMessageSituation
        switch state {
        case .stillQuiet(let contacted, _), .waiting(let contacted):
            situation = .stillQuiet(when: TTFollowUpText.when(contacted))
        default:
            situation = item.inactiveDays.map { .daysWithoutLog($0) } ?? .noLogs
        }
        // Keep the board as it is while the sheet is open (see `frozenContacts`).
        frozenContacts = contactLog.contactedAt
        quickMessage = TTQuickMessageTarget(
            id: trainee.id,
            peerId: peerKeyFor(trainee),
            name: name,
            reason: cardLine(item, state),
            situation: situation
        )
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

// MARK: - Follow-up board (Trainer Home)

/// Named numbers of the follow-up board and the quick message sheet.
enum TTFollowUp {
    /// A contacted trainee who is still quiet after this many days returns to NEEDS YOU ("STILL QUIET").
    static let followUpQuietAfterDays = 3
    /// Quick message: no "sent" after this long stops the spinner and offers Retry (a late success still ends as Sent).
    static let sendTimeoutSeconds: TimeInterval = 12
    /// Cards shown in NEEDS YOU before "See all N".
    static let needsYouCardLimit = 3
    /// A card moving between sections.
    static let moveDuration: TimeInterval = 0.25
    /// The WAITING ON REPLY row opening or closing.
    static let expandDuration: TimeInterval = 0.2
}

enum TTFollowUpState: Equatable {
    case needsYou
    case replied(at: Date)
    case stillQuiet(contacted: Date, days: Int)
    case waiting(contacted: Date)

    var isWaiting: Bool {
        if case .waiting = self { return true }
        return false
    }
}

/// Per-device record of "the trainer messaged this trainee": [chat peer id (the trainee's USER id) : time].
/// Written only when a text message was sent successfully (HumanChatStore). One device only: messages sent from
/// another device are not known here. Kept in UserDefaults.
@MainActor
@Observable
final class TTContactLog {
    static let shared = TTContactLog()
    private static let defaultsKey = "followup.contactedAt"

    private(set) var contactedAt: [String: Date]

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        contactedAt = stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func record(peerUserId: String, at date: Date = Date()) {
        let id = peerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        contactedAt[id] = date
        UserDefaults.standard.set(contactedAt.mapValues { $0.timeIntervalSince1970 }, forKey: Self.defaultsKey)
    }
}

/// Lines of the board. Localized through the String Catalog.
@MainActor
enum TTFollowUpText {
    private static func l(_ value: String.LocalizationValue) -> String {
        LocalizationController.shared.localized(value)
    }

    /// "yesterday", "3 days ago", in the app language.
    static func when(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationController.shared.locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func waiting(_ contacted: Date) -> String { l("Messaged \(when(contacted)) · no log yet") }
    static func stillQuiet(days: Int) -> String { l("Messaged \(days) days ago, still no log") }
    static func replied(_ date: Date) -> String { l("Replied \(when(date))") }
}

// MARK: - Quick message (Trainer Home)
//
// A review sheet opened from a Home attention card's "Message" button. The trainer reads the message, can edit it,
// and sends it without leaving Home. Nothing is sent until "Send message" is tapped.
// Sending reuses HumanChatStore (`sendText(to:text:)` / `retryFailed`), which resolves the thread with the existing
// get-or-create logic. No new endpoint, no new request shape.

/// What the card is about. Decides which message is written.
enum TTQuickMessageSituation: Hashable {
    case noLogs
    case daysWithoutLog(Int)
    /// The trainer already messaged and the trainee is still quiet. `when` is a short phrase such as "yesterday".
    case stillQuiet(when: String)
    case noPlan
    case generic
}

struct TTQuickMessageTarget: Identifiable, Hashable {
    /// Trainee profile id.
    let id: String
    /// Chat peer id (the trainee's USER id), the key HumanChatStore uses for threads and drafts.
    let peerId: String
    /// Full display name; empty when unknown.
    let name: String
    /// The card's reason line, for example "79 days without a log".
    let reason: String
    let situation: TTQuickMessageSituation

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? ""
    }
}

/// The written texts. English is the source; every string lives in Localizable.xcstrings.
/// Only the first name is used. Never weights, calories or other personal data.
@MainActor
enum TTQuickMessageText {
    private static func l(_ value: String.LocalizationValue) -> String {
        LocalizationController.shared.localized(value)
    }

    /// "Hi ," -> "Hi," when there is no name.
    private static func tidy(_ text: String, name: String) -> String {
        guard name.isEmpty else { return text }
        return text
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " ،", with: "،")
            .replacingOccurrences(of: " ，", with: "，")
    }

    static func message(for situation: TTQuickMessageSituation, name: String) -> String {
        let text: String
        switch situation {
        case .noLogs:
            text = l("Hi \(name), I noticed there are no workouts logged yet. How is it going? I'm here if you need anything.")
        case .daysWithoutLog(let days):
            text = l("Hi \(name), it has been \(days) days since your last logged workout. Is something getting in the way? Let's adjust your plan so it fits your week.")
        case .stillQuiet(let when):
            text = l("Hi \(name), checking in again. I messaged you \(when) and haven't seen a workout since. Is everything okay?")
        case .noPlan:
            text = l("Hi \(name), I'm preparing your plan. Which days work best for you to train, and is there anything I should know, like injuries or equipment?")
        case .generic:
            text = l("Hi \(name), how is your training going this week?")
        }
        return tidy(text, name: name)
    }

    @MainActor
    enum Chip: CaseIterable, Hashable {
        case checkIn, planHelp, encouragement

        var title: String {
            switch self {
            case .checkIn: return LocalizationController.shared.localized("Check-in")
            case .planHelp: return LocalizationController.shared.localized("Plan help")
            case .encouragement: return LocalizationController.shared.localized("Encouragement")
            }
        }

        func message(name: String) -> String {
            let text: String
            switch self {
            case .checkIn:
                text = TTQuickMessageText.l("Hi \(name), just checking in. If the plan needs changing, tell me and we'll sort it out together.")
            case .planHelp:
                text = TTQuickMessageText.l("Hi \(name), want to adjust your plan? Tell me what feels too easy, too hard, or hard to fit in your week.")
            case .encouragement:
                text = TTQuickMessageText.l("Great work, \(name)! Keep it up. Tell me how the sessions feel.")
            }
            return TTQuickMessageText.tidy(text, name: name)
        }
    }
}

// MARK: - Sheet

struct TTQuickMessageSheet: View {
    let target: TTQuickMessageTarget
    /// Asked to open the full chat for this trainee. The sheet dismisses itself right after calling it.
    var onOpenChat: () -> Void = {}

    private enum SendPhase: Equatable { case idle, sending, sent, failed }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var text: String
    @State private var isEditing = false
    @State private var detent: PresentationDetent
    @State private var phase: SendPhase = .idle
    /// clientId of the message handed to HumanChatStore; its delivery state tells us how the send went.
    @State private var trackedClientId: String?
    /// Counts send attempts; the timeout task is keyed on it, so each attempt gets its own 12 s clock.
    @State private var attempt = 0
    // First-detent sizing (measured once the content is laid out; ignored while editing).
    @State private var fitHeight: CGFloat
    @State private var contentHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    @State private var bottomInset: CGFloat = 0
    @FocusState private var editorFocused: Bool

    private let chat = HumanChatStore.shared
    private let ink = Color.black
    private let sentGreen = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)

    init(target: TTQuickMessageTarget, onOpenChat: @escaping () -> Void = {}) {
        self.target = target
        self.onOpenChat = onOpenChat
        // An existing draft wins. Otherwise the situation text is shown but NOT stored as a draft.
        let draft = HumanChatStore.shared.drafts[target.peerId] ?? ""
        let hasDraft = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let initial = hasDraft
            ? draft
            : TTQuickMessageText.message(for: target.situation, name: target.firstName)
        _text = State(initialValue: initial)
        // First guess for the height (about 34 characters per line); the measured value replaces it at once.
        let lines = max(1, Int((Double(initial.count) / 34).rounded(.up)))
        let guess = Self.clampedHeight(330 + CGFloat(lines) * 22 + 150)
        _fitHeight = State(initialValue: guess)
        _detent = State(initialValue: .height(guess))
    }

    private static func clampedHeight(_ value: CGFloat) -> CGFloat {
        min(max(value, 380), UIScreen.main.bounds.height * 0.88)
    }

    private var displayName: String {
        target.name.isEmpty ? LocalizationController.shared.localized("Trainee") : target.name
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isBusy: Bool { phase == .sending || phase == .sent }

    /// Delivery state of the message we handed to the chat store (nil until something was sent).
    private var trackedDelivery: HumanChatDeliveryStatus? {
        guard let id = trackedClientId else { return nil }
        return chat.messages(for: target.peerId).first(where: { $0.clientId == id })?.resolvedDelivery
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recipientRow
                previewSection
                if isEditing { editArea.transition(.opacity) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isEditing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { height in
                guard height != contentHeight else { return }
                contentHeight = height
                refit()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { height in
                    guard height != barHeight else { return }
                    barHeight = height
                    refit()
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom.rounded(.up) } action: { inset in
            guard inset != bottomInset else { return }
            bottomInset = inset
            refit()
        }
        .presentationDetents([.height(fitHeight), .large], selection: $detent)
        .presentationBackground(Color.white)
        .interactiveDismissDisabled(isBusy)
        .onChange(of: text) { _, newValue in
            // Only the trainer's own edits reach here (the starting text is set in init).
            storeDraft(newValue)
            if phase == .failed { phase = .idle }
        }
        .onChange(of: trackedDelivery) { _, state in
            handleDelivery(state)
        }
        // One timeout clock per attempt: after the limit the spinner stops and Retry appears. The message stays
        // tracked, so if it still arrives later the UI turns to "Sent" (see handleDelivery).
        .task(id: attempt) {
            guard phase == .sending else { return }
            try? await Task.sleep(for: .seconds(TTFollowUp.sendTimeoutSeconds))
            guard !Task.isCancelled, phase == .sending else { return }
            phase = .failed
        }
        .onAppear {
            AccessibilityNotification.Announcement(
                LocalizationController.shared.localized("Message to \(displayName)")
            ).post()
        }
    }

    /// Content height + bottom bar + home-indicator inset = the first detent. Not while editing (that is .large).
    private func refit() {
        guard !isEditing, contentHeight > 0, barHeight > 0 else { return }
        let next = Self.clampedHeight(contentHeight + barHeight + bottomInset)
        guard abs(next - fitHeight) >= 1 else { return }
        let wasAtFit = detent != .large
        fitHeight = next
        if wasAtFit { detent = .height(next) }
    }

    // MARK: Recipient

    private var recipientRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                TTAvatar(name: displayName, size: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TO")
                        .font(TTFont.workSans(11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color(white: 0.5))
                    Text(displayName)
                        .font(TTFont.workSans(20, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    if !target.reason.isEmpty {
                        Text(target.reason)
                            .font(TTFont.textMD(.medium))
                            .foregroundStyle(Color(white: 0.45))
                            .lineLimit(2)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                openChat()
            } label: {
                Text("Open chat")
                    .font(TTFont.workSans(14, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }

    /// Opens the full chat for this trainee. An edited text is already stored as the draft (storeDraft), so it
    /// shows in the chat composer.
    private func openChat() {
        guard !isBusy else { return }
        editorFocused = false
        onOpenChat()
        dismiss()
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WHAT \(target.firstName.isEmpty ? displayName.uppercased() : target.firstName.uppercased()) WILL SEE")
                    .font(TTFont.workSans(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color(white: 0.5))
                    .lineLimit(2)
                Spacer(minLength: 8)
                editPill
            }

            VStack(alignment: .trailing, spacing: 10) {
                if !trimmed.isEmpty {
                    HStack(spacing: 0) {
                        Spacer(minLength: 36)
                        Text(trimmed)
                            .font(TTFont.workSans(16, weight: .regular))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 22,
                                    bottomLeadingRadius: 22,
                                    bottomTrailingRadius: 6,
                                    topTrailingRadius: 22,
                                    style: .continuous
                                )
                                .fill(ink)
                            )
                    }
                }
                Text("Sent now, in your chat with \(target.firstName.isEmpty ? displayName : target.firstName)")
                    .font(TTFont.textSM(.medium))
                    .foregroundStyle(Color(white: 0.5))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LocalizationController.shared.localized("Message preview: \(trimmed)"))
        }
    }

    private var editPill: some View {
        Button {
            toggleEditing()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 12, weight: .semibold))
                Text(LocalizedStringKey(isEditing ? "Done editing" : "Edit message"))
                    .font(TTFont.workSans(13, weight: .semibold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color(white: 0.94)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(Text(LocalizedStringKey(isEditing ? "Done editing" : "Edit message")))
    }

    // MARK: Editing

    private var editArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .focused($editorFocused)
                .font(TTFont.workSans(16, weight: .regular))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(TTColor.actionOrange, lineWidth: 1.5)
                )
                .disabled(isBusy)
                .accessibilityLabel("Message")

            ViewThatFits(in: .horizontal) {
                chipRow
                ScrollView(.horizontal, showsIndicators: false) { chipRow }
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(TTQuickMessageText.Chip.allCases, id: \.self) { chip in
                Button {
                    text = chip.message(name: target.firstName)
                    editorFocused = true
                } label: {
                    Text(chip.title)
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color(white: 0.94)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    private func toggleEditing() {
        if isEditing {
            editorFocused = false
            isEditing = false
            detent = .height(fitHeight)
        } else {
            isEditing = true
            detent = .large
            // Focus after the editor exists. The sheet never opens with the keyboard.
            DispatchQueue.main.async { editorFocused = true }
        }
    }

    // MARK: Drafts

    /// Same mechanism the chat uses: drafts keyed by the trainee's user id (and the profile id, as the old opener did).
    private func storeDraft(_ value: String) {
        chat.drafts[target.peerId] = value
        if target.id != target.peerId { chat.drafts[target.id] = value }
    }

    private func clearDraft() {
        chat.drafts[target.peerId] = ""
        if target.id != target.peerId { chat.drafts[target.id] = "" }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if phase == .failed {
                Text("Couldn't send. Check your connection and try again.")
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .accessibilityAddTraits(.isStaticText)
            }

            Button(action: send) { sendLabel }
                .buttonStyle(TTQuickSendPressStyle())
                .disabled(trimmed.isEmpty || isBusy)
                .opacity(trimmed.isEmpty && !isBusy ? 0.4 : 1)
                .accessibilityLabel(sendAccessibilityLabel)

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(TTFont.workSans(16, weight: .medium))
                    .foregroundStyle(Color(white: 0.4))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.white)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: phase)
    }

    private var sendLabel: some View {
        HStack(spacing: 8) {
            switch phase {
            case .sending:
                ProgressView().tint(.white)
                Text("Sending…")
            case .sent:
                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                Text("Sent")
            default:
                Text("Send message")
            }
        }
        .font(TTFont.workSans(17, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Capsule().fill(phase == .sent ? sentGreen : ink))
        .contentShape(Capsule())
    }

    private var sendAccessibilityLabel: String {
        switch phase {
        case .sending: return LocalizationController.shared.localized("Sending…")
        case .sent: return LocalizationController.shared.localized("Sent")
        default: return LocalizationController.shared.localized("Send message")
        }
    }

    // MARK: Sending

    /// Uses HumanChatStore.sendText(to:text:) (existing). It adds the message to the thread as "pending", resolves the
    /// thread (existing inbox thread, else POST /chat/threads, which creates or returns it), then sends. The result
    /// arrives as that message's delivery state, which `handleDelivery` turns into success or failure.
    ///
    /// Retry rules (existing store functions only):
    ///  - same text, message failed  -> `retryFailed` on that message (no second copy);
    ///  - same text, still pending   -> keep waiting for it (a new 12 s clock starts, nothing is sent twice);
    ///  - edited text, old one failed -> `deleteLocalMessage` removes the stale failed bubble, then a new send;
    ///  - edited text, old one still pending -> it is left alone (it may still arrive), then a new send.
    private func send() {
        guard !trimmed.isEmpty, !isBusy else { return }
        editorFocused = false
        let message = trimmed

        if let id = trackedClientId,
           let old = chat.messages(for: target.peerId).first(where: { $0.clientId == id }) {
            if old.text == message {
                phase = .sending
                attempt += 1
                if old.resolvedDelivery == .failed {
                    chat.retryFailed(messageId: old.id, peerUserId: target.peerId)
                }
                return
            }
            if old.resolvedDelivery == .failed {
                chat.deleteLocalMessage(id: old.id, peerUserId: target.peerId)
            }
        }

        phase = .sending
        attempt += 1
        chat.sendText(to: target.peerId, text: message)
        // sendText appends the pending message synchronously; find it by its text.
        trackedClientId = chat.messages(for: target.peerId)
            .last(where: { $0.isOutgoing && $0.text == message && $0.resolvedDelivery == .pending })?.clientId
        if trackedClientId == nil {
            // Nothing was queued (for example an empty peer id): show the failure, keep the text.
            fail()
        }
    }

    private func handleDelivery(_ state: HumanChatDeliveryStatus?) {
        guard let state else { return }
        switch state {
        case .failed:
            if phase == .sending { fail() }
        case .sent, .delivered, .read:
            // Also after the 12 s timeout: a late success must end as "Sent", not leave a second copy to retry.
            guard phase == .sending || phase == .failed else { return }
            phase = .sent
            clearDraft()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                dismiss()
            }
        case .pending:
            break
        }
    }

    private func fail() {
        phase = .failed
        // sendText cleared the draft; the sheet keeps the text, and so does the draft.
        storeDraft(text)
    }
}

/// Press feedback for Send: scale 0.98 while pressed.
private struct TTQuickSendPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

#Preview("Trainer Home") {
    TrainerDashboardView()
        .ttPreviewTrainer()
}
