import Charts
import SwiftUI

/// Trainer discovery analytics — views, contacts, impressions, Boost ROI context.
struct TrainerCoachAnalyticsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var period: AnalyticsPeriod = .month
    @State private var analytics: CoachAnalyticsResponse?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var missingProfile = false
    @State private var chartMetric: ChartMetric = .views
    @State private var showBoostStore = false
    @State private var showProfileEditor = false
    @State private var toast: TTToastMessage?
    @State private var didResetPeriodForValidation = false

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private enum ChartMetric: String, CaseIterable, Identifiable {
        case views, contacts, impressions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .views: "Views"
            case .contacts: "Contacts"
            case .impressions: "Impressions"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(
                    title: "Insights",
                    subtitle: "Discovery performance",
                    background: .white
                )

                if store.session?.role != .trainer {
                    forbiddenState
                } else if isLoading && analytics == nil && !missingProfile {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if missingProfile {
                    missingProfileState
                } else if let loadError, analytics == nil {
                    errorState(loadError)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            periodPicker
                            if let analytics {
                                boostStrip(analytics)
                                kpiGrid(analytics.totals)
                                privacyNote
                                chartCard(analytics)
                                if isAllZero(analytics.totals) {
                                    emptyHint
                                }
                            }
                        }
                        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                        .padding(.top, TTModalSheetChrome.contentTopPadding)
                        .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
                    }
                    .refreshable { await load() }
                }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .ttToast($toast, bottomInset: 28)
            .task { await load() }
            .onChange(of: period) { _, _ in
                didResetPeriodForValidation = false
                Task { await load() }
            }
            .sheet(isPresented: $showBoostStore) {
                TrainerBoostStoreView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showProfileEditor) {
                CoachPublicProfileEditorView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(AnalyticsPeriod.allCases) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Analytics period")
    }

    private func boostStrip(_ analytics: CoachAnalyticsResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(TTColor.actionOrange)
                VStack(alignment: .leading, spacing: 4) {
                    if analytics.boost.activeNow {
                        HStack(spacing: 8) {
                            Text("Boost active")
                                .font(TTFont.heading(15))
                            CoachBoostBadge()
                        }
                        if let ends = analytics.boost.endsAt {
                            Text("Until \(ends.formatted(date: .abbreviated, time: .shortened))")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                    } else {
                        Text("Boost inactive")
                            .font(TTFont.heading(15))
                        Text("Feature your profile to climb Find Coaches.")
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }

            Text("Boost active \(analytics.totals.boostActiveDays) of \(analytics.periodDays) days")
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.inkMuted)

            Button {
                showBoostStore = true
            } label: {
                Text(analytics.boost.activeNow ? "Manage Boost" : "Get Featured")
                    .font(TTFont.heading(13))
                    .foregroundStyle(TTColor.actionOrange)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func kpiGrid(_ totals: CoachAnalyticsTotals) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            kpiCard(title: "Profile views", value: "\(totals.views)")
            kpiCard(title: "Unique viewers", value: "\(totals.uniqueViewers)")
            kpiCard(
                title: "Contacts",
                value: "\(totals.contacts)",
                caption: totals.contactsCreated > 0
                    ? "\(totals.contactsCreated) new thread\(totals.contactsCreated == 1 ? "" : "s")"
                    : nil
            )
            kpiCard(title: "Impressions", value: "\(totals.impressions)")
            kpiCard(
                title: "Rating",
                value: ratingValue(totals),
                spanTwo: true
            )
        }
    }

    private func kpiCard(
        title: String,
        value: String,
        caption: String? = nil,
        spanTwo: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            Text(value)
                .font(TTFont.heading(22))
                .foregroundStyle(TTColor.ink)
            if let caption {
                Text(caption)
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .gridCellColumns(spanTwo ? 2 : 1)
    }

    private var privacyNote: some View {
        Text("Views and contacts from Find Coaches. We don’t share who viewed your profile.")
            .font(TTFont.caption(12))
            .foregroundStyle(TTColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func chartCard(_ analytics: CoachAnalyticsResponse) -> some View {
        let points = chartPoints(from: analytics.series ?? [])
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily trend")
                    .font(TTFont.heading(15))
                Spacer()
                Picker("Metric", selection: $chartMetric) {
                    ForEach(ChartMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .tint(TTColor.actionOrange)
            }

            if points.isEmpty {
                Text("No daily data for this period yet.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(height: 160, alignment: .center)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(chartMetric.label, point.value)
                    )
                    .foregroundStyle(TTColor.actionOrange)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(chartMetric.label, point.value)
                    )
                    .foregroundStyle(TTColor.actionOrange.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, points.count / 6))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyHint: some View {
        Text("Share your public profile or Boost to get discovered")
            .font(TTFont.body(14))
            .foregroundStyle(TTColor.inkMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private var missingProfileState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
            Text("Set up your public coach profile")
                .font(TTFont.heading(18))
                .multilineTextAlignment(.center)
            Text("Insights appear once your discovery profile exists.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            TTButton(title: "Set up public profile") {
                showProfileEditor = true
            }
            .padding(.horizontal, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var forbiddenState: some View {
        VStack(spacing: 12) {
            Text("Trainer only")
                .font(TTFont.heading(18))
            Text("Discovery insights are available to trainers.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
            TTButton(title: "Close", style: .secondary) { dismiss() }
                .padding(.horizontal, 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { dismiss() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn’t load insights")
                .font(TTFont.heading(18))
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            TTButton(title: "Retry") {
                Task { await load() }
            }
            .padding(.horizontal, 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ratingValue(_ totals: CoachAnalyticsTotals) -> String {
        if totals.ratingCount > 0, let avg = totals.ratingAvg {
            return String(format: "★ %.1f (%d)", avg, totals.ratingCount)
        }
        return "No ratings yet"
    }

    private func isAllZero(_ totals: CoachAnalyticsTotals) -> Bool {
        totals.views == 0
            && totals.uniqueViewers == 0
            && totals.impressions == 0
            && totals.contacts == 0
            && totals.ratingCount == 0
    }

    private struct ChartPoint: Identifiable {
        var id: String { date.formatted(.iso8601.year().month().day()) }
        var date: Date
        var value: Int
    }

    private func chartPoints(from series: [CoachAnalyticsDay]) -> [ChartPoint] {
        series.compactMap { day in
            guard let date = day.chartDate else { return nil }
            let value: Int
            switch chartMetric {
            case .views: value = day.views
            case .contacts: value = day.contacts
            case .impressions: value = day.impressions
            }
            return ChartPoint(date: date, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    @MainActor
    private func load() async {
        guard store.session?.role == .trainer else {
            isLoading = false
            return
        }
        isLoading = analytics == nil
        loadError = nil
        missingProfile = false
        do {
            analytics = try await APIClient().fetchCoachAnalytics(periodDays: period.rawValue)
        } catch let error as AppError where error == .unauthorized {
            toast = TTToastMessage(text: error.localizedDescription, style: .error)
            dismiss()
        } catch let error as AppError where error.isNotFound {
            analytics = nil
            missingProfile = true
        } catch let error as AppError {
            if case .validation = error, period != .month, !didResetPeriodForValidation {
                didResetPeriodForValidation = true
                isLoading = false
                period = .month
                toast = TTToastMessage(
                    text: error.localizedDescription,
                    style: .error
                )
                return
            }
            if case .api = error, error.localizedDescription.lowercased().contains("not allow") {
                toast = TTToastMessage(text: error.localizedDescription, style: .error)
                dismiss()
                return
            }
            loadError = error.localizedDescription
            if analytics == nil {
                toast = TTToastMessage(
                    text: "Couldn’t load insights",
                    style: .error,
                    subtitle: error.localizedDescription
                )
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Compact 7D summary (home / profile)

struct TrainerDiscoveryInsightsStrip: View {
    @State private var summary: CoachAnalyticsResponse?
    @State private var showAnalytics = false
    @State private var showProfileEditor = false
    @State private var missingProfile = false

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    var body: some View {
        Group {
            if missingProfile {
                Button {
                    showProfileEditor = true
                } label: {
                    stripLabel(
                        title: "Insights",
                        subtitle: "Set up your public coach profile",
                        values: nil
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showAnalytics = true
                } label: {
                    stripLabel(
                        title: "Insights",
                        subtitle: "7-day discovery",
                        values: summary.map {
                            (
                                views: $0.totals.views,
                                contacts: $0.totals.contacts,
                                boostDays: $0.totals.boostActiveDays
                            )
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .task { await loadSummary() }
        .sheet(isPresented: $showAnalytics) {
            TrainerCoachAnalyticsView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .sheet(isPresented: $showProfileEditor) {
            CoachPublicProfileEditorView()
                .ttModalSheetPresentation(dragIndicator: .hidden)
        }
        .onChange(of: showProfileEditor) { _, open in
            if !open { Task { await loadSummary() } }
        }
    }

    private func stripLabel(
        title: String,
        subtitle: String,
        values: (views: Int, contacts: Int, boostDays: Int)?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TTColor.actionOrange)
                .frame(width: 36, height: 36)
                .background(TTColor.actionOrange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TTFont.heading(15))
                    .foregroundStyle(TTColor.ink)
                Text(subtitle)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                if let values {
                    Text("\(values.views) views · \(values.contacts) contacts · \(values.boostDays)d boost")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TTColor.inkSubtle)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Discovery insights")
    }

    @MainActor
    private func loadSummary() async {
        do {
            summary = try await APIClient().fetchCoachAnalyticsSummary(periodDays: 7)
            missingProfile = false
        } catch let error as AppError where error.isNotFound {
            summary = nil
            missingProfile = true
        } catch {
            // Soft-fail — strip stays tappable into full screen.
            missingProfile = false
        }
    }
}

#Preview("Trainer Analytics") {
    TrainerCoachAnalyticsView()
        .ttPreviewTrainer()
}
