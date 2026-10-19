import SwiftUI

struct TrainerDashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.selectTrainerTab) private var selectTrainerTab
    @State private var showProfile = false
    @State private var showNotifications = false
    @State private var showJoinRequests = false
    @State private var isLoadingJoinRequests = true
    @State private var showAssignSheet = false
    @Bindable private var notificationStore = NotificationStore.shared
    @StateObject private var scrollCollapse: TTHomeScrollCollapseModel = {
        let model = TTHomeScrollCollapseModel()
        model.layoutTravel = TTHomeHeaderCollapse.homeLayoutTravel
        return model
    }()

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let blue   = Color(red: 37  / 255, green: 99  / 255, blue: 235 / 255)
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

                            // 3-stat snapshot row
                            statsRow
                                .ttHomeAppear(index: 0)

                            // Join requests — urgent banner
                            if isLoadingJoinRequests {
                                joinRequestsLoadingSkeleton
                                    .ttHomeAppear(index: 1)
                            } else if store.trainerJoinRequests.contains(where: \.isPending) {
                                joinRequestsCard
                                    .ttHomeAppear(index: 1)
                            }

                            // What needs doing right now
                            actionList
                                .ttHomeAppear(index: 2)

                            // 2 quick actions at the bottom
                            quickActions
                                .ttHomeAppear(index: 3)
                        }
                        .padding(.horizontal, TTSpace.screen)
                        .padding(.top, 20)
                        .padding(.bottom, 48)
                    }
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
            .task {
                isLoadingJoinRequests = true
                await store.fetchTrainerJoinRequests()
                isLoadingJoinRequests = false
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
            metrics: [
                TTHomeProfileMetric(
                    id: "trainees",
                    icon: .usersTwo,
                    iconColor: orange,
                    text: "\(clients.count) Trainees"
                ),
                TTHomeProfileMetric(
                    id: "coach",
                    icon: .starFull,
                    iconColor: blue,
                    text: "Coach"
                )
            ],
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

    // MARK: - 3-stat snapshot row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCell(
                value: "\(clients.count)",
                label: "Clients",
                icon: "person.2.fill",
                tint: orange
            )
            statDivider
            statCell(
                value: "\(activePlanCount)",
                label: "Active plans",
                icon: "list.clipboard.fill",
                tint: blue
            )
            statDivider
            statCell(
                value: formAvgLabel,
                label: "Form avg",
                icon: "camera.viewfinder",
                tint: Color(white: 0.3)
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statCell(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(TTFont.workSans(22, weight: .bold))
                .foregroundStyle(.black)
            Text(label)
                .font(TTFont.workSans(11, weight: .medium))
                .foregroundStyle(Color(white: 0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color(white: 0.88))
            .frame(width: 1, height: 36)
    }

    // MARK: - Quick actions (2 only)

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button {
                selectTrainerTab(.plans)
            } label: {
                Label("Create Plan", systemImage: "plus.square.fill")
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(TTHomeCardPressStyle())

            Button {
                selectTrainerTab(.trainees)
            } label: {
                Label("View Trainees", systemImage: "person.2.fill")
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(white: 0.93))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(TTHomeCardPressStyle())
        }
    }

    // MARK: - Action list (the only thing on Home)

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Title: tells trainer exactly how many things need doing
            let urgent = actionQueue.filter { $0.priority < 3 }
            let done   = actionQueue.filter { $0.priority == 3 }

            if clients.isEmpty {
                emptyRosterCard
            } else if urgent.isEmpty && done.isEmpty {
                allClearCard
            } else {
                // Section title
                HStack(alignment: .firstTextBaseline) {
                    Text(urgent.isEmpty ? "All done today 🎉" : "\(urgent.count) thing\(urgent.count == 1 ? "" : "s") need your attention")
                        .font(TTFont.workSans(20, weight: .bold))
                        .foregroundStyle(.black)
                    Spacer()
                    Text(Date(), format: .dateTime.weekday(.wide))
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.bottom, 4)

                // Urgent cards — each has ONE action
                ForEach(urgent) { item in
                    actionCard(item)
                }

                // Divider + done section
                if !done.isEmpty {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color(white: 0.88))
                            .frame(height: 1)
                        Text("Completed")
                            .font(TTFont.workSans(11, weight: .semibold))
                            .foregroundStyle(Color(white: 0.6))
                            .fixedSize()
                        Rectangle()
                            .fill(Color(white: 0.88))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 6)

                    ForEach(done) { item in
                        doneCard(item)
                    }
                }
            }
        }
    }

    // MARK: - Action card (ONE button, ONE job)

    private func actionCard(_ item: QueueItem) -> some View {
        NavigationLink {
            TraineeDetailView(trainee: item.trainee)
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
        .simultaneousGesture(TapGesture().onEnded {
            if item.priority == 2 {
                showAssignSheet = true
            }
        })
    }

    @ViewBuilder
    private func actionButton(_ item: QueueItem) -> some View {
        switch item.priority {
        case 0: // Check-in needed
            Text("Check in")
                .font(TTFont.textXS(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(blue)
                .clipShape(Capsule())

        case 1: // Session today
            Text("View session")
                .font(TTFont.textXS(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(orange)
                .clipShape(Capsule())

        case 2: // No plan
            Text("Assign plan")
                .font(TTFont.textXS(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(white: 0.2))
                .clipShape(Capsule())

        default:
            EmptyView()
        }
    }

    // MARK: - Done card (muted, no button)

    private func doneCard(_ item: QueueItem) -> some View {
        HStack(spacing: 12) {
            TTAvatar(
                name: store.user(forTrainee: item.trainee)?.name ?? "T",
                size: 38
            )
            .opacity(0.55)

            Text(store.user(forTrainee: item.trainee)?.name ?? "Trainee")
                .font(TTFont.textMD(.semibold))
                .foregroundStyle(Color(white: 0.5))

            Spacer(minLength: 0)

            Label("Done", systemImage: "checkmark.circle.fill")
                .font(TTFont.textXS(.semibold))
                .foregroundStyle(green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            Text("You're clear for today")
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

    private var joinRequestsCard: some View {
        let count = store.trainerJoinRequests.filter(\.isPending).count
        return Button {
            showJoinRequests = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.clock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(orange)
                    .frame(width: 40, height: 40)
                    .background(orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join requests")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(.black)
                    Text("\(count) waiting for your approval")
                        .font(TTFont.caption(12))
                        .foregroundStyle(Color(white: 0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.6))
            }
            .padding(14)
            .background(orange.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading skeleton

    private var joinRequestsLoadingSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.92))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.88))
                    .frame(width: 110, height: 11)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.92))
                    .frame(width: 80, height: 10)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                return QueueItem(trainee: trainee, detail: wait, tint: blue, priority: 0)
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
