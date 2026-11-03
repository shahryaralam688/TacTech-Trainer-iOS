import SwiftUI

// MARK: - Workout Overview Screen

struct WorkoutOverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    
    let plan: WorkoutPlan
    @State private var selectedDay = Date()
    @State private var showFullCalendar = false
    @State private var expandedExerciseIds: Set<String> = []
    
    private let canvas = Color(white: 0.97)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let orange = TTColor.actionOrange
    
    private var session: PlanDay? {
        plan.session(on: selectedDay)
    }
    
    private var exercises: [WorkoutExercise] {
        session?.exercises ?? []
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        workoutHeaderSection
                        calendarSection
                        sessionCardSection
                        
                        if let session = session {
                            if let warmup = session.warmup, !warmup.isEmpty {
                                warmupSection(warmup)
                            }
                            
                            if !exercises.isEmpty {
                                exercisesSection
                            }
                            
                            if let cooldown = session.cooldown, !cooldown.isEmpty {
                                cooldownSection(cooldown)
                            }
                        }
                        
                        liveFormSection
                    }
                    .padding(.horizontal, TTSpace.screen)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
                .ttTopRoundedSheet(radius: TTSheetChrome.pageTopRadius, fill: canvas)
            }
            .background(charcoal.ignoresSafeArea(edges: .top))
            .ttHideSystemNavigationBar()
            .ttSyncRootTabBarWithNavigationDepth()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        TTDarkPageHeader(title: "Workout Overview") {
            dismiss()
        }
    }
    
    // MARK: - Workout Header Section
    
    private var workoutHeaderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(plan.title)
                    .font(TTFont.workSans(24, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                
                Text(plan.level.capitalized)
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(orange.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            Text(scheduleDisplay)
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }
    
    private var scheduleDisplay: String {
        let scheduled = plan.scheduledDays
        if scheduled.isEmpty { return "\(plan.daysPerWeek)× per week" }
        let allTBD = scheduled.allSatisfy { $0.startTime == nil }
        if allTBD {
            return scheduled.map { $0.weekday.short }.joined(separator: " · ")
        }
        return plan.scheduleLine
    }
    
    // MARK: - Calendar Section
    
    private var calendarSection: some View {
        TTHomeWeekDatePicker(
            selected: $selectedDay,
            accent: orange,
            sessionDayKeys: sessionDayKeySet(plan)
        )
    }
    
    private func sessionDayKeySet(_ plan: WorkoutPlan) -> Set<String> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var keys = Set<String>()
        for offset in -7...28 {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            if plan.session(on: date) != nil {
                let c = cal.dateComponents([.year, .month, .day], from: date)
                keys.insert("\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)")
            }
        }
        return keys
    }
    
    // MARK: - Session Card Section
    
    private var sessionCardSection: some View {
        Group {
            if let session = session {
                let isPast = selectedDay < Calendar.current.startOfDay(for: Date())
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(relativeDayLabel(for: session.weekday))
                        .font(TTFont.caption(11))
                        .fontWeight(.bold)
                        .tracking(0.8)
                        .foregroundStyle(isPast ? TTColor.inkSubtle : orange)
                    
                    Text(session.title)
                        .font(TTFont.workSans(20, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                    
                    HStack(spacing: 8) {
                        Label(session.timeLabel, systemImage: "clock")
                        Label("\(session.durationMinutes) min", systemImage: "timer")
                        Label(session.location ?? "Gym", systemImage: "location")
                    }
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(TTColor.inkMuted)
                    
                    if isPast {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(TTColor.inkSubtle)
                            Text("This session has passed")
                                .font(TTFont.workSans(13, weight: .medium))
                                .foregroundStyle(TTColor.inkSubtle)
                        }
                        .padding(.top, 2)
                    } else {
                        NavigationLink {
                            ActiveWorkoutView(plan: plan, day: session)
                        } label: {
                            Text("Start Session")
                                .font(TTFont.workSans(16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(orange)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("REST DAY")
                        .font(TTFont.caption(11))
                        .fontWeight(.bold)
                        .tracking(0.8)
                        .foregroundStyle(TTColor.inkSubtle)
                    
                    Text("No workout scheduled")
                        .font(TTFont.workSans(16, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                    
                    if let next = plan.nextSession(from: selectedDay) {
                        Text("Next: \(relativeDayLabel(for: next.weekday)) · \(next.focus)")
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(TTColor.inkSubtle)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
            }
        }
    }
    
    private func relativeDayLabel(for weekday: Weekday) -> String {
        let todayIdx = Weekday.from(date: Date()).sortIndex
        let targetIdx = weekday.sortIndex
        switch (targetIdx - todayIdx + 7) % 7 {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 6: return "Yesterday"
        default: return weekday.title
        }
    }
    
    // MARK: - Warm-up Section
    
    private func warmupSection(_ warmup: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warm-up")
                .font(TTFont.workSans(16, weight: .semibold))
                .foregroundStyle(TTColor.ink)
            
            Text(warmup)
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }
    
    // MARK: - Exercises Section
    
    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(TTFont.workSans(16, weight: .semibold))
                .foregroundStyle(TTColor.ink)
            
            VStack(spacing: 10) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    exerciseCard(exercise, index: index)
                }
            }
        }
    }
    
    private func exerciseCard(_ exercise: WorkoutExercise, index: Int) -> some View {
        let isExpanded = expandedExerciseIds.contains(exercise.id)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let exerciseData = store.exercise(id: exercise.exerciseId) {
                    Text("\(index + 1)")
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(orange)
                        .frame(width: 32, height: 32)
                        .background(orange.opacity(0.12))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exerciseData.name)
                            .font(TTFont.workSans(15, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                        
                        Text(exercise.prescriptionLine)
                            .font(TTFont.workSans(13, weight: .medium))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    
                    Spacer(minLength: 0)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedExerciseIds.remove(exercise.id)
                            } else {
                                expandedExerciseIds.insert(exercise.id)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isExpanded {
                if let exerciseData = store.exercise(id: exercise.exerciseId) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !exerciseData.cues.isEmpty {
                            Text(exerciseData.cues.joined(separator: "\n"))
                                .font(TTFont.workSans(13, weight: .medium))
                                .foregroundStyle(TTColor.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        if let notes = exercise.notes, !notes.isEmpty {
                            Text(notes)
                                .font(TTFont.workSans(13, weight: .medium))
                                .foregroundStyle(TTColor.inkSubtle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    // MARK: - Cool-down Section
    
    private func cooldownSection(_ cooldown: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cool-down")
                .font(TTFont.workSans(16, weight: .semibold))
                .foregroundStyle(TTColor.ink)
            
            Text(cooldown)
                .font(TTFont.workSans(14, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }
    
    // MARK: - Live Form Section
    
    private var liveFormSection: some View {
        NavigationLink {
            LiveFormCorrectionView(
                initialExerciseId: exercises.first?.exerciseId
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(orange)
                    .frame(width: 36, height: 36)
                    .background(orange.opacity(0.12))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Form Correction")
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(TTColor.ink)
                    
                    Text("Get real-time feedback on your form")
                        .font(TTFont.workSans(13, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                }
                
                Spacer(minLength: 0)
                
                TTChevronForward()
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
