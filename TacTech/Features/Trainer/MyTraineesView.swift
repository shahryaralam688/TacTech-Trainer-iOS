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
    @Namespace private var searchNS
    @State private var showSearch = false
    @State private var query = ""
    @State private var goalFilter: String?
    @State private var rosterFilter: TraineeRosterFilter
    @State private var selectedTrainee: TraineeProfile?
    @State private var showJoinRequests = false
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let scrollSpace = "myTrainees"

    init(initialFilter: TraineeRosterFilter = .all) {
        _rosterFilter = State(initialValue: initialFilter)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                trainerListHeader(
                    title: "My Trainees",
                    subtitle: "\(filtered.count) athletes",
                    trailingIcon: .userPlus,
                    collapseProgress: scrollCollapse.progress
                ) {
                    UIPasteboard.general.string = store.currentTrainer?.inviteCode
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TTHomeScrollCollapseProbe(model: scrollCollapse, space: scrollSpace)

                        VStack(alignment: .leading, spacing: 12) {
                            if let code = store.currentTrainer?.inviteCode {
                                inviteBanner(code: code)
                            }

                            Button {
                                showJoinRequests = true
                            } label: {
                                joinRequestsEntry
                            }
                            .buttonStyle(.plain)

                            TTSearchEntryPill(
                                placeholder: TTSearchCopy.trainees.pillPlaceholder,
                                query: displayQuery,
                                namespace: searchNS
                            ) {
                                showSearch = true
                            }

                            filterChips

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
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
                .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
                .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
            }
            .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .ttSyncRootTabBarWithNavigationDepth()
            .navigationDestination(item: $selectedTrainee) { trainee in
                TraineeDetailView(trainee: trainee)
            }
            .navigationDestination(isPresented: $showJoinRequests) {
                JoinRequestsView()
            }
            .ttSearchOverlay(
                isPresented: $showSearch,
                catalog: searchCatalog,
                namespace: searchNS,
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
                Text(
                    pendingRequestCount == 0
                        ? "No pending join requests"
                        : "\(pendingRequestCount) waiting for approval"
                )
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
            ($0.id, store.user(forTrainee: $0)?.name ?? "Athlete")
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

    private var filterChips: some View {
        HStack(spacing: 8) {
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
            }
            Spacer(minLength: 0)
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TTColor.actionOrange.opacity(0.12))
                TTIcon(icon: .link4, filled: true, size: 18)
                    .foregroundStyle(TTColor.actionOrange)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Invite code")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                Text(code)
                    .font(TTFont.workSans(18, weight: .bold))
                    .foregroundStyle(TTColor.ink)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = code
            } label: {
                Text("Copy")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func traineeRow(_ trainee: TraineeProfile) -> some View {
        let user = store.user(forTrainee: trainee)
        let plan = store.assignedPlan(for: trainee)

        return HStack(spacing: TTCardTokens.listSpacing) {
            TTAvatar(name: user?.name ?? "T", size: TTCardTokens.thumbSize)

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

    /// "yesterday" / "3 days ago" from the system formatter, so plurals and word order follow the app language.
    /// Display only; the status itself comes from `TraineeTodayStatus`.
    private func lastWorkoutRelative(_ trainee: TraineeProfile) -> String? {
        guard let last = store.logs(for: trainee.id).map(\.completedAt).max() else { return nil }
        let cal = Calendar.current
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.locale = LocalizationController.shared.locale
        return formatter.localizedString(for: cal.startOfDay(for: last), relativeTo: cal.startOfDay(for: Date()))
    }

    private var emptyCard: some View {
        if rosterFilter != .all && !allTrainees.isEmpty {
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

    private var plainEmptyCard: some View {
        VStack(spacing: 12) {
            TTIcon(icon: .usersTwo, filled: true, size: 28)
                .foregroundStyle(TTColor.actionOrange)
            Text(query.isEmpty && goalFilter == nil ? "No trainees yet" : "No matches")
                .font(TTFont.workSans(17, weight: .bold))
            Text(
                query.isEmpty && goalFilter == nil
                    ? "Share your invite code so athletes can join your roster."
                    : "Try a different name."
            )
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

#Preview("My Trainees") {
    MyTraineesView()
        .ttPreviewTrainer()
}
