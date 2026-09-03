import SwiftUI

struct TraineeDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()
    @State private var activityRange: ActivityRange = .week
    @State private var showProfile = false
    @State private var showProgress = false
    @State private var showNutrition = false
    @State private var showWorkouts = false

    @State private var headerHeight: CGFloat = 160

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let blue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private let canvas = Color(white: 0.98)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                darkHeader
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: HomeHeaderHeightKey.self, value: geo.size.height)
                        }
                    )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        fitnessMetrics
                        workoutsSection
                        dietSection
                        activitiesSection
                        coachSection
                        formInsightsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .onPreferenceChange(HomeHeaderHeightKey.self) { headerHeight = $0 }
            .background(canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: selectedDay) {
                if let trainee = store.currentTrainee {
                    await store.refreshDay(for: trainee.id, on: selectedDay)
                }
            }
            .sheet(isPresented: $showProfile) { TraineeProfileView() }
            .sheet(isPresented: $showProgress) { TraineeProgressView() }
            .sheet(isPresented: $showNutrition) { NutritionView() }
            .sheet(isPresented: $showWorkouts) { WorkoutHubView() }
        }
    }

    // MARK: - Header

    private var darkHeader: some View {
        TTHomeProfileHeader(
            name: firstName,
            avatarSymbol: avatarSymbol,
            badgeCount: notificationCount,
            metrics: [
                TTHomeProfileMetric(
                    id: "health",
                    icon: .plus,
                    iconColor: orange,
                    text: "\(healthScore)% Healthy"
                ),
                TTHomeProfileMetric(
                    id: "pro",
                    icon: .starFull,
                    iconColor: blue,
                    text: "Pro"
                )
            ],
            onProfileTap: { showProfile = true }
        )
    }

    // MARK: - Fitness Metrics

    private var fitnessMetrics: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Fitness Metrics") {
                Button("See All") { showProgress = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    metricCard(title: "Score", value: "\(healthScore)%", icon: "plus", tint: orange, chart: .bars)
                    metricCard(title: "Hydration", value: "\(hydrationMl) ml", icon: "drop.fill", tint: blue, chart: .wave)
                    metricCard(title: "Calories", value: "\(caloriesToday)", icon: "flame.fill", tint: Color(white: 0.28), chart: .dots)
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
        let series = session?.exercises.count ?? plan?.allExercises.count ?? 0
        let level = plan?.level ?? "Training"

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Workouts (\(workoutCount))") {
                Button {
                    showWorkouts = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(white: 0.35))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            ZStack(alignment: .topLeading) {
                Image("OnboardingWorkouts")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.25), .clear, .black.opacity(0.72)],
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
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session?.title ?? plan?.title ?? "Today’s training")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)

                            HStack(spacing: 8) {
                                Text(series > 0 ? "\(series) Series Workout" : (plan?.focus ?? "Ask your trainer for a plan"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))

                                Text(level.lowercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(orange)
                                    .clipShape(Capsule())
                            }
                        }

                        Spacer(minLength: 8)

                        if let plan {
                            NavigationLink {
                                ActiveWorkoutView(plan: plan, day: session)
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(orange)
                                    .clipShape(Circle())
                                    .shadow(color: orange.opacity(0.4), radius: 8, y: 4)
                            }
                        }
                    }
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

    // MARK: - Diet & Nutrition

    private var dietSection: some View {
        let meals = store.currentTrainee.map { store.meals(for: $0.id, on: selectedDay) } ?? []

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Diet & Nutrition") {
                Button("See All") { showNutrition = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if meals.isEmpty {
                        mealCard(
                            name: "Log your first meal",
                            protein: 0,
                            fat: 0,
                            calories: 0,
                            minutes: 0,
                            empty: true
                        )
                    } else {
                        ForEach(meals.prefix(6)) { meal in
                            mealCard(
                                name: meal.name,
                                protein: Int(meal.macros.protein.rounded()),
                                fat: Int(meal.macros.fat.rounded()),
                                calories: meal.macros.calories,
                                minutes: max(Int(meal.portionGrams / 25), 5),
                                empty: false
                            )
                        }
                    }
                }
            }
        }
    }

    private func mealCard(
        name: String,
        protein: Int,
        fat: Int,
        calories: Int,
        minutes: Int,
        empty: Bool
    ) -> some View {
        Button {
            showNutrition = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Image("OnboardingNutrition")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 128)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    if !empty {
                        HStack(spacing: 6) {
                            mealStatPill("\(protein)g Protein")
                            mealStatPill("\(fat)g Fat")
                        }
                        .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)

                    HStack {
                        if empty {
                            Label("Scan or add a meal", systemImage: "fork.knife")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        } else {
                            Label("\(calories)kcal", systemImage: "flame.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                            Label("\(minutes)min", systemImage: "clock")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(orange)
                            .clipShape(Circle())
                    }
                }
                .padding(12)
            }
            .frame(width: 220)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func mealStatPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Activities

    private var activitiesSection: some View {
        let points = activityPoints
        let total = points.reduce(0) { $0 + $1.value }
        let peak = points.map(\.value).max() ?? 0
        let delta = activityDelta
        let suggestions = cueSuggestionCount

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Activities") {
                Button("See All") { showProgress = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(ActivityRange.allCases) { range in
                        Button {
                            activityRange = range
                        } label: {
                            Text(range.label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(activityRange == range ? .white : Color(white: 0.35))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(activityRange == range ? Color.black : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color(white: 0.94))
                .clipShape(Capsule())

                ZStack(alignment: .topTrailing) {
                    ActivityLineChart(points: points.map(\.value), tint: orange)
                        .frame(height: 120)

                    if peak > 0 {
                        Text("\(peak)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(orange)
                            .clipShape(Capsule())
                            .padding(.trailing, 8)
                            .padding(.top, 4)
                    }
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(total.formatted()) kcal")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.black)

                        HStack(spacing: 14) {
                            Label(deltaLabel(delta), systemImage: "star.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(delta >= 0 ? orange : Color(white: 0.45))

                            Label("\(suggestions) Suggestions", systemImage: "person.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }

                    Spacer()

                    Button {
                        showWorkouts = true
                    } label: {
                        Image(systemName: "figure.run")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
    }

    // MARK: - Coach (trainer feedback — no fake AI)

    private var coachSection: some View {
        let notes = store.currentTrainee.map { store.feedback(for: $0.id) } ?? []
        let trainerName = store.currentTrainee.flatMap { store.trainer(for: $0)?.userId }.flatMap { id in
            store.users.first { $0.id == id }?.name
        } ?? "Your trainer"

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Your Coach") {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
            }

            ZStack(alignment: .bottomLeading) {
                Image("OnboardingCoach")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 168)
                    .frame(maxWidth: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [orange.opacity(0.15), orange.opacity(0.92)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            coachPill(trainerName.components(separatedBy: " ").first ?? "Coach")
                            coachPill("\(notes.count) notes")
                        }

                        Text("\(notes.count)+")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Trainer conversations")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    Spacer()

                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(orange)
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func coachPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
            .lineLimit(1)
    }

    // MARK: - Form insights (real reports — not fake resources)

    private var formInsightsSection: some View {
        let reports = store.currentTrainee.map { store.formReports(for: $0.id) } ?? []

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Form Insights") {
                Button("See All") { showProgress = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            if reports.isEmpty {
                Text("Form scores and coaching cues show up here after a live form session.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(reports.prefix(3)) { report in
                        Button {
                            showProgress = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(white: 0.94))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: "figure.strengthtraining.traditional")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Color(white: 0.35))
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exerciseTitle(for: report.exerciseId))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                        .lineLimit(1)

                                    Text(report.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color(white: 0.45))

                                    HStack(spacing: 12) {
                                        Label(String(format: "%.1f", Double(report.score) / 20.0), systemImage: "star.fill")
                                        Label("\(report.repCount) reps", systemImage: "eye")
                                        Label("\(report.cues.count) cues", systemImage: "heart.fill")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.45))
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.35))
                            }
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Shared chrome

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)
            Spacer()
            trailing()
        }
    }

    // MARK: - Derived data

    private var firstName: String {
        store.currentUser?.name.components(separatedBy: " ").first ?? "Athlete"
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

    private var cueSuggestionCount: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        return store.formReports(for: trainee.id).reduce(0) { $0 + $1.cues.count }
    }

    private var activityPoints: [(date: Date, value: Int)] {
        guard let trainee = store.currentTrainee else { return [] }
        let calendar = Calendar.current
        let dayCount = activityRange.dayCount
        let today = calendar.startOfDay(for: Date())
        return (0..<dayCount).reversed().compactMap { offset -> (Date, Int)? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let mealKcal = store.dailyMacros(for: trainee.id, on: day).calories
            let workoutKcal = store.logs(for: trainee.id)
                .filter { calendar.isDate($0.completedAt, inSameDayAs: day) }
                .reduce(0) { $0 + max($1.durationMinutes * 8, 0) }
            return (day, mealKcal + workoutKcal)
        }
    }

    private var activityDelta: Int {
        guard let trainee = store.currentTrainee else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = activityRange.dayCount
        func total(ending offsetEnd: Int) -> Int {
            (0..<days).reduce(0) { partial, offset in
                guard let day = calendar.date(byAdding: .day, value: -(offset + offsetEnd), to: today) else { return partial }
                return partial + store.dailyMacros(for: trainee.id, on: day).calories
            }
        }
        return total(ending: 0) - total(ending: days)
    }

    private func deltaLabel(_ delta: Int) -> String {
        if delta == 0 { return "0" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func exerciseTitle(for exerciseId: String) -> String {
        if let name = store.exercise(id: exerciseId)?.name, !name.isEmpty {
            return name
        }
        return "Form check"
    }
}

// MARK: - Header height

private struct HomeHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 160
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Activity range

private enum ActivityRange: String, CaseIterable, Identifiable {
    case day, week, month, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "1d"
        case .week: "1w"
        case .month: "1m"
        case .year: "1y"
        case .all: "All"
        }
    }

    var dayCount: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .year: 90
        case .all: 120
        }
    }
}

// MARK: - Chart

private struct ActivityLineChart: View {
    let points: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let values = points.isEmpty ? [0] : points
            let maxV = max(values.max() ?? 1, 1)
            let stepX = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : geo.size.width

            ZStack {
                tint.opacity(0.12)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = geo.size.height - (CGFloat(value) / CGFloat(maxV)) * (geo.size.height - 16) - 8
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                if let last = values.indices.last {
                    let x = CGFloat(last) * stepX
                    let y = geo.size.height - (CGFloat(values[last]) / CGFloat(maxV)) * (geo.size.height - 16) - 8
                    Circle()
                        .fill(tint)
                        .frame(width: 10, height: 10)
                        .position(x: min(max(x, 5), geo.size.width - 5), y: y)
                }
            }
        }
    }
}

// MARK: - Shapes

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
