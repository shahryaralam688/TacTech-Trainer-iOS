import AVFoundation
import Charts
import ImageIO
import PhotosUI
import SwiftUI
import Vision

enum NutHistoryRange: Int, CaseIterable, Identifiable {
    case days = 0
    case weeks = 1
    case months = 2
    var id: Int { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .days: "Days"
        case .weeks: "Weeks"
        case .months: "Months"
        }
    }
    var apiPeriod: String {
        switch self {
        case .days: "day"
        case .weeks: "week"
        case .months: "month"
        }
    }
    var fetchDays: Int {
        switch self {
        case .days: 7
        case .weeks: 42
        case .months: 60
        }
    }
}

extension NutritionView {

    struct NutHistoryBucket: Identifiable {
        let id: String
        let shortLabel: String
        let title: String
        let daysLogged: Int
        let avgCalories: Int
        let totalCalories: Int
        let daysOverGoal: Int
        let avgProtein: Double
        let avgCarbs: Double
        let avgFat: Double
        let meals: [Meal]
    }

    func recomputeHistoryBuckets() {
        cachedHistoryBuckets = computeHistoryBuckets()
    }

    func invalidateHistoryCache() {
        summaryByPeriod.removeAll()
        loadedHistoryDays = 0
        cachedHistoryBuckets = []
        historyLoadFailed = false
        if tab == .history {
            recomputeHistoryBuckets()
        }
    }

    private func computeHistoryBuckets() -> [NutHistoryBucket] {
        if let remoteBuckets = summaryByPeriod[historyRange]?.buckets, !remoteBuckets.isEmpty {
            return remoteBuckets.enumerated().map { idx, b in
                let meals = (b.meals ?? []).filter { !$0.isPlanned }.sorted { $0.eatenAt > $1.eatenAt }
                let avg = b.avgCalories ?? b.totalCalories ?? 0
                let total = b.totalCalories ?? (avg * max(1, b.daysLogged ?? 1))
                return NutHistoryBucket(
                    id: "remote-\(historyRange.rawValue)-\(idx)",
                    shortLabel: b.label,
                    title: b.title ?? b.label,
                    daysLogged: b.daysLogged ?? (meals.isEmpty ? 0 : 1),
                    avgCalories: avg,
                    totalCalories: total,
                    daysOverGoal: b.daysOverGoal ?? 0,
                    avgProtein: b.avgProtein ?? meals.reduce(0.0) { $0 + $1.macros.protein },
                    avgCarbs: b.avgCarbs ?? meals.reduce(0.0) { $0 + $1.macros.carbs },
                    avgFat: b.avgFat ?? meals.reduce(0.0) { $0 + $1.macros.fat },
                    meals: meals
                )
            }
        }
        guard let id = traineeId else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let allEaten = store.meals.filter { $0.traineeId == id && !$0.isPlanned }

        switch historyRange {
        case .days:
            return (0..<7).reversed().compactMap { offset -> NutHistoryBucket? in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                let dayMeals = allEaten.filter { calendar.isDate($0.eatenAt, inSameDayAs: date) }
                    .sorted { $0.eatenAt > $1.eatenAt }
                let kcal = dayMeals.reduce(0) { $0 + $1.macros.calories }
                let p = dayMeals.reduce(0.0) { $0 + $1.macros.protein }
                let c = dayMeals.reduce(0.0) { $0 + $1.macros.carbs }
                let f = dayMeals.reduce(0.0) { $0 + $1.macros.fat }
                let short = offset == 0 ? String(localized: "Today") : date.formatted(.dateTime.weekday(.abbreviated))
                let title: String
                if offset == 0 {
                    title = String(localized: "Today so far")
                } else if offset == 1 {
                    title = String(localized: "Yesterday, ") + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                } else {
                    title = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }
                return NutHistoryBucket(
                    id: "day-\(offset)",
                    shortLabel: short,
                    title: title,
                    daysLogged: dayMeals.isEmpty ? 0 : 1,
                    avgCalories: kcal,
                    totalCalories: kcal,
                    daysOverGoal: (goal > 0 && kcal > goal) ? 1 : 0,
                    avgProtein: p,
                    avgCarbs: c,
                    avgFat: f,
                    meals: dayMeals
                )
            }

        case .weeks:
            let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            return (0..<6).reversed().compactMap { weekOffset -> NutHistoryBucket? in
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: startOfThisWeek),
                      let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else { return nil }
                let weekMeals = allEaten.filter { $0.eatenAt >= weekStart && $0.eatenAt <= min(Date(), calendar.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd) ?? weekEnd) }
                let byDay = Dictionary(grouping: weekMeals) { calendar.startOfDay(for: $0.eatenAt) }
                let dayTotals = byDay.values.map { meals in
                    (
                        kcal: meals.reduce(0) { $0 + $1.macros.calories },
                        p: meals.reduce(0.0) { $0 + $1.macros.protein },
                        c: meals.reduce(0.0) { $0 + $1.macros.carbs },
                        f: meals.reduce(0.0) { $0 + $1.macros.fat }
                    )
                }
                let logged = dayTotals.count
                let totalKcal = dayTotals.reduce(0) { $0 + $1.kcal }
                let avgKcal = logged > 0 ? totalKcal / logged : 0
                let over = goal > 0 ? dayTotals.filter { $0.kcal > goal }.count : 0
                let short = weekOffset == 0 ? String(localized: "This wk") : weekStart.formatted(.dateTime.day().month(.abbreviated))
                let title = weekOffset == 0
                    ? "\(weekStart.formatted(.dateTime.weekday(.abbreviated).day())) – \(String(localized: "today"))"
                    : "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(weekEnd.formatted(.dateTime.day().month(.abbreviated)))"
                return NutHistoryBucket(
                    id: "wk-\(weekOffset)",
                    shortLabel: short,
                    title: title,
                    daysLogged: logged,
                    avgCalories: avgKcal,
                    totalCalories: totalKcal,
                    daysOverGoal: over,
                    avgProtein: logged > 0 ? dayTotals.reduce(0) { $0 + $1.p } / Double(logged) : 0,
                    avgCarbs: logged > 0 ? dayTotals.reduce(0) { $0 + $1.c } / Double(logged) : 0,
                    avgFat: logged > 0 ? dayTotals.reduce(0) { $0 + $1.f } / Double(logged) : 0,
                    meals: weekMeals
                )
            }

        case .months:
            let startOfThisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            return (0..<6).reversed().compactMap { monthOffset -> NutHistoryBucket? in
                guard let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: startOfThisMonth),
                      let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else { return nil }
                let monthMeals = allEaten.filter { $0.eatenAt >= monthInterval.start && $0.eatenAt < monthInterval.end }
                let byDay = Dictionary(grouping: monthMeals) { calendar.startOfDay(for: $0.eatenAt) }
                let dayTotals = byDay.values.map { meals in
                    (
                        kcal: meals.reduce(0) { $0 + $1.macros.calories },
                        p: meals.reduce(0.0) { $0 + $1.macros.protein },
                        c: meals.reduce(0.0) { $0 + $1.macros.carbs },
                        f: meals.reduce(0.0) { $0 + $1.macros.fat }
                    )
                }
                let logged = dayTotals.count
                let totalKcal = dayTotals.reduce(0) { $0 + $1.kcal }
                let avgKcal = logged > 0 ? totalKcal / logged : 0
                let over = goal > 0 ? dayTotals.filter { $0.kcal > goal }.count : 0
                let short = monthStart.formatted(.dateTime.month(.abbreviated))
                let title = monthOffset == 0
                    ? "\(monthStart.formatted(.dateTime.month(.wide))) \(String(localized: "so far"))"
                    : monthStart.formatted(.dateTime.month(.wide).year())
                return NutHistoryBucket(
                    id: "mo-\(monthOffset)",
                    shortLabel: short,
                    title: title,
                    daysLogged: logged,
                    avgCalories: avgKcal,
                    totalCalories: totalKcal,
                    daysOverGoal: over,
                    avgProtein: logged > 0 ? dayTotals.reduce(0) { $0 + $1.p } / Double(logged) : 0,
                    avgCarbs: logged > 0 ? dayTotals.reduce(0) { $0 + $1.c } / Double(logged) : 0,
                    avgFat: logged > 0 ? dayTotals.reduce(0) { $0 + $1.f } / Double(logged) : 0,
                    meals: monthMeals
                )
            }
        }
    }

    var historyBody: some View {
        let buckets = cachedHistoryBuckets
        let activeIndex = min(selectedBucketIndex ?? max(0, buckets.count - 1), max(0, buckets.count - 1))
        let selected = buckets.isEmpty ? nil : buckets[activeIndex]
        let nonZero = buckets.filter { $0.avgCalories > 0 }
        let avgAll = nonZero.isEmpty ? 0 : nonZero.reduce(0) { $0 + $1.avgCalories } / nonZero.count
        let onTarget = goal > 0 ? buckets.filter { $0.avgCalories > 0 && $0.avgCalories <= goal }.count : 0
        let highest = buckets.max(by: { $0.avgCalories < $1.avgCalories })

        return VStack(alignment: .leading, spacing: 10) {
            if showHistorySkeleton && buckets.allSatisfy({ $0.meals.isEmpty && $0.avgCalories == 0 }) {
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(NutStyle.orange.opacity(0.25))
                        .frame(height: 310)
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(NutStyle.field)
                                .frame(height: 68)
                        }
                    }
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(NutStyle.field)
                        .frame(height: 150)
                }
                .redacted(reason: .placeholder)
                .padding(.top, 10)
            } else if historyLoadFailed && buckets.allSatisfy({ $0.meals.isEmpty && $0.avgCalories == 0 }) {
                TTLoadError(
                    title: "Couldn’t load history",
                    message: "Check your connection and try again."
                ) {
                    Task { await loadHistory() }
                }
                .padding(.top, 24)
            } else if let selected {
                historyHeroCard(buckets: buckets, selectedIndex: activeIndex, selected: selected)
                historyStatsRow(
                    avgKcal: avgAll,
                    onTargetText: "\(onTarget) of \(max(1, nonZero.count))",
                    highestLabel: highest?.avgCalories ?? 0 > 0 ? (highest?.shortLabel ?? "—") : "—"
                )
                historyDetailCard(selected: selected)
            }
        }
        .task(id: historyRange) {
            barsGrown = false
            await loadHistory()
            withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7)) {
                barsGrown = true
            }
        }
    }

    private func historyHeroCard(buckets: [NutHistoryBucket], selectedIndex: Int, selected: NutHistoryBucket) -> some View {
        let maxBar = max(Double(max(goal, 1)) * 1.25, Double(buckets.map(\.avgCalories).max() ?? 0) * 1.12)
        let goalRatio = goal > 0 ? min(1.0, Double(goal) / maxBar) : 0
        let diff = selected.avgCalories - goal
        let isOver = goal > 0 && diff > 0

        return VStack(alignment: .leading, spacing: 0) {
            // Sliding Days | Weeks | Months pill switch
            HStack(spacing: 0) {
                ForEach(NutHistoryRange.allCases) { range in
                    Button {
                        guard historyRange != range else { return }
                        selectedBucketIndex = nil
                        barsGrown = false
                        withAnimation(reduceMotion ? nil : NutStyle.ease) {
                            historyRange = range
                        }
                    } label: {
                        Text(range.title)
                            .font(TTFont.workSans(14, weight: .semibold))
                            .foregroundStyle(historyRange == range ? NutStyle.accentText : .white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: (geo.size.width - 6) / 3, height: geo.size.height - 6)
                        .offset(x: 3 + CGFloat(historyRange.rawValue) * ((geo.size.width - 6) / 3), y: 3)
                        .animation(reduceMotion ? nil : NutStyle.ease, value: historyRange)
                }
            }
            .background(Color.white.opacity(0.22))
            .clipShape(Capsule())

            Text(verbatim: selected.title)
                .font(TTFont.workSans(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 12)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                NutCountUpText(
                    target: selected.avgCalories,
                    suffix: historyRange == .days ? " kcal" : " kcal / day",
                    reduceMotion: reduceMotion
                )
                .font(TTFont.workSans(34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            }
            .padding(.top, 2)

            if goal > 0 {
                Text(isOver
                     ? "\(diff.formatted()) kcal over goal"
                     : "\(abs(diff).formatted()) kcal under goal")
                    .font(TTFont.workSans(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isOver ? NutStyle.charcoal : Color.white.opacity(0.22))
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }

            // Interactive animated bars + dashed goal line
            ZStack(alignment: .bottom) {
                if goal > 0 {
                    GeometryReader { geo in
                        let barAreaHeight = geo.size.height - 24
                        let yOffset = barAreaHeight * (1 - goalRatio)
                        ZStack(alignment: .topTrailing) {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: 0))
                                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                            }
                            .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .frame(height: 2)

                            Text("Goal \(goal.formatted())")
                                .font(TTFont.workSans(11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(NutStyle.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .offset(y: -16)
                        }
                        .offset(y: yOffset)
                    }
                    .allowsHitTesting(false)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        let isSelected = index == selectedIndex
                        let over = goal > 0 && bucket.avgCalories > goal
                        let ratio = maxBar > 0 ? min(1.0, Double(bucket.avgCalories) / maxBar) : 0
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                selectedBucketIndex = index
                            }
                        } label: {
                            VStack(spacing: 4) {
                                GeometryReader { barGeo in
                                    let targetH = max(bucket.avgCalories > 0 ? 6 : 0, barGeo.size.height * ratio)
                                    VStack {
                                        Spacer(minLength: 0)
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(over ? NutStyle.charcoal : Color.white)
                                            .opacity(isSelected ? 1.0 : (over ? 0.6 : 0.5))
                                            .frame(maxWidth: 36)
                                            .frame(height: barsGrown ? targetH : 0)
                                            .animation(
                                                reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7).delay(Double(index) * 0.045),
                                                value: barsGrown
                                            )
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .frame(height: 140)

                                Text(verbatim: bucket.shortLabel)
                                    .font(TTFont.workSans(11, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .frame(height: 20)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 164)
            .padding(.top, 12)
        }
        .padding(14)
        .background(NutStyle.orange)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 10)
    }

    private func historyStatsRow(avgKcal: Int, onTargetText: String, highestLabel: String) -> some View {
        HStack(spacing: 8) {
            historyStatTile(value: avgKcal.formatted(), label: "average kcal")
            historyStatTile(value: onTargetText, label: "on target")
            historyStatTile(value: highestLabel, label: "highest")
        }
    }

    private func historyStatTile(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(TTFont.workSans(18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(TTFont.workSans(12, weight: .regular))
                .foregroundStyle(NutStyle.mute)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func historyDetailCard(selected: NutHistoryBucket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if historyRange == .days {
                Text("What you ate")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(NutStyle.mute)
                if selected.meals.isEmpty {
                    Text("Nothing logged yet.")
                        .font(TTFont.body(14))
                        .foregroundStyle(NutStyle.mute)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(selected.meals.enumerated()), id: \.element.id) { idx, meal in
                        entryRow(meal, first: idx == 0)
                    }
                }
            } else {
                Text("Total \(selected.totalCalories.formatted()) kcal · \(selected.daysLogged) days logged · over goal on \(selected.daysOverGoal) of \(selected.daysLogged) days")
                    .font(TTFont.workSans(13, weight: .regular))
                    .foregroundStyle(NutStyle.mute)
                Text("Average per day")
                    .font(TTFont.workSans(13, weight: .medium))
                    .foregroundStyle(NutStyle.mute)
                    .padding(.top, 4)
                HStack(spacing: 10) {
                    historyMacroBar("Protein", value: selected.avgProtein, share: selected.avgProtein / 120)
                    historyMacroBar("Carbs", value: selected.avgCarbs, share: selected.avgCarbs / 170)
                    historyMacroBar("Fat", value: selected.avgFat, share: selected.avgFat / 55)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NutStyle.field)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selected.id)
    }

    private func historyMacroBar(_ title: LocalizedStringKey, value: Double, share: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer(minLength: 2)
                Text(verbatim: "\(Int(value.rounded())) g").monospacedDigit()
            }
            .font(TTFont.workSans(12, weight: .medium))
            .foregroundStyle(TTColor.ink)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 228 / 255, green: 228 / 255, blue: 231 / 255))
                    Capsule().fill(NutStyle.orange)
                        .frame(width: geo.size.width * min(1, max(0, share)))
                        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: value)
                }
            }
            .frame(height: 6)
        }
    }

    func loadHistory() async {
        guard let id = traineeId else {
            recomputeHistoryBuckets()
            return
        }
        let range = historyRange
        if summaryByPeriod[range] != nil {
            recomputeHistoryBuckets()
            return
        }

        isLoadingHistory = true
        historyLoadFailed = false
        var skeletonShownAt: Date?
        let skeletonTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !Task.isCancelled && isLoadingHistory {
                skeletonShownAt = Date()
                showHistorySkeleton = true
            }
        }
        defer {
            skeletonTask.cancel()
            isLoadingHistory = false
            showHistorySkeleton = false
        }

        var hadSuccess = false
        if let summary = await store.fetchMealSummary(period: range.apiPeriod),
           !(summary.buckets ?? []).isEmpty {
            if !Task.isCancelled {
                summaryByPeriod[range] = summary
                hadSuccess = true
            }
        } else {
            let targetDays = range.fetchDays
            if loadedHistoryDays < targetDays {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let start = loadedHistoryDays
                let anyOk = await withTaskGroup(of: Bool.self) { group in
                    for offset in start..<targetDays {
                        guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                        let queryDate = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) ?? dayStart
                        group.addTask {
                            await store.refreshDay(for: id, on: queryDate)
                        }
                    }
                    var ok = false
                    for await result in group where result { ok = true }
                    return ok
                }
                if !Task.isCancelled {
                    if anyOk {
                        loadedHistoryDays = max(loadedHistoryDays, targetDays)
                        hadSuccess = true
                    }
                }
            } else {
                hadSuccess = true
            }
        }

        if let shownAt = skeletonShownAt {
            let elapsed = Date().timeIntervalSince(shownAt)
            if elapsed < 0.4 {
                try? await Task.sleep(nanoseconds: UInt64((0.4 - elapsed) * 1_000_000_000))
            }
        }
        if !Task.isCancelled {
            recomputeHistoryBuckets()
            if !hadSuccess && cachedHistoryBuckets.allSatisfy({ $0.meals.isEmpty && $0.avgCalories == 0 }) {
                historyLoadFailed = true
            }
        }
    }
}
