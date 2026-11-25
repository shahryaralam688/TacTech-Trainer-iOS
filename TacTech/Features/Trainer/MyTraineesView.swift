import SwiftUI

// MARK: - My Trainees (Sandow / TacTech system design)

/// Roster filter chips. `.today` uses `TraineeTodayStatus.isTrainingToday` (same definition as Home).
enum TraineeRosterFilter: String, CaseIterable, Identifiable {
    case all, today, noPlan
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .noPlan: return "No plan"
        }
    }
}

struct MyTraineesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Namespace private var searchNS
    @State private var showSearch = false
    @State private var query = ""
    @State private var goalFilter: String?
    @State private var rosterFilter: TraineeRosterFilter
    @State private var selectedTrainee: TraineeProfile?
    @State private var showJoinRequests = false
    @State private var showShareSheet = false
    @State private var searchVisible = true

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    init(initialFilter: TraineeRosterFilter = .all) {
        _rosterFilter = State(initialValue: initialFilter)
    }

    /// The dark list header for a given collapse progress (0 = expanded, 1 = compact).
    @ViewBuilder
    private func rosterHeader(progress: CGFloat) -> some View {
        trainerListHeader(
            title: "My Trainees",
            // No "0 trainees" line on an empty roster.
            subtitle: allTrainees.isEmpty ? "" : String(localized: "\(allTrainees.count) in total"),
            trailingIcon: .userPlus,
            collapseProgress: progress,
            accessibilityLabel: String(localized: "Invite a trainee"),
            trailingTitle: "Invite",
            onClose: { dismiss() }
        ) {
            // Was: copy the code silently. Now the same share action as the invite card.
            // TODO: no invite code on the trainer profile → nothing to share, button does nothing.
            if inviteCode != nil { showShareSheet = true }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                // Header is drawn over the scroll view; the content size never depends on its collapse.
                // The pinned controls row sticks directly under the *collapsed* header.
                TTCollapsingHeaderScreen(
                    sheetFill: canvas,
                    headerBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
                    topRadius: { _ in TTSheetChrome.pageTopRadius },
                    pinsBelowCollapsedHeader: true,
                    topAnchorID: "traineesTop",
                    header: { progress in rosterHeader(progress: progress) }
                ) {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        if let code = inviteCode {
                            inviteBanner(code: code)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        }

                        // Hidden at 0 pending; Home's join-requests card still opens the same screen.
                        if pendingRequestCount > 0 {
                            Button {
                                showJoinRequests = true
                            } label: {
                                joinRequestsEntry
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.top, inviteCode == nil ? 16 : 0)
                        }

                        TTSearchEntryPill(
                            placeholder: TTSearchCopy.trainees.pillPlaceholder,
                            query: displayQuery,
                            namespace: searchNS
                        ) {
                            showSearch = true
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, (inviteCode == nil && pendingRequestCount == 0) ? 16 : 0)
                        .onAppear { searchVisible = true }
                        .onDisappear { searchVisible = false }

                        if allTrainees.count >= 2 {
                            Section {
                                traineesListContent
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 24)
                            } header: {
                                pinnedControls(proxy: proxy)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                if isFiltering {
                                    statusLine
                                }
                                traineesListContent
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .perfTempScreen("My Trainees") // PERF-TEMP
            .ttSyncRootTabBarWithNavigationDepth()
            .navigationDestination(item: $selectedTrainee) { trainee in
                TraineeDetailView(trainee: trainee)
            }
            .navigationDestination(isPresented: $showJoinRequests) {
                JoinRequestsView()
            }
            .sheet(isPresented: $showShareSheet) {
                if let code = inviteCode {
                    TTInviteActivitySheet(text: inviteMessage(code: code))
                        .presentationDetents([.medium, .large])
                }
            }
            .ttSearchOverlay(
                isPresented: $showSearch,
                catalog: searchCatalog,
                namespace: searchNS,
                refined: true,
                onOutcome: handleSearchOutcome
            )
            .task {
                await store.fetchTrainerJoinRequests()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttJoinRequestRealtime)) { note in
                let type = (note.userInfo?["type"] as? String) ?? ""
                Task { await store.handleJoinRequestRealtime(type: type) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttOpenJoinRequests)) { _ in
                // Navigation is available from this tab; dashboard may also present sheet.
            }
        }
    }

    private var inviteCode: String? {
        guard let code = store.currentTrainer?.inviteCode, !code.isEmpty else { return nil }
        return code
    }

    private func inviteMessage(code: String) -> String {
        String(localized: "Join me on TacTech. Use my invite code \(code) (Profile, then Join a coach).")
    }

    private var pendingRequestCount: Int {
        store.trainerJoinRequests.filter(\.isPending).count
    }

    private var joinRequestsEntry: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TTColor.actionOrange.opacity(0.12))
                Image(systemName: "person.badge.clock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Requests")
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text("\(pendingRequestCount) waiting")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            }

            Spacer(minLength: 8)

            if pendingRequestCount > 0 {
                Text("\(pendingRequestCount)")
                    .font(TTFont.caption(12))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TTColor.actionOrange)
                    .clipShape(Capsule())
            }

            TTIcon(icon: .chevronRight, size: 14)
                .foregroundStyle(TTColor.inkSubtle)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var allTrainees: [TraineeProfile] {
        guard let trainer = store.currentTrainer else { return [] }
        return store.trainees(for: trainer)
    }

    private var searchCatalog: TTSearchCatalog {
        let names = Dictionary(uniqueKeysWithValues: allTrainees.map {
            ($0.id, store.user(forTrainee: $0)?.name ?? "Trainee")
        })
        let plansByTrainee = Dictionary(uniqueKeysWithValues: allTrainees.compactMap { trainee -> (String, String)? in
            guard let title = store.assignedPlan(for: trainee)?.title else { return nil }
            return (trainee.id, title)
        })
        let activeIds = Set(allTrainees.compactMap { trainee -> String? in
            store.logs(for: trainee.id).first != nil ? trainee.id : nil
        })
        return TTSearchCatalog.trainees(
            trainees: allTrainees,
            names: names,
            plansByTrainee: plansByTrainee,
            activeIds: activeIds,
            trainerId: store.currentTrainer?.id ?? "local",
            inviteCode: store.currentTrainer?.inviteCode
        )
    }

    private var displayQuery: String {
        if !query.isEmpty { return query }
        if let goalFilter { return goalFilter }
        return ""
    }

    private var filtered: [TraineeProfile] {
        var result = allTrainees
        if let goalFilter {
            result = result.filter { $0.goal.lowercased() == goalFilter.lowercased() }
        }
        switch rosterFilter {
        case .all: break
        case .today: result = result.filter { status(for: $0).isTrainingToday }
        case .noPlan: result = result.filter { status(for: $0) == .noPlan }
        }
        guard !query.isEmpty else { return result }
        return result.filter {
            store.user(forTrainee: $0)?.name.localizedCaseInsensitiveContains(query) == true
                || $0.goal.localizedCaseInsensitiveContains(query)
        }
    }

    /// Same inputs and same helper as Trainer Home — never a second definition of "today".
    private func status(for trainee: TraineeProfile) -> TraineeTodayStatus {
        TraineeTodayStatus.make(
            plan: store.assignedPlan(for: trainee),
            logs: store.logs(for: trainee.id),
            today: Date()
        )
    }

    private var isFiltering: Bool {
        !query.isEmpty || goalFilter != nil
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 8) {
            Text(
                goalFilter != nil
                    ? String(localized: "Goal: \(goalFilter!) · \(filtered.count) of \(allTrainees.count) trainees")
                    : String(localized: "Search: \(query) · \(filtered.count) of \(allTrainees.count) trainees")
            )
            .font(TTFont.workSans(13, weight: .medium))
            .foregroundStyle(TTColor.inkMuted)
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer(minLength: 8)

            Button("Clear") {
                query = ""
                goalFilter = nil
            }
            .font(TTFont.workSans(14, weight: .semibold))
            .foregroundStyle(TTColor.actionOrange)
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    private func pinnedControls(proxy: ScrollViewProxy) -> some View {
        let scrolledUnder = !searchVisible
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if !searchVisible {
                    // Opens search right here: the field grows out of this icon. No scrolling.
                    TTSearchRowButton(accessibilityLabel: "Search trainees") { showSearch = true }
                }

                filterChips

                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .ttSearchRowAnchor()

            if isFiltering {
                statusLine
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TTColor.ink.opacity(0.08))
                .frame(height: 1)
                .opacity(scrolledUnder ? 1 : 0)
        }
    }

    private var filterChips: some View {
        ForEach(TraineeRosterFilter.allCases) { option in
            let selected = rosterFilter == option
            Button { rosterFilter = option } label: {
                Text(option.title)
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(selected ? .white : TTColor.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(selected ? Color.black : cardFill)
                    .clipShape(Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .ttSearchRowFade()
        }
    }

    @ViewBuilder
    private var traineesListContent: some View {
        if filtered.isEmpty {
            emptyCard
        } else {
            ForEach(filtered) { trainee in
                Button {
                    selectedTrainee = trainee
                } label: {
                    traineeRow(trainee)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleSearchOutcome(_ outcome: TTSearchOutcome) {
        switch outcome {
        case .item(let id):
            query = ""
            goalFilter = nil
            selectedTrainee = allTrainees.first { $0.id == id }
        case .category(let id):
            query = ""
            goalFilter = id
        case .offer:
            if let code = store.currentTrainer?.inviteCode {
                UIPasteboard.general.string = code
            }
        case .applyQuery(let q):
            goalFilter = nil
            query = q
        case .dismissed:
            break
        }
    }

    private func inviteBanner(code: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your invite code")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                Text(code)
                    .font(TTFont.workSans(30, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                ShareLink(item: inviteMessage(code: code)) {
                    HStack(spacing: 8) {
                        Text("Share invite")
                            .font(TTFont.workSans(15, weight: .semibold))
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                TTCopyCodeButton(code: code) { copied in
                    TTCopyCodeLabel(copied: copied, font: TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(TTColor.ink.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func traineeRow(_ trainee: TraineeProfile) -> some View {
        let user = store.user(forTrainee: trainee)
        let plan = store.assignedPlan(for: trainee)

        return HStack(spacing: TTCardTokens.listSpacing) {
            TTAvatar(
                name: user?.name ?? "T",
                size: TTCardTokens.thumbSize,
                avatarUrl: user?.avatarUrl,
                avatarAsset: user?.avatarAsset,
                userId: user?.id
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(user?.name ?? "Trainee")
                    .font(TTFont.workSans(TTCardTokens.titleSize, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                statusLine(for: trainee)
                if let plan {
                    Text(plan.title)
                        .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(1)
                }
                Text(trainee.goal)
                    .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .medium))
                    .foregroundStyle(TTColor.inkSubtle)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            TTIcon(icon: .chevronRight, size: 14)
                .foregroundStyle(TTColor.inkSubtle)
        }
        .ttListSurface()
    }

    private let statusGreen = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    private let statusAmber = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)

    /// ONE status line per row. Words always accompany colour.
    @ViewBuilder
    private func statusLine(for trainee: TraineeProfile) -> some View {
        switch status(for: trainee) {
        case .doneToday:
            statusLabel(icon: "checkmark.circle.fill", color: statusGreen) { Text("Done today") }
        case .sessionToday(let title):
            statusLabel(icon: "calendar", color: TTColor.actionOrange) {
                title.isEmpty ? Text("Session today") : Text("Session today: \(title)")
            }
        case .inactive(let days):
            statusLabel(icon: "clock.badge.exclamationmark", color: statusAmber) {
                if days != nil, let when = lastWorkoutRelative(trainee) {
                    Text("Last workout: \(when)")
                } else {
                    Text("No workouts yet")
                }
            }
        case .noPlan:
            statusLabel(icon: "minus.circle", color: TTColor.inkMuted) { Text("No plan yet") }
        case .none:
            // Has a plan and trained 1–2 days ago: informational, not a concern (neutral colour).
            if let when = lastWorkoutRelative(trainee) {
                statusLabel(icon: "clock", color: TTColor.inkMuted) { Text("Last workout: \(when)") }
            }
        }
    }

    private func statusLabel(icon: String, color: Color, @ViewBuilder text: () -> some View) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            text()
                .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }()

    /// "yesterday" / "3 days ago" from the system formatter, so plurals and word order follow the app language.
    /// Display only; the status itself comes from `TraineeTodayStatus`.
    private func lastWorkoutRelative(_ trainee: TraineeProfile) -> String? {
        guard let last = store.logs(for: trainee.id).map(\.completedAt).max() else { return nil }
        let cal = Calendar.current
        let formatter = Self.relativeDateFormatter
        let locale = LocalizationController.shared.locale
        if formatter.locale != locale { formatter.locale = locale }
        return formatter.localizedString(for: cal.startOfDay(for: last), relativeTo: cal.startOfDay(for: Date()))
    }

    private var emptyCard: some View {
        if allTrainees.isEmpty {
            return AnyView(howItWorksCard)
        }
        if rosterFilter != .all {
            return AnyView(filterEmptyCard)
        }
        return AnyView(plainEmptyCard)
    }

    private var filterEmptyCard: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .usersTwo, filled: true, size: 28)
                .foregroundStyle(TTColor.actionOrange)
            Text("No trainees match this filter")
                .font(TTFont.workSans(17, weight: .bold))
                .multilineTextAlignment(.center)
            Button { rosterFilter = .all } label: {
                Text("Show all")
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Color.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How it works")
                .font(TTFont.workSans(17, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .accessibilityAddTraits(.isHeader)
            howItWorksStep(1, title: "Send them your code", detail: "Text it, or share it from the button above.")
            howItWorksStep(2, title: "They enter it in the app", detail: "Profile, then Join a coach.")
            howItWorksStep(3, title: "You accept the request", detail: "It appears here and on Home.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func howItWorksStep(_ number: Int, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TTFont.workSans(16, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                Text(detail)
                    .font(TTFont.workSans(14, weight: .regular))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var plainEmptyCard: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .usersTwo, filled: true, size: 28)
                .foregroundStyle(TTColor.actionOrange)
            Text("No matches")
                .font(TTFont.workSans(17, weight: .bold))
            Text("Try a different name.")
            .font(TTFont.body(14))
            .foregroundStyle(TTColor.inkMuted)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// System share sheet for the header "Invite" button (the card uses `ShareLink`; same text).
private struct TTInviteActivitySheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview("My Trainees") {
    MyTraineesView()
        .ttPreviewTrainer()
}
