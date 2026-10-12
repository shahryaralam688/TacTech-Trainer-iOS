import Charts
import SwiftUI

/// History | Analytics | Meals segment content for trainer trainee detail.
enum TraineeDetailPerformanceTab: String, CaseIterable, Identifiable {
    case history
    case analytics
    case meals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .analytics: "Analytics"
        case .meals: "Meals"
        }
    }
}

struct TraineeDetailHistorySection: View {
    @Environment(AppStore.self) private var store
    let trainee: TraineeProfile
    var analytics: TraineeAnalytics?

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var logs: [WorkoutLog] {
        let fromStore = store.logs(for: trainee.id)
        if !fromStore.isEmpty { return fromStore }
        return analytics?.recentLogs ?? []
    }

    private var isEmpty: Bool {
        if let analytics, analytics.sessionsCompleted == 0, logs.isEmpty { return true }
        return logs.isEmpty && (analytics?.sessionsCompleted ?? 0) == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEmpty {
                emptyState(
                    title: "No workouts yet",
                    message: "When this athlete logs sessions, they’ll show up here."
                )
            } else {
                ForEach(logs) { log in
                    historyRow(log)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func historyRow(_ log: WorkoutLog) -> some View {
        let volume = log.totalVolumeKg
        let volumeLabel = volume >= 1000
            ? String(format: "%.1fk kg", volume / 1000)
            : "\(Int(volume.rounded())) kg"

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.plans.first { $0.id == log.planId }?.title ?? "Workout")
                    .font(TTFont.workSans(15, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                Text(log.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                Text("\(log.setCount) sets · \(volumeLabel)")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            Spacer(minLength: 8)
            Text("\(log.durationMinutes) min")
                .font(TTFont.workSans(14, weight: .bold))
                .foregroundStyle(TTColor.actionOrange)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(message)
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct TraineeDetailAnalyticsSection: View {
    @Environment(AppStore.self) private var store
    let trainee: TraineeProfile
    var analytics: TraineeAnalytics?
    var loadError: String?

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let loadError, analytics == nil {
                errorCard(loadError)
            } else if let analytics, analytics.sessionsCompleted == 0, analytics.workoutsByDay.allSatisfy({ $0.sessions == 0 }) {
                emptyCard
            } else if let analytics {
                kpiRow(analytics)
                volumeChart(analytics)
                topExercises(analytics)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No analytics yet")
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text("Sessions will appear here once this athlete completes workouts.")
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn’t load analytics")
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(message)
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func kpiRow(_ analytics: TraineeAnalytics) -> some View {
        let last = analytics.lastWorkoutAt?.formatted(date: .abbreviated, time: .omitted) ?? "—"
        let volume = analytics.totalVolumeKg
        let volumeText = volume >= 1000
            ? String(format: "%.1fk", volume / 1000)
            : "\(Int(volume.rounded()))"

        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            kpiTile("Sessions", "\(analytics.sessionsCompleted)", subtitle: "\(analytics.periodDays)d")
            kpiTile("Volume", volumeText, subtitle: "kg")
            kpiTile("Duration", "\(analytics.totalDurationMinutes)", subtitle: "min")
            kpiTile("Last workout", last, subtitle: nil)
        }
    }

    private func kpiTile(_ title: String, _ value: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(TTFont.caption(10))
                .fontWeight(.bold)
                .foregroundStyle(TTColor.inkSubtle)
                .tracking(0.4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(TTFont.workSans(22, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func volumeChart(_ analytics: TraineeAnalytics) -> some View {
        let days = analytics.workoutsByDay.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Volume by day")
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(TTColor.ink)

            if days.isEmpty {
                Text("No daily breakdown for this period.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Volume", day.volumeKg)
                    )
                    .foregroundStyle(orange.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, days.count / 6))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func topExercises(_ analytics: TraineeAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top exercises")
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(TTColor.ink)

            if analytics.topExercises.isEmpty {
                Text("No exercise volume yet.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(analytics.topExercises) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.exercise(id: item.exerciseId)?.name ?? "Exercise")
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(TTColor.ink)
                            Text("\(item.sets) sets · \(item.reps) reps")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        Spacer()
                        Text("\(Int(item.volumeKg.rounded())) kg")
                            .font(TTFont.workSans(14, weight: .bold))
                            .foregroundStyle(orange)
                    }
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
