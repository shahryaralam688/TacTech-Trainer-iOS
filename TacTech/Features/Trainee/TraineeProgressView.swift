import SwiftUI
import Charts

struct TraineeProgressView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TTScreenHeader(eyebrow: "Improve", title: "Progress")
                    if let trainee = store.currentTrainee {
                        metrics(trainee)
                        Chart {
                            ForEach(store.logs(for: trainee.id)) { log in
                                LineMark(
                                    x: .value("Date", log.completedAt),
                                    y: .value("Minutes", log.durationMinutes)
                                )
                                .foregroundStyle(TTColor.brand)
                                PointMark(
                                    x: .value("Date", log.completedAt),
                                    y: .value("Minutes", log.durationMinutes)
                                )
                                .foregroundStyle(TTColor.brand)
                            }
                        }
                        .frame(height: 190)
                        .ttCard()

                        TTSectionHeader(title: "Workout history")
                        ForEach(store.logs(for: trainee.id)) { log in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.plans.first { $0.id == log.planId }?.title ?? "Workout")
                                        .font(TTFont.heading(15))
                                    Text(log.completedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(TTFont.caption(12))
                                        .foregroundStyle(TTColor.inkMuted)
                                }
                                Spacer()
                                Text("\(log.durationMinutes) min")
                                    .font(TTFont.caption(13))
                                    .foregroundStyle(TTColor.brand)
                            }
                            .ttCard()
                        }

                        TTSectionHeader(title: "Form history")
                        ForEach(store.formReports(for: trainee.id)) { report in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.exercise(id: report.exerciseId)?.name ?? "Exercise")
                                        .font(TTFont.heading(15))
                                    Text(report.cues.joined(separator: " · "))
                                        .font(TTFont.caption(12))
                                        .foregroundStyle(TTColor.inkMuted)
                                }
                                Spacer()
                                Text("\(report.score)")
                                    .font(TTFont.title(20))
                                    .foregroundStyle(TTColor.brand)
                            }
                            .ttCard()
                        }
                    }
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func metrics(_ trainee: TraineeProfile) -> some View {
        let logs = store.logs(for: trainee.id)
        let reports = store.formReports(for: trainee.id)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            TTMetricCard(title: "Sessions", value: "\(logs.count)", subtitle: "Completed", icon: "flame.fill", tint: TTColor.calorie)
            TTMetricCard(title: "Best form", value: reports.map(\.score).max().map(String.init) ?? "—", subtitle: "AI score", icon: "star.fill", tint: TTColor.energy)
        }
    }
}
