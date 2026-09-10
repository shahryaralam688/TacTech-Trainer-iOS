import SwiftUI

struct TraineeDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()
    @State private var activityRange: ActivityRange = .week
    @State private var showProfile = false
    @State private var showProgress = false
    @State private var showNutrition = false
    @State private var showWorkouts = false
    @State private var showNotifications = false
    @State private var celebrateStart = false
    @Bindable private var notificationStore = NotificationStore.shared
    @Namespace private var activitySegmentNS

    @StateObject private var scrollCollapse: TTHomeScrollCollapseModel = {
        let model = TTHomeScrollCollapseModel()
        model.layoutTravel = TTHomeHeaderCollapse.homeLayoutTravel
        return model
    }()

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let blue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private let canvas = Color(white: 0.98)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                darkHeader

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        TTHomeScrollCollapseProbe(model: scrollCollapse, space: "traineeHome")

                        VStack(alignment: .leading, spacing: 24) {
                            // Execution first → snapshot → support
                            todayWorkoutSection
                                .ttHomeAppear(index: 0)
                            fitnessMetrics
                                .ttHomeAppear(index: 1)
                            dietSection
                                .ttHomeAppear(index: 2)
                            activitiesSection
                                .ttHomeAppear(index: 3)
                            coachSection
                                .ttHomeAppear(index: 4)
                            formInsightsSection
                                .ttHomeAppear(index: 5)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 36)
                    }
                }
                .ttTopRoundedSheet(radius: TTSheetChrome.homeTopRadius, fill: canvas)
                .ttObserveHomeScrollCollapse(scrollCollapse, space: "traineeHome")
            }
            .background(Color.black.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .task(id: selectedDay) {
                if let trainee = store.currentTrainee {
                    await store.refreshDay(for: trainee.id, on: selectedDay)
                }
            }
            .sheet(isPresented: $showProfile) { TraineeProfileView(showsBack: true) }
            .sheet(isPresented: $showProgress) { TraineeProgressView() }
            .sheet(isPresented: $showNutrition) { NutritionView() }
            .sheet(isPresented: $showWorkouts) { WorkoutHubView() }
            .sheet(isPresented: $showNotifications) { NotificationsInboxView() }
        }
    }

    // MARK: - Header

    private var darkHeader: some View {
        TTHomeProfileHeader(
            name: firstName,
            avatarSymbol: avatarSymbol,
            avatarUserId: store.session?.userId,
            badgeCount: notificationStore.unreadCount,
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

    // MARK: - Fitness Metrics

    private var fitnessMetrics: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Fitness Metrics") {
                Button("See All") {
                    TTHomeHaptics.light()
                    showProgress = true
                }
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { showProgress = true } label: {
                        metricCard(title: "Score", value: "\(healthScore)%", icon: "plus", tint: orange, chart: .ring)
                    }
                    .buttonStyle(TTHomeCardPressStyle())
                    .ttHomeCardMorph()

                    Button { showNutrition = true } label: {
                        metricCard(title: "Hydration", value: "\(hydrationMl) ml", icon: "drop.fill", tint: blue, chart: .wave)
                    }
                    .buttonStyle(TTHomeCardPressStyle())
                    .ttHomeCardMorph()

                    Button { showNutrition = true } label: {
                        metricCard(title: "Calories", value: "\(caloriesToday)", icon: "flame.fill", tint: Color(white: 0.28), chart: .dots)
                    }
                    .buttonStyle(TTHomeCardPressStyle())
                    .ttHomeCardMorph()
                }
            }
        }
    }

    private enum MetricChart { case bars, wave, dots, ring }

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
                    .font(TTFont.workSans(14, weight: .semibold))
                Spacer()
                Image(systemName: icon)
                    .font(TTFont.workSans(12, weight: .bold))
            }

            Group {
                switch chart {
                case .bars:
                    TTHomeMetricBars()
                case .wave:
                    TTHomeMetricWave()
                case .dots:
                    TTHomeMetricDots()
                case .ring:
                    TTHomeProgressRing(
                        progress: Double(healthScore) / 100.0,
                        tint: .white,
                        lineWidth: 6,
                        size: 40,
                        label: nil
                    )
                    .frame(height: 40)
                }
            }

            Text(value)
                .font(TTFont.workSans(28, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 148, height: 148, alignment: .topLeading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Today's Workout (primary CTA)

    private var todayWorkoutSection: some View {
        let plan = store.currentTrainee.flatMap { store.assignedPlan(for: $0) }
        let session = plan?.session(on: selectedDay) ?? plan?.nextSession(from: selectedDay)
        let minutes = session?.durationMinutes ?? plan?.durationMinutes ?? 25
        let kcal = max(minutes * 12, 180)
        let series = session?.exercises.count ?? plan?.allExercises.count ?? 0
        let level = plan?.level ?? "Training"
        let title = session?.title ?? plan?.title ?? "Today’s training"
        let subtitle = series > 0
            ? "\(series) exercises · \(plan?.focus ?? "Full body")"
            : (plan?.focus ?? "Ask your trainer for a plan")

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Today’s Workout") {
                Button("See All") {
                    TTHomeHaptics.light()
                    showWorkouts = true
                }
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            ZStack(alignment: .topLeading) {
                Image("OnboardingWorkouts")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .scaleEffect(1.08)
                    .ttHomeParallax(scrollProgress: scrollCollapse.progress, strength: 28)

                LinearGradient(
                    colors: [.black.opacity(0.25), .clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Soft moving highlight over the hero
                TTHomeHeroSheen()

                HStack(spacing: 8) {
                    workoutPill(icon: "clock", text: "\(minutes)min")
                    workoutPill(icon: "flame.fill", text: "\(kcal)kcal")
                    if plan != nil {
                        workoutPill(icon: "calendar", text: selectedDay.formatted(.dateTime.weekday(.abbreviated)))
                    }
                }
                .padding(14)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(TTFont.headingMD(.semibold))
                                .foregroundStyle(.white)

                            HStack(spacing: 8) {
                                Text(subtitle)
                                    .font(TTFont.textMD(.medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)

                                Text(level.lowercased())
                                    .font(TTFont.textXS(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(orange)
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer(minLength: 0)
                        TTHomeProgressRing(
                            progress: plan == nil ? 0.15 : min(1, Double(series) / 8.0),
                            tint: .white,
                            lineWidth: 5,
                            size: 48,
                            label: plan == nil ? "—" : "\(series)"
                        )
                    }
                    .padding(16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .ttHomeCardMorph()

            if let plan {
                NavigationLink {
                    ActiveWorkoutView(plan: plan, day: session)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(TTFont.workSans(14, weight: .semibold))
                        Text(session == nil ? "Start Next Session" : "Start Today’s Workout")
                            .font(TTFont.textLG(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(orange)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TTHomeHapticPressStyle(intensity: .medium))
                .ttHomeCTAPulse(tint: orange)
                .simultaneousGesture(TapGesture().onEnded {
                    celebrateStart = true
                })
                .ttHomeWin(celebrate: $celebrateStart, tint: orange)
            } else {
                Button {
                    TTHomeHaptics.medium()
                    showProfile = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(TTFont.workSans(14, weight: .semibold))
                        Text("Link a trainer to get workouts")
                            .font(TTFont.textLG(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TTHomeCardPressStyle())
            }
        }
    }

    private func workoutPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(TTFont.workSans(11, weight: .bold))
            Text(text)
                .font(TTFont.workSans(12, weight: .bold))
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
                Button("See All") {
                    TTHomeHaptics.light()
                    showNutrition = true
                }
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            if meals.isEmpty {
                TTHomeEmptyState(
                    icon: "fork.knife",
                    title: "Fuel today’s session",
                    subtitle: "Log breakfast or scan a meal so macros stay on track with your plan.",
                    cta: "Add a meal",
                    tint: orange
                ) {
                    showNutrition = true
                }
                .ttHomeCardMorph()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
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
            TTHomeHaptics.light()
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
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(.black)
                        .lineLimit(2)

                    HStack {
                        if empty {
                            Label("Scan or add a meal", systemImage: "fork.knife")
                                .font(TTFont.workSans(12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        } else {
                            Label("\(calories)kcal", systemImage: "flame.fill")
                                .font(TTFont.workSans(12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                            Label("\(minutes)min", systemImage: "clock")
                                .font(TTFont.workSans(12, weight: .medium))
                                .foregroundStyle(Color(white: 0.45))
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.right")
                            .font(TTFont.workSans(12, weight: .bold))
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
            .ttHomeCardMorph()
        }
        .buttonStyle(TTHomeCardPressStyle())
    }

    private func mealStatPill(_ text: String) -> some View {
        Text(text)
            .font(TTFont.workSans(10, weight: .bold))
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
                Button("See All") {
                    TTHomeHaptics.light()
                    showProgress = true
                }
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(ActivityRange.allCases) { range in
                        Button {
                            TTHomeHaptics.selection()
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                activityRange = range
                            }
                        } label: {
                            Text(range.label)
                                .font(TTFont.workSans(12, weight: .semibold))
                                .foregroundStyle(activityRange == range ? .white : Color(white: 0.35))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    if activityRange == range {
                                        Capsule()
                                            .fill(Color.black)
                                            .matchedGeometryEffect(id: "activityRangePill", in: activitySegmentNS)
                                    }
                                }
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
                            .font(TTFont.workSans(12, weight: .semibold))
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
                            .font(TTFont.workSans(28, weight: .semibold))
                            .foregroundStyle(.black)

                        HStack(spacing: 14) {
                            Label(deltaLabel(delta), systemImage: "star.fill")
                                .font(TTFont.workSans(13, weight: .semibold))
                                .foregroundStyle(delta >= 0 ? orange : Color(white: 0.45))

                            Label("\(suggestions) Suggestions", systemImage: "person.fill")
                                .font(TTFont.workSans(13, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }

                    Spacer()

                    TTHomeProgressRing(
                        progress: Double(healthScore) / 100.0,
                        tint: orange,
                        lineWidth: 6,
                        size: 52,
                        label: "\(healthScore)"
                    )
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
            .ttHomeCardMorph()
        }
    }

    // MARK: - Coach (trainer feedback — no fake AI)

    private var coachSection: some View {
        let notes = store.currentTrainee.map { store.feedback(for: $0.id) } ?? []
        let trainerName = store.currentTrainee.flatMap { store.trainer(for: $0)?.userId }.flatMap { id in
            store.users.first { $0.id == id }?.name
        } ?? "Your trainer"

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader("My Coach") {
                Button("Profile") {
                    TTHomeHaptics.light()
                    showProfile = true
                }
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            ZStack(alignment: .bottomLeading) {
                Image("OnboardingCoach")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 168)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .scaleEffect(1.06)
                    .ttHomeParallax(scrollProgress: scrollCollapse.progress, strength: 18)

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
                            .font(TTFont.workSans(34, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Trainer conversations")
                            .font(TTFont.workSans(16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    Spacer()

                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(TTFont.workSans(16, weight: .semibold))
                            .foregroundStyle(orange)
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(TTHomeCardPressStyle())
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .ttHomeCardMorph()
        }
    }

    private func coachPill(_ text: String) -> some View {
        Text(text)
            .font(TTFont.workSans(11, weight: .bold))
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
                Button("See All") {
                    TTHomeHaptics.light()
                    showProgress = true
                }
                    .font(TTFont.workSans(14, weight: .semibold))
                    .foregroundStyle(orange)
            }

            if reports.isEmpty {
                TTHomeEmptyState(
                    icon: "camera.viewfinder",
                    title: "Capture your first form check",
                    subtitle: "After a live form session, scores and coaching cues land here so you can improve reps.",
                    cta: "Open progress",
                    tint: orange
                ) {
                    showProgress = true
                }
                .ttHomeCardMorph()
            } else {
                VStack(spacing: 12) {
                    ForEach(reports.prefix(3)) { report in
                        Button {
                            showProgress = true
                        } label: {
                            HStack(spacing: 12) {
                                TTHomeProgressRing(
                                    progress: min(1, Double(report.score) / 100.0),
                                    tint: orange,
                                    lineWidth: 5,
                                    size: 52,
                                    label: "\(report.score)"
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exerciseTitle(for: report.exerciseId))
                                        .font(TTFont.workSans(15, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .lineLimit(1)

                                    Text(report.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(TTFont.workSans(12, weight: .medium))
                                        .foregroundStyle(Color(white: 0.45))

                                    HStack(spacing: 12) {
                                        Label(String(format: "%.1f", Double(report.score) / 20.0), systemImage: "star.fill")
                                        Label("\(report.repCount) reps", systemImage: "eye")
                                        Label("\(report.cues.count) cues", systemImage: "heart.fill")
                                    }
                                    .font(TTFont.workSans(11, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.45))
                                }

                                Spacer(minLength: 0)

                                TTChevronForward(size: 13, color: Color(white: 0.35))
                            }
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .ttHomeCardMorph()
                        }
                        .buttonStyle(TTHomeCardPressStyle())
                    }
                }
            }
        }
    }

    // MARK: - Shared chrome

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(TTFont.workSans(20, weight: .bold))
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

    private var avatarSymbol: String? {
        TTAvatarCatalog.saved(for: store.session?.userId)
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

#Preview("Trainee Home") {
    TraineeDashboardView()
        .ttPreviewTrainee()
}
