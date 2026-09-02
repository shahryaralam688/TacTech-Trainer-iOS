import SwiftUI

struct TrainerDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    TTWeekStrip(selected: $selectedDay)
                    metrics
                    todaysFocus
                    recentForm
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        TTScreenHeader(
            eyebrow: greeting,
            title: store.currentUser?.name.components(separatedBy: " ").first ?? "Coach",
            trailing: AnyView(TTAvatar(name: store.currentUser?.name ?? "T", size: 48))
        )
    }

    private var metrics: some View {
        let clients = store.currentTrainer.map { store.trainees(for: $0) } ?? []
        let activeToday = clients.filter { trainee in
            store.logs(for: trainee.id).contains { Calendar.current.isDate($0.completedAt, inSameDayAs: selectedDay) }
        }.count
        let reports = clients.flatMap { store.formReports(for: $0.id) }
        let avgScore = reports.isEmpty ? 0 : reports.map(\.score).reduce(0, +) / reports.count

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            TTMetricCard(title: "Trainees", value: "\(clients.count)", subtitle: "Active roster", icon: "person.2.fill", tint: TTColor.brand)
            TTMetricCard(title: "Trained today", value: "\(activeToday)", subtitle: selectedDay.formatted(.dateTime.weekday(.wide)), icon: "checkmark.seal.fill", tint: TTColor.success)
            TTMetricCard(title: "Plans", value: "\(store.plans.filter { $0.trainerId == store.currentTrainer?.id }.count)", subtitle: "Ready to assign", icon: "list.clipboard.fill", tint: TTColor.sleep)
            TTMetricCard(title: "Form avg", value: avgScore == 0 ? "—" : "\(avgScore)", subtitle: "AI analysis", icon: "camera.viewfinder", tint: TTColor.energy)
        }
    }

    private var todaysFocus: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Coach workflow")
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
                .foregroundStyle(TTColor.brand)
                .frame(width: 40, height: 40)
                .background(TTColor.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TTFont.heading(15))
                    .foregroundStyle(TTColor.ink)
                Text(subtitle)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
            }
            Spacer()
        }
        .ttCard()
    }

    private var recentForm: some View {
        let clients = store.currentTrainer.map { store.trainees(for: $0) } ?? []
        let reports = clients.flatMap { trainee in
            store.formReports(for: trainee.id).map { (trainee, $0) }
        }.sorted { $0.1.createdAt > $1.1.createdAt }.prefix(3)

        return VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Latest form reviews")
            if reports.isEmpty {
                TTEmptyState(icon: "camera.viewfinder", title: "No form reports yet", message: "When trainees use live form correction, results land here.")
                    .ttCard()
            } else {
                ForEach(Array(reports), id: \.1.id) { pair in
                    NavigationLink {
                        TraineeDetailView(trainee: pair.0)
                    } label: {
                        HStack {
                            TTAvatar(name: store.user(forTrainee: pair.0)?.name ?? "T", size: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.user(forTrainee: pair.0)?.name ?? "Trainee")
                                    .font(TTFont.heading(15))
                                    .foregroundStyle(TTColor.ink)
                                Text(store.exercise(id: pair.1.exerciseId)?.name ?? "Exercise")
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(TTColor.inkMuted)
                            }
                            Spacer()
                            Text("\(pair.1.score)")
                                .font(TTFont.heading(18))
                                .foregroundStyle(pair.1.score >= 80 ? TTColor.success : TTColor.brand)
                        }
                        .ttCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }
}
