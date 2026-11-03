import SwiftUI

struct TraineeDashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedDay = Date()
    @State private var activityRange: ActivityRange = .week
    @State private var showProfile = false
    @State private var showProgress = false
    @State private var showNutrition = false
    @State private var showWorkouts = false
    @State private var showWorkoutOverview = false
    @State private var showNotifications = false
    @State private var showFindCoaches = false
    @State private var celebrateStart = false
    @State private var generateNotice: String?
    @State private var showAssessmentReview = false
    @State private var showProfileCompletion = false
    @State private var dismissedProfileNudge = false
    /// Friction E: direct resume of the live guided session from Home.
    @State private var resumeTarget: ResumeTarget?
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

                        VStack(alignment: .leading, spacing: 0) {

                            // ── Zone 1: Today ───────────────────────────────
                            traineZoneLabel("Today")
                                .ttHomeAppear(index: 0)
                            VStack(alignment: .leading, spacing: 14) {
                                todayWorkoutSection
                                    .ttHomeAppear(index: 1)
                                if store.canShowSoloAIGenerate {
                                    soloAIGenerateCard
                                        .ttHomeAppear(index: 2)
                                }
                            }

                            // ── Zone 2: Progress ────────────────────────────
                            traineZoneLabel("Progress")
                                .ttHomeAppear(index: 3)
                            VStack(alignment: .leading, spacing: 14) {
                                fitnessMetrics
                                    .ttHomeAppear(index: 4)
                                activitiesSection
                                    .ttHomeAppear(index: 5)
                            }

                            // ── Zone 3: Health & Support ────────────────────
                            traineZoneLabel("Health & Support")
                                .ttHomeAppear(index: 6)
                            if hasMeaningfulActivity {
                                VStack(alignment: .leading, spacing: 14) {
                                    dietSection
                                        .ttHomeAppear(index: 7)
                                    coachSection
                                        .ttHomeAppear(index: 8)
                                    formInsightsSection
                                        .ttHomeAppear(index: 9)
                                }
                            } else {
                                getStartedCard
                                    .ttHomeAppear(index: 7)
                            }

                            // Friction H: unobtrusive, dismissible profile-completion nudge
                            if shouldShowProfileNudge {
                                profileCompletionNudge
                                    .padding(.top, 14)
                                    .ttHomeAppear(index: 10)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, TTSpace.screen)
                        .padding(.top, 20)
                        .padding(.bottom, 36)
                    }
                }
                .ttTopRoundedSheet(
                    radius: TTSheetChrome.homeTopRadius(collapseProgress: scrollCollapse.progress),
                    fill: canvas
                )
                .ttObserveHomeScrollCollapse(scrollCollapse, space: "traineeHome")
            }
            .background(Color.black.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $resumeTarget) { target in
                ActiveWorkoutView(plan: target.plan, day: target.day)
            }
            .ttSyncRootTabBarWithNavigationDepth()
            .task(id: selectedDay) {
                if let trainee = store.currentTrainee {
                    await store.refreshDay(for: trainee.id, on: selectedDay)
                }
            }
            .task {
                await store.refreshAICapabilities()
            }
            .task {
                await store.refreshActiveSession()
            }
            .overlay(alignment: .top) {
                if let generateNotice {
                    Text(generateNotice)
                        .font(TTFont.workSans(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.82))
                        .clipShape(Capsule())
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showProfile) {
                TraineeProfileView(showsBack: true)
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showProgress) {
                TraineeProgressView()
                    .ttModalSheetPresentation()
            }
            .sheet(isPresented: $showNutrition) {
                NutritionView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showWorkouts) {
                WorkoutHubView(showsCloseChrome: true)
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showWorkoutOverview) {
                if let trainee = store.currentTrainee, let plan = store.assignedPlan(for: trainee) {
                    WorkoutOverviewView(plan: plan)
                        .ttModalSheetPresentation(dragIndicator: .hidden)
                }
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsInboxView()
                    .ttModalSheetPresentation()
            }
            .sheet(isPresented: $showFindCoaches) {
                FindCoachesView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showAssessmentReview) {
                AssessmentReviewSheet(assessment: store.loadSavedFitnessAssessment()) {
                    flashGenerateNotice("AI week ready — open Workouts")
                    showWorkouts = true
                }
                .ttModalSheetPresentation()
            }
            .sheet(isPresented: $showProfileCompletion) {
                ProfileCompletionFlowView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
        }
    }

    // MARK: - Friction E: resume the live guided session directly

    /// Resolves the in-progress session to its plan + day and pushes `ActiveWorkoutView`
    /// (which resumes at `activeExerciseIndex`). Falls back to the Workout hub when the
    /// session can't be resolved — no new resume rule is invented.
    private func continueWorkout() {
        TTHomeHaptics.medium()
        if let session = store.activeWorkoutSession,
           let plan = store.plans.first(where: { $0.id == session.planId })
                ?? store.currentTrainee.flatMap({ store.assignedPlan(for: $0) }),
           let day = session.dayId.flatMap({ id in plan.days.first(where: { $0.id == id }) })
                ?? plan.session(on: Date()) {
            resumeTarget = ResumeTarget(plan: plan, day: day)
        } else {
            celebrateStart = true
            showWorkouts = true
        }
    }

    // MARK: - Friction H: non-blocking profile completion nudge

    private var shouldShowProfileNudge: Bool {
        !dismissedProfileNudge && !store.profileSetupCompleted && store.session?.role == .trainee
    }

    @ViewBuilder private var profileCompletionNudge: some View {
        Button {
            TTHomeHaptics.light()
            showProfileCompletion = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Complete your profile")
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(.black)
                    Text("A few details help tailor your coaching.")
                        .font(TTFont.workSans(12, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    TTHomeHaptics.light()
                    withAnimation(.snappy(duration: 0.2)) { dismissedProfileNudge = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(white: 0.5))
                        .frame(width: 28, height: 28)
                        .background(Color(white: 0.95))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .ttHomeCardMorph()
        }
        .buttonStyle(TTHomeCardPressStyle())
    }

    // MARK: - Header

    private var darkHeader: some View {
        TTHomeProfileHeader(
            name: firstName,
            avatarSymbol: store.displayAvatarAsset,
            avatarUrl: store.remoteAvatarURL,
            avatarUserId: store.session?.userId,
            badgeCount: notificationStore.unreadCount,
            showsAIPro: store.aiEntitlement?.active == true,
            metrics: [
                TTHomeProfileMetric(
                    id: "health",
                    icon: .plus,
                    iconColor: orange,
                    text: hasRealHealthScore ? "\(healthScore)% Healthy" : "Complete a workout"
                ),
                TTHomeProfileMetric(
                    id: "member",
                    icon: .starFull,
                    iconColor: blue,
                    text: {
                        let goal = store.currentTrainee?.goal.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return goal.isEmpty ? "Trainee" : goal
                    }()
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
                        metricCard(title: "Score", value: hasRealHealthScore ? "\(healthScore)%" : "—", icon: "plus", tint: orange, chart: .ring)
                    }
                    .buttonStyle(TTHomeCardPressStyle())
                    .ttHomeCardMorph()

                    Button { showNutrition = true } label: {
                        metricCard(title: "Est. Hydration", value: "~\(hydrationMl) ml", icon: "drop.fill", tint: blue, chart: .wave)
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
        .padding(TTCardTokens.padding)
        .frame(width: 148, height: 148, alignment: .topLeading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    // MARK: - Today's Workout (primary CTA)

    private var todayWorkoutSection: some View {
        let plan = store.currentTrainee.flatMap { store.assignedPlan(for: $0) }
        let session = plan?.session(on: selectedDay) ?? plan?.nextSession(from: selectedDay)
        let minutes = session?.durationMinutes ?? plan?.durationMinutes ?? 25
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

                TTHomeHeroSheen()

                // Top-left: duration + optional "Done" badge in brand style
                HStack(spacing: 6) {
                    TTCardBadge(text: "\(minutes) Min")
                    if hasCompletedTodayWorkout {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Done today")
                                .font(TTFont.workSans(12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .padding(TTCardTokens.padding)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hasCompletedTodayWorkout)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: TTCardTokens.listSpacing) {
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
                            progress: plan == nil ? 0 : min(1, Double(series) / 8.0),
                            tint: .white,
                            lineWidth: 5,
                            size: 48,
                            label: plan == nil ? "—" : "\(series)"
                        )
                    }
                    .padding(TTCardTokens.padding)
                }

                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        TTCardActionButton(systemImage: hasCompletedTodayWorkout ? "arrow.clockwise" : "play.fill")
                            .padding(TTCardTokens.padding)
                            .padding(.bottom, 56)
                    }
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            .ttHomeCardMorph()

            if plan != nil {
                if hasCompletedTodayWorkout {
                    // Primary: view — secondary ghost: go again
                    VStack(spacing: 10) {
                        Button {
                            TTHomeHaptics.light()
                            showWorkoutOverview = true
                        } label: {
                            Text("View today’s workout")
                                .font(TTFont.workSans(15, weight: .semibold))
                                .foregroundStyle(Color(white: 0.25))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color(white: 0.93))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(TTHomeCardPressStyle())

                        Button {
                            TTHomeHaptics.medium()
                            celebrateStart = true
                            showWorkoutOverview = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Go again")
                                    .font(TTFont.workSans(13, weight: .semibold))
                            }
                            .foregroundStyle(orange)
                        }
                        .buttonStyle(.plain)
                        .ttHomeWin(celebrate: $celebrateStart, tint: orange)
                    }
                } else {
                    let hasActiveSession = store.activeWorkoutSession != nil
                    Button {
                        if hasActiveSession {
                            // Friction E: resume the live session instead of the hub overview.
                            continueWorkout()
                        } else {
                            TTHomeHaptics.medium()
                            celebrateStart = true
                            if session != nil {
                                showWorkoutOverview = true
                            } else {
                                showWorkoutOverview = true
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: hasActiveSession ? "arrow.right.circle.fill" : "play.fill")
                                .font(TTFont.workSans(14, weight: .semibold))
                            Text(hasActiveSession ? "Continue Workout" : session == nil ? "See My Workouts" : "Start Today’s Workout")
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
                    .ttHomeWin(celebrate: $celebrateStart, tint: orange)
                }
            } else if store.hasLinkedTrainer {
                // Friction B/N (§2e): linked coach but no plan assigned yet — explain, don't go silent.
                // Neutral copy only; no AI-generate CTA here (correctly gated off).
                coachAwaitingPlanCard
            } else if !store.canShowSoloAIGenerate {
                // No trainer and solo-AI unavailable: steer to discovery (avoids two competing CTAs).
                Button {
                    TTHomeHaptics.medium()
                    showFindCoaches = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .font(TTFont.workSans(14, weight: .semibold))
                        Text("Find a coach to get workouts")
                            .font(TTFont.textLG(.semibold))
                    }
                    .foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(white: 0.93))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TTHomeCardPressStyle())
            }
        }
    }

    // MARK: - Solo AI generate (no trainer)

    private var soloAIGenerateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Train with AI") {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(orange)
                    Text("Your AI Training Week")
                        .font(TTFont.workSans(17, weight: .bold))
                        .foregroundStyle(.black)
                    Spacer(minLength: 0)
                }

                Text("We'll use your fitness assessment to build a personalised week of training.")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(Color(white: 0.4))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    TTHomeHaptics.medium()
                    showAssessmentReview = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(TTFont.workSans(14, weight: .semibold))
                        Text("Build my plan")
                            .font(TTFont.textLG(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TTHomeCardPressStyle())
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .ttHomeCardMorph()
        }
    }

    // MARK: - Coach assigned, awaiting first plan (friction B/N §2e)

    private var coachAwaitingPlanCard: some View {
        let coachName = store.currentTrainee
            .flatMap { store.trainer(for: $0)?.userId }
            .flatMap { id in store.users.first { $0.id == id }?.name }?
            .components(separatedBy: " ").first ?? "Your coach"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(orange)
                Text("\(coachName) guides your training")
                    .font(TTFont.workSans(16, weight: .bold))
                    .foregroundStyle(.black)
                Spacer(minLength: 0)
            }

            Text("Waiting for \(coachName) to assign your first plan. You’ll be notified when it’s ready.")
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(Color(white: 0.4))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                TTHomeHaptics.light()
                showProfile = true
            } label: {
                HStack(spacing: 8) {
                    Text("View coach")
                        .font(TTFont.workSans(14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(white: 0.25))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(TTHomeCardPressStyle())
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .ttHomeCardMorph()
    }

    private func flashGenerateNotice(_ text: String) {
        withAnimation(.snappy(duration: 0.25)) {
            generateNotice = text
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    generateNotice = nil
                }
            }
        }
    }

    // MARK: - Get Started (shown before first workout / meal / trainer)

    private var getStartedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(orange)
                    Text("Set yourself up for success")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(.black)
                }
                Text("Log your first workout or meal and your nutrition, coach notes, and form insights will appear here.")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button {
                    TTHomeHaptics.medium()
                    showNutrition = true
                } label: {
                    Text("Log a meal")
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(orange)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(white: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TTHomeCardPressStyle())

                Button {
                    TTHomeHaptics.medium()
                    showFindCoaches = true
                } label: {
                    Text("Find a coach")
                        .font(TTFont.workSans(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(TTHomeCardPressStyle())
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .ttHomeCardMorph()
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
            TTMediaActivityCard(
                badge: empty ? nil : "\(minutes) Min",
                actionSystemImage: empty ? "plus" : "arrow.right",
                showsAction: true
            ) {
                Image("OnboardingNutrition")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name)
                        .font(TTFont.workSans(TTCardTokens.titleSize, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(2)

                    if empty {
                        Label("Scan or add a meal", systemImage: "fork.knife")
                            .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .medium))
                            .foregroundStyle(TTColor.inkMuted)
                    } else {
                        Text("\(calories) kcal · \(protein)g protein · \(fat)g fat")
                            .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .medium))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 220)
            .ttHomeCardMorph()
        }
        .buttonStyle(TTHomeCardPressStyle())
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
                            Label(deltaLabel(delta), systemImage: delta >= 0 ? "flame.fill" : "arrow.down")
                                .font(TTFont.workSans(13, weight: .semibold))
                                .foregroundStyle(delta >= 0 ? orange : Color(white: 0.45))

                            if suggestions > 0 {
                                Label("\(suggestions) tips ready", systemImage: "lightbulb.fill")
                                    .font(TTFont.workSans(13, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                        }
                    }

                    Spacer()

                    TTHomeProgressRing(
                        progress: hasRealHealthScore ? Double(healthScore) / 100.0 : 0,
                        tint: orange,
                        lineWidth: 6,
                        size: 52,
                        label: hasRealHealthScore ? "\(healthScore)" : "—"
                    )
                }
            }
            .padding(TTCardTokens.padding)
            .background(TTCardTokens.mediaFillLight)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
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
                Button("Find Coaches") {
                    TTHomeHaptics.light()
                    showFindCoaches = true
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
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 22))
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
                                        Label("\(report.repCount) reps", systemImage: "figure.strengthtraining.traditional")
                                        Label("\(report.cues.count) tips", systemImage: "lightbulb.fill")
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

    // MARK: - Zone label

    private func traineZoneLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(orange)
                .frame(width: 3, height: 13)
            Text(title.uppercased())
                .font(TTFont.workSans(12, weight: .bold))
                .foregroundStyle(Color(white: 0.28))
                .kerning(1.0)
        }
        .padding(.top, 28)
        .padding(.bottom, 10)
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


    // Only show a real score — never a placeholder number that misleads the user
    private var hasRealHealthScore: Bool {
        store.currentTrainee.map { !store.formReports(for: $0.id).isEmpty } ?? false
    }

    private var healthScore: Int {
        guard let score = store.currentTrainee.flatMap({ store.formReports(for: $0.id).first?.score }) else {
            return 0
        }
        return min(max(score, 1), 99)
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

    private var hasCompletedTodayWorkout: Bool {
        guard let trainee = store.currentTrainee else { return false }
        return store.logs(for: trainee.id).contains {
            Calendar.current.isDateInToday($0.completedAt)
        }
    }

    // Show Health & Support zone only once the user has real activity or a trainer
    private var hasMeaningfulActivity: Bool {
        guard let trainee = store.currentTrainee else { return false }
        return store.logs(for: trainee.id).count > 0
            || store.formReports(for: trainee.id).count > 0
            || store.trainer(for: trainee) != nil
            || !(store.meals(for: trainee.id, on: Date()).isEmpty)
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
        if abs(delta) < 50 { return "On track this week" }
        return delta > 0 ? "Ahead of last week" : "Behind last week"
    }

    private func exerciseTitle(for exerciseId: String) -> String {
        if let name = store.exercise(id: exerciseId)?.name, !name.isEmpty {
            return name
        }
        return "Form check"
    }
}

// MARK: - Resume target (friction E)

/// Identifiable wrapper so Home can push `ActiveWorkoutView` for the resolved session day.
private struct ResumeTarget: Identifiable, Hashable {
    let plan: WorkoutPlan
    let day: PlanDay
    var id: String { "\(plan.id)#\(day.id)" }
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
