import SwiftUI

struct TrainerDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()
    @State private var showProfile = false
    @State private var headerHeight: CGFloat = 160

    private let orange = TTColor.accent
    private let blue = TTColor.info
    private let green = TTColor.success
    private let canvas = TTColor.canvas

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
                        weekStrip
                        coachingMetrics
                        featuredRoster
                        coachWorkflow
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
            .sheet(isPresented: $showProfile) { TrainerProfileView() }
        }
    }

    // MARK: - Static header

    private var darkHeader: some View {
        TTHomeProfileHeader(
            name: firstName,
            badgeCount: clients.count,
            metrics: [
                TTHomeProfileMetric(
                    id: "trainees",
                    icon: .plus,
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

    // MARK: - Week strip

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
                                .font(.system(size: 12, weight: .semibold))
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 18, weight: .bold))
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

    // MARK: - Metrics (color cards like trainee home)

    private var coachingMetrics: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Coaching Metrics")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text("See All")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    metricCard(title: "Trainees", value: "\(clients.count)", icon: "person.2.fill", tint: orange, subtitle: "Active roster")
                    metricCard(title: "Today", value: "\(trainedToday)", icon: "checkmark.seal.fill", tint: green, subtitle: selectedDay.formatted(.dateTime.weekday(.wide)))
                    metricCard(title: "Plans", value: "\(planCount)", icon: "list.clipboard.fill", tint: blue, subtitle: "Ready to assign")
                    metricCard(title: "Form avg", value: formAvgLabel, icon: "camera.viewfinder", tint: Color(white: 0.28), subtitle: "AI analysis")
                }
            }
        }
    }

    private func metricCard(title: String, value: String, icon: String, tint: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(value)
                .font(.system(size: 32, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.85)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 148, height: 148, alignment: .topLeading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Featured roster card

    private var featuredRoster: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Today’s focus")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
            }

            ZStack(alignment: .bottomLeading) {
                Image("OnboardingCoach")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        focusPill(icon: "person.2.fill", text: "\(clients.count) roster")
                        focusPill(icon: "flame.fill", text: "\(trainedToday) trained")
                    }
                    Text(clients.isEmpty ? "Invite trainees to start coaching" : "Keep athletes moving today")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(store.currentTrainer?.specialty ?? "Personal coaching")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func focusPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.45))
        .clipShape(Capsule())
    }

    // MARK: - Workflow

    private var coachWorkflow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach workflow")
                .font(.system(size: 20, weight: .bold))

            VStack(spacing: 10) {
                workflowRow("Manage", "Review your roster and assignments", "person.crop.rectangle.stack")
                workflowRow("Assign", "Push the right plan to each athlete", "arrow.right.square")
                workflowRow("Monitor", "Watch sessions, meals, and form scores", "eye")
                workflowRow("Review", "Leave feedback while it still matters", "bubble.left")
            }
        }
    }

    private func workflowRow(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(orange)
                .frame(width: 44, height: 44)
                .background(Color(red: 255 / 255, green: 240 / 255, blue: 224 / 255))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))
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

    // MARK: - Form reviews

    private var recentForm: some View {
        let reports = clients.flatMap { trainee in
            store.formReports(for: trainee.id).map { (trainee, $0) }
        }.sorted { $0.1.createdAt > $1.1.createdAt }.prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Latest form reviews")
                .font(.system(size: 20, weight: .bold))

            if reports.isEmpty {
                Text("When trainees use live form correction, results land here.")
                    .font(.system(size: 14, weight: .medium))
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
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.black)
                                Text(store.exercise(id: pair.1.exerciseId)?.name ?? "Exercise")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            Spacer()
                            Text("\(pair.1.score)")
                                .font(.system(size: 18, weight: .bold))
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

    // MARK: - Data

    private var firstName: String {
        store.currentUser?.name.components(separatedBy: " ").first ?? "Coach"
    }


    private var clients: [TraineeProfile] {
        store.currentTrainer.map { store.trainees(for: $0) } ?? []
    }

    private var trainedToday: Int {
        clients.filter { trainee in
            store.logs(for: trainee.id).contains {
                Calendar.current.isDate($0.completedAt, inSameDayAs: selectedDay)
            }
        }.count
    }

    private var planCount: Int {
        store.plans.filter { $0.trainerId == store.currentTrainer?.id }.count
    }

    private var formAvgLabel: String {
        let reports = clients.flatMap { store.formReports(for: $0.id) }
        guard !reports.isEmpty else { return "—" }
        return "\(reports.map(\.score).reduce(0, +) / reports.count)"
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

