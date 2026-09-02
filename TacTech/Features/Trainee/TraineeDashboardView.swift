import SwiftUI

struct TraineeDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    TTWeekStrip(selected: $selectedDay)
                    hero
                    metrics
                    trainerFeedback
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .task(id: selectedDay) {
                if let trainee = store.currentTrainee {
                    await store.refreshDay(for: trainee.id, on: selectedDay)
                }
            }
        }
    }

    private var header: some View {
        TTScreenHeader(
            eyebrow: "Ready to train",
            title: store.currentUser?.name.components(separatedBy: " ").first ?? "Athlete",
            trailing: AnyView(TTAvatar(name: store.currentUser?.name ?? "A", size: 48))
        )
    }

    private var hero: some View {
        let plan = store.currentTrainee.flatMap { store.assignedPlan(for: $0) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S PLAN")
                .font(TTFont.caption(11))
                .tracking(0.8)
                .foregroundStyle(TTColor.brand)
            Text(plan?.title ?? "No plan assigned")
                .font(TTFont.title(24))
                .foregroundStyle(TTColor.ink)
            Text(plan?.focus ?? "Ask your trainer to assign a workout.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            HStack {
                if let plan {
                    Text("\(plan.durationMinutes) min")
                    Text("·")
                    Text(plan.level)
                    Text("·")
                    Text("\(plan.exercises.count) exercises")
                }
            }
            .font(TTFont.caption(13))
            .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [TTColor.brandSoft, TTColor.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous)
                .stroke(TTColor.line, lineWidth: 1)
        )
    }

    private var metrics: some View {
        let macros = store.currentTrainee.map { store.dailyMacros(for: $0.id, on: selectedDay) }
        let sessions = store.currentTrainee.map { store.logs(for: $0.id).count } ?? 0
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            TTMetricCard(title: "Calories", value: "\(macros?.calories ?? 0)", subtitle: "Estimated today", icon: "flame.fill", tint: TTColor.calorie)
            TTMetricCard(title: "Protein", value: String(format: "%.0fg", macros?.protein ?? 0), subtitle: "From logged meals", icon: "circle.grid.cross.fill", tint: TTColor.protein)
            TTMetricCard(title: "Sessions", value: "\(sessions)", subtitle: "Completed workouts", icon: "checkmark.circle.fill", tint: TTColor.success)
            TTMetricCard(title: "Form AI", value: store.currentTrainee.flatMap { store.formReports(for: $0.id).first }.map { "\($0.score)" } ?? "—", subtitle: "Latest score", icon: "camera.metering.center.weighted", tint: TTColor.energy)
        }
    }

    private var trainerFeedback: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Trainer notes")
            if let trainee = store.currentTrainee {
                let notes = store.feedback(for: trainee.id)
                if notes.isEmpty {
                    TTEmptyState(icon: "bubble.left", title: "No feedback yet", message: "Your trainer’s notes will appear here after a review.")
                        .ttCard()
                } else {
                    ForEach(notes.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.message)
                                .font(TTFont.body(14))
                                .foregroundStyle(TTColor.ink)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkSubtle)
                        }
                        .ttCard()
                    }
                }
            }
        }
    }
}
