import SwiftUI

struct TraineeDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let blue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                darkHeader
                VStack(alignment: .leading, spacing: 22) {
                    fitnessMetrics
                    workoutsSection
                    trainerNotes
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .task(id: selectedDay) {
            if let trainee = store.currentTrainee {
                await store.refreshDay(for: trainee.id, on: selectedDay)
            }
        }
    }

    // MARK: - Dark curved header

    private var darkHeader: some View {
        ZStack(alignment: .bottom) {
            charcoal
                .clipShape(HomeHeaderCurve())
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(headerDate, systemImage: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .textCase(.uppercase)

                    Spacer()

                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())

                        Text("\(notificationCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(orange)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -2)
                    }
                }

                HStack(spacing: 14) {
                    avatarView

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Hello, \(firstName)!")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                        }

                        HStack(spacing: 14) {
                            Label("\(healthScore)% Healthy", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(orange)

                            Label("Pro", systemImage: "star.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(blue)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 58)
            .padding(.bottom, 36)
        }
        .frame(height: 210)
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 58, height: 58)
            if let symbol = avatarSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(String(firstName.prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 2))
    }

    // MARK: - Fitness Metrics

    private var fitnessMetrics: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Fitness Metrics")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                Spacer()
                Text("See All")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    metricCard(
                        title: "Score",
                        value: "\(healthScore)%",
                        icon: "plus",
                        tint: orange,
                        chart: .bars
                    )
                    metricCard(
                        title: "Hydration",
                        value: "\(hydrationMl) ml",
                        icon: "drop.fill",
                        tint: blue,
                        chart: .wave
                    )
                    metricCard(
                        title: "Calories",
                        value: "\(caloriesToday)",
                        icon: "flame.fill",
                        tint: Color(white: 0.28),
                        chart: .dots
                    )
                }
            }
        }
    }

    private enum MetricChart { case bars, wave, dots }

    private func metricCard(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        chart: MetricChart
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
            }

            Group {
                switch chart {
                case .bars:
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array([0.45, 0.7, 0.55, 0.9, 0.65].enumerated()), id: \.offset) { _, h in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 8, height: 36 * h)
                        }
                    }
                    .frame(height: 40, alignment: .bottom)
                case .wave:
                    WaveShape()
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(height: 40)
                case .dots:
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            Circle()
                                .fill(Color.white.opacity(i == 3 ? 1 : 0.35))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(height: 40)
                }
            }

            Text(value)
                .font(.system(size: 28, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 148, height: 148, alignment: .topLeading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Workouts

    private var workoutsSection: some View {
        let plan = store.currentTrainee.flatMap { store.assignedPlan(for: $0) }
        let session = plan?.session(on: selectedDay) ?? plan?.nextSession(from: selectedDay)
        let minutes = session?.durationMinutes ?? plan?.durationMinutes ?? 25
        let kcal = max(minutes * 12, 180)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Workouts (\(workoutCount))")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
            }

            ZStack(alignment: .topLeading) {
                Image("OnboardingWorkouts")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 8) {
                    workoutPill(icon: "clock", text: "\(minutes)min")
                    workoutPill(icon: "flame.fill", text: "\(kcal)kcal")
                }
                .padding(14)

                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session?.title ?? plan?.title ?? "Today’s training")
                                .font(.system(size: 18, weight: .bold))
                            Text(session.map { "\($0.weekday.title) · \($0.timeLabel)" } ?? plan?.focus ?? "Ask your trainer for a plan")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func workoutPill(icon: String, text: String) -> some View {
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

    // MARK: - Trainer notes (kept, restyled)

    private var trainerNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trainer notes")
                .font(.system(size: 20, weight: .bold))

            if let trainee = store.currentTrainee {
                let notes = store.feedback(for: trainee.id)
                if notes.isEmpty {
                    Text("No feedback yet — notes appear after your trainer reviews a session.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ForEach(notes.prefix(2)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.message)
                                .font(.system(size: 14, weight: .medium))
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Derived data

    private var firstName: String {
        store.currentUser?.name.components(separatedBy: " ").first ?? "Athlete"
    }

    private var headerDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: Date()).uppercased()
    }

    private var healthScore: Int {
        if let score = store.currentTrainee.flatMap({ store.formReports(for: $0.id).first?.score }) {
            return min(max(score, 1), 99)
        }
        if let userId = store.session?.userId,
           UserDefaults.standard.bool(forKey: "profile.setup.completed.\(userId)") {
            return 88
        }
        return 72
    }

    private var hydrationMl: Int {
        // Lightweight estimate from logged volume until a dedicated hydration log exists.
        guard let trainee = store.currentTrainee else { return 781 }
        let macros = store.dailyMacros(for: trainee.id, on: selectedDay)
        let base = 500 + Int(macros.calories / 4)
        return min(max(base, 400), 3500)
    }

    private var caloriesToday: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        return store.dailyMacros(for: trainee.id, on: selectedDay).calories
    }

    private var workoutCount: Int {
        store.currentTrainee.map { store.logs(for: $0.id).count } ?? 0
    }

    private var notificationCount: Int {
        store.currentTrainee.map { store.feedback(for: $0.id).count } ?? 0
    }

    private var avatarSymbol: String? {
        guard let userId = store.session?.userId else { return nil }
        return UserDefaults.standard.string(forKey: "profile.avatar.\(userId)")
    }
}

// MARK: - Shapes

private struct HomeHeaderCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 28))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - 28),
            control: CGPoint(x: rect.midX, y: rect.maxY + 18)
        )
        path.closeSubpath()
        return path
    }
}

private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.33, y: rect.midY - 10),
            control1: CGPoint(x: rect.maxX * 0.12, y: rect.midY + 12),
            control2: CGPoint(x: rect.maxX * 0.22, y: rect.midY - 16)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.66, y: rect.midY + 8),
            control1: CGPoint(x: rect.maxX * 0.44, y: rect.midY - 4),
            control2: CGPoint(x: rect.maxX * 0.55, y: rect.midY + 14)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY - 4),
            control1: CGPoint(x: rect.maxX * 0.78, y: rect.midY + 2),
            control2: CGPoint(x: rect.maxX * 0.9, y: rect.midY - 12)
        )
        return path
    }
}
