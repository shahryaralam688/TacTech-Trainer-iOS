import SwiftUI
import Charts

struct TrainerProgressView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TTScreenHeader(eyebrow: "Monitor", title: "Progress")
                    overview
                    chartCard
                    rosterHealth
                }
                .padding(20)
            }
            .ttScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var overview: some View {
        let clients = store.currentTrainer.map { store.trainees(for: $0) } ?? []
        let sessions = clients.flatMap { store.logs(for: $0.id) }
        let reports = clients.flatMap { store.formReports(for: $0.id) }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            TTMetricCard(title: "Sessions", value: "\(sessions.count)", subtitle: "Logged workouts", icon: "flame.fill", tint: TTColor.calorie)
            TTMetricCard(title: "Reviews", value: "\(reports.count)", subtitle: "Form reports", icon: "waveform.path.ecg", tint: TTColor.heart)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Weekly sessions")
            Chart(weekPoints, id: \.day) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Sessions", point.count)
                )
                .foregroundStyle(TTColor.brand)
                .cornerRadius(6)
            }
            .frame(height: 180)
        }
        .ttCard()
    }

    private var rosterHealth: some View {
        let clients = store.currentTrainer.map { store.trainees(for: $0) } ?? []
        return VStack(alignment: .leading, spacing: 12) {
            TTSectionHeader(title: "Roster health")
            ForEach(clients) { trainee in
                let logs = store.logs(for: trainee.id)
                let score = store.formReports(for: trainee.id).first?.score
                HStack {
                    TTAvatar(name: store.user(forTrainee: trainee)?.name ?? "T", size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.user(forTrainee: trainee)?.name ?? "Trainee")
                            .font(TTFont.heading(15))
                        Text("\(logs.count) sessions")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Spacer()
                    Text(score.map { "Form \($0)" } ?? "No AI yet")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.brand)
                }
                .ttCard()
            }
        }
    }

    private var weekPoints: [SessionPoint] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let clients = store.currentTrainer.map { store.trainees(for: $0) } ?? []
        let logs = clients.flatMap { store.logs(for: $0.id) }
        return (0..<7).compactMap { offset -> SessionPoint? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let count = logs.filter { calendar.isDate($0.completedAt, inSameDayAs: day) }.count
            return SessionPoint(day: day, count: count)
        }
    }
}

struct SessionPoint {
    var day: Date
    var count: Int
}
