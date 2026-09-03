import SwiftUI

struct TrainerDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()
    @State private var showProfile = false
    @State private var copiedInvite = false
    @State private var headerHeight: CGFloat = 160

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let blue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private let green = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    private let canvas = Color.white

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                darkHeader
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: TrainerHeaderHeightKey.self, value: geo.size.height)
                        }
                    )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        // Ops first → snapshot → roster → actions → recent
                        weekStrip
                        todayQueue
                        coachingMetrics
                        rosterSpotlight
                        coachShortcuts
                        recentForm
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .onPreferenceChange(TrainerHeaderHeightKey.self) { headerHeight = $0 }
            .background(canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showProfile) { TrainerProfileView(showsBack: true) }
        }
    }

    // MARK: - Header

    private var darkHeader: some View {
        TTHomeProfileHeader(
            name: firstName,
            badgeCount: attentionQueue.count,
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
            onProfileTap: { showProfile = true }
        )
    }

    // MARK: - Week strip (schedule context)

    private var weekStrip: some View {
        let days = weekDays()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let on = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedDay = day
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(TTFont.textSM(.semibold))
                            Text(day.formatted(.dateTime.day()))
                                .font(TTFont.headingXS(.bold))
                        }
                        .foregroundStyle(on ? .white : .black)
                        .frame(width: 48, height: 64)
                        .background(on ? orange : Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Today's coaching queue (primary)

    private var todayQueue: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today’s Queue")
                    .font(TTFont.headingSM(.bold))
                Spacer()
                NavigationLink {
                    MyTraineesView()
                } label: {
                    Text("See All")
                        .font(TTFont.textMD(.semibold))
                        .foregroundStyle(orange)
                }
                .buttonStyle(.plain)
            }

            if clients.isEmpty {
                emptyCard(
                    title: "No trainees yet",
                    subtitle: "Share your invite code so athletes can join your roster.",
                    cta: "Copy invite code"
                ) {
                    copyInvite()
                }
            } else if attentionQueue.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You’re clear for now")
                        .font(TTFont.textLG(.bold))
                    Text("No check-ins pending for \(selectedDay.formatted(.dateTime.weekday(.wide))).")
                        .font(TTFont.textMD(.medium))
                        .foregroundStyle(Color(white: 0.45))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.96))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(attentionQueue.prefix(5)) { item in
                        NavigationLink {
                            TraineeDetailView(trainee: item.trainee)
                        } label: {
                            HStack(spacing: 12) {
                                TTAvatar(
                                    name: store.user(forTrainee: item.trainee)?.name ?? "T",
                                    size: 44
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.user(forTrainee: item.trainee)?.name ?? "Trainee")
                                        .font(TTFont.textLG(.bold))
                                        .foregroundStyle(.black)
                                    Text(item.detail)
                                        .font(TTFont.textSM(.medium))
                                        .foregroundStyle(Color(white: 0.45))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Text(item.badge)
                                    .font(TTFont.textXS(.bold))
                                    .foregroundStyle(item.tint)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(item.tint.opacity(0.14))
                                    .clipShape(Capsule())

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            .padding(14)
                            .background(Color(white: 0.96))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Metrics

    private var coachingMetrics: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Coaching Snapshot")
                    .font(TTFont.headingSM(.bold))
                Spacer()
                NavigationLink {
                    MyTraineesView()
                } label: {
                    Text("See All")
                        .font(TTFont.textMD(.semibold))
                        .foregroundStyle(orange)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink { MyTraineesView() } label: {
                        metricCard(
                            title: "Trainees",
                            value: "\(clients.count)",
                            icon: "person.2.fill",
                            tint: orange,
                            subtitle: "Active roster"
                        )
                    }
                    .buttonStyle(.plain)

                    metricCard(
                        title: "Today",
                        value: "\(trainedToday)",
                        icon: "checkmark.seal.fill",
                        tint: green,
                        subtitle: selectedDay.formatted(.dateTime.weekday(.wide))
                    )

                    NavigationLink { WorkoutPlansView() } label: {
                        metricCard(
                            title: "Plans",
                            value: "\(planCount)",
                            icon: "list.clipboard.fill",
                            tint: blue,
                            subtitle: "Ready to assign"
                        )
                    }
                    .buttonStyle(.plain)

                    metricCard(
                        title: "Form avg",
                        value: formAvgLabel,
                        icon: "camera.viewfinder",
                        tint: Color(white: 0.28),
                        subtitle: "Live reviews"
                    )
                }
            }
        }
    }

    private func metricCard(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(TTFont.textMD(.semibold))
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(value)
                .font(TTFont.headingLG(.bold))
            Text(subtitle)
                .font(TTFont.textSM(.medium))
                .opacity(0.85)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 148, height: 148, alignment: .topLeading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Roster spotlight

    private var rosterSpotlight: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Roster")
                    .font(TTFont.headingSM(.bold))
                Spacer()
                NavigationLink {
                    MyTraineesView()
                } label: {
                    Text("Manage")
                        .font(TTFont.textMD(.semibold))
                        .foregroundStyle(orange)
                }
                .buttonStyle(.plain)
            }

            if clients.isEmpty {
                Text("Invite athletes from Profile using your code.")
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(clients.prefix(8)) { trainee in
                            NavigationLink {
                                TraineeDetailView(trainee: trainee)
                            } label: {
                                VStack(spacing: 10) {
                                    TTAvatar(
                                        name: store.user(forTrainee: trainee)?.name ?? "T",
                                        size: 56
                                    )
                                    Text(store.user(forTrainee: trainee)?.name.components(separatedBy: " ").first ?? "Athlete")
                                        .font(TTFont.textSM(.semibold))
                                        .foregroundStyle(.black)
                                        .lineLimit(1)
                                    Text(rosterStatus(for: trainee))
                                        .font(TTFont.textXS(.bold))
                                        .foregroundStyle(rosterStatusColor(for: trainee))
                                }
                                .frame(width: 96)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 8)
                                .background(Color(white: 0.96))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shortcuts (real destinations)

    private var coachShortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(TTFont.headingSM(.bold))

            VStack(spacing: 10) {
                NavigationLink {
                    MyTraineesView()
                } label: {
                    shortcutRow(
                        title: "Manage trainees",
                        subtitle: "Review roster and assignments",
                        icon: "person.crop.rectangle.stack"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WorkoutPlansView()
                } label: {
                    shortcutRow(
                        title: "Assign plans",
                        subtitle: "Push the right plan to each athlete",
                        icon: "arrow.right.square"
                    )
                }
                .buttonStyle(.plain)

                Button(action: copyInvite) {
                    shortcutRow(
                        title: copiedInvite ? "Invite copied" : "Share invite code",
                        subtitle: store.currentTrainer?.inviteCode ?? "Open Profile for your code",
                        icon: "link"
                    )
                }
                .buttonStyle(.plain)

                Button { showProfile = true } label: {
                    shortcutRow(
                        title: "Account & settings",
                        subtitle: "Profile, help, and security",
                        icon: "gearshape"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shortcutRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(orange)
                .frame(width: 44, height: 44)
                .background(Color(red: 255 / 255, green: 240 / 255, blue: 224 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TTFont.textLG(.bold))
                    .foregroundStyle(.black)
                Text(subtitle)
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(Color(white: 0.45))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(white: 0.55))
        }
        .padding(14)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Recent form

    private var recentForm: some View {
        let reports = clients.flatMap { trainee in
            store.formReports(for: trainee.id).map { (trainee, $0) }
        }.sorted { $0.1.createdAt > $1.1.createdAt }.prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Latest Form Reviews")
                .font(TTFont.headingSM(.bold))

            if reports.isEmpty {
                Text("When trainees use live form correction, results land here.")
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(Array(reports), id: \.1.id) { pair in
                    NavigationLink {
                        TraineeDetailView(trainee: pair.0)
                    } label: {
                        HStack {
                            TTAvatar(name: store.user(forTrainee: pair.0)?.name ?? "T", size: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.user(forTrainee: pair.0)?.name ?? "Trainee")
                                    .font(TTFont.textLG(.bold))
                                    .foregroundStyle(.black)
                                Text(store.exercise(id: pair.1.exerciseId)?.name ?? "Exercise")
                                    .font(TTFont.textSM(.medium))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            Spacer()
                            Text("\(pair.1.score)")
                                .font(TTFont.headingXS(.bold))
                                .foregroundStyle(pair.1.score >= 80 ? green : orange)
                        }
                        .padding(14)
                        .background(Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty / helpers

    private func emptyCard(
        title: String,
        subtitle: String,
        cta: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(TTFont.textLG(.bold))
            Text(subtitle)
                .font(TTFont.textMD(.medium))
                .foregroundStyle(Color(white: 0.45))
            Button(action: action) {
                Text(cta)
                    .font(TTFont.textMD(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func copyInvite() {
        guard let code = store.currentTrainer?.inviteCode else {
            showProfile = true
            return
        }
        UIPasteboard.general.string = code
        copiedInvite = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedInvite = false
        }
    }

    // MARK: - Data

    private var firstName: String {
        store.currentUser?.name.components(separatedBy: " ").first ?? "Coach"
    }

    private var clients: [TraineeProfile] {
        store.currentTrainer.map { store.trainees(for: $0) } ?? []
    }

    private var trainedToday: Int {
        clients.filter { didTrain($0, on: selectedDay) }.count
    }

    private var planCount: Int {
        store.plans.filter { $0.trainerId == store.currentTrainer?.id }.count
    }

    private var formAvgLabel: String {
        let reports = clients.flatMap { store.formReports(for: $0.id) }
        guard !reports.isEmpty else { return "—" }
        return "\(reports.map(\.score).reduce(0, +) / reports.count)"
    }

    private struct QueueItem: Identifiable {
        var id: String { trainee.id }
        let trainee: TraineeProfile
        let badge: String
        let detail: String
        let tint: Color
        let priority: Int
    }

    /// Needs attention first, then scheduled, then already trained.
    private var attentionQueue: [QueueItem] {
        clients.compactMap { trainee -> QueueItem? in
            let name = store.user(forTrainee: trainee)?.name ?? "Trainee"
            let plan = store.assignedPlan(for: trainee)
            let session = plan?.session(on: selectedDay)
            let trained = didTrain(trainee, on: selectedDay)
            let daysSince = daysSinceLastWorkout(trainee)

            if trained {
                return QueueItem(
                    trainee: trainee,
                    badge: "Done",
                    detail: "Completed session · \(name)",
                    tint: green,
                    priority: 3
                )
            }
            if session != nil {
                return QueueItem(
                    trainee: trainee,
                    badge: "Today",
                    detail: session?.title ?? plan?.title ?? "Session scheduled",
                    tint: orange,
                    priority: 1
                )
            }
            if daysSince == nil || (daysSince ?? 0) >= 3 {
                let wait = daysSince.map { "\($0)d quiet" } ?? "No logs yet"
                return QueueItem(
                    trainee: trainee,
                    badge: "Check-in",
                    detail: wait,
                    tint: blue,
                    priority: 0
                )
            }
            if plan == nil {
                return QueueItem(
                    trainee: trainee,
                    badge: "Plan",
                    detail: "Needs a workout plan",
                    tint: Color(white: 0.35),
                    priority: 2
                )
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

    private func rosterStatus(for trainee: TraineeProfile) -> String {
        if didTrain(trainee, on: selectedDay) { return "Trained" }
        if store.assignedPlan(for: trainee)?.session(on: selectedDay) != nil { return "Due" }
        if store.assignedPlan(for: trainee) == nil { return "No plan" }
        return "Active"
    }

    private func rosterStatusColor(for trainee: TraineeProfile) -> Color {
        if didTrain(trainee, on: selectedDay) { return green }
        if store.assignedPlan(for: trainee)?.session(on: selectedDay) != nil { return orange }
        if store.assignedPlan(for: trainee) == nil { return Color(white: 0.45) }
        return blue
    }

    private func weekDays() -> [Date] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDay)) ?? selectedDay
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }
}

private struct TrainerHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 160
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Trainer Home") {
    TrainerDashboardView()
        .ttPreviewTrainer()
}
