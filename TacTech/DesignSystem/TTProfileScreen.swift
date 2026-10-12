import Charts
import SwiftUI

// MARK: - Sandow Profile Screen
// Hero + overlapping avatar + sheet identity. Scrolls without collapsing the hero.

struct TTProfileMetric: Identifiable {
    let id: String
    let icon: SandowIcon
    let iconColor: Color
    let value: String
    let unit: String
    let label: String
}

struct TTSandowDayScore: Identifiable, Equatable {
    let id: String
    let label: String
    let score: Int
    var weekday: Weekday? = nil
    /// `yyyy-MM-DD` when known — used to highlight “today”.
    var dateKey: String? = nil

    var short: String { label }

    init(id: String, label: String, score: Int, weekday: Weekday? = nil, dateKey: String? = nil) {
        self.id = id
        self.label = label
        self.score = score
        self.weekday = weekday
        self.dateKey = dateKey
    }

    init(id: String, weekday: Weekday, score: Int, dateKey: String? = nil) {
        self.init(id: id, label: weekday.short, score: score, weekday: weekday, dateKey: dateKey)
    }
}

/// Shared profile chrome — hero, identity, Sandow Score, metric tiles.
struct TTProfileScreen<Extra: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    let name: String
    let location: String
    let membership: String
    let avatarAsset: String?
    var avatarUrl: String? = nil
    var avatarUserId: String? = nil
    let initials: String
    /// Preview / override only — live profile uses `AppStore.sandowChartScores`.
    var scoresOverride: [TTSandowDayScore]? = nil
    let metrics: [TTProfileMetric]
    var showsBack: Bool = false
    /// Static top card background — same family as Profile / Setup headers.
    var heroImage: String = "ProfileHero"
    @ViewBuilder var extra: () -> Extra

    @State private var selectedDayId: String?
    @State private var selectedShort: String?
    @State private var period: SandowScorePeriod = .week
    @State private var path = NavigationPath()

    private let canvas = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let avatarSide: CGFloat = 112
    private let heroHeight: CGFloat = 236
    private let contentTopRadius: CGFloat = 36
    private let chromeButton: CGFloat = 52
    private let chromeIcon: CGFloat = 22
    private let chromeBottomPad: CGFloat = 20
    private let chromeSidePad: CGFloat = 20

    private enum ProfileRoute: Hashable {
        case accountSettings
        case personalInfo
    }

    private var scores: [TTSandowDayScore] {
        scoresOverride ?? store.sandowChartScores
    }

    private var sandowTitle: String {
        store.sandowScore?.resolvedTitle ?? "TacTech Score"
    }

    private var sandowSubtitle: String? {
        store.sandowScore?.resolvedSubtitle
    }

    private var emptyCaption: String? {
        guard scoresOverride == nil else { return nil }
        if let caption = store.sandowScore?.emptyCaption, !caption.isEmpty { return caption }
        guard !scores.contains(where: { $0.score > 0 }) else { return nil }
        switch store.sandowScore?.mode {
        case "boost_analytics": return "Boost to see reach"
        case "roster_performance": return "No client activity yet"
        default:
            return store.session?.role == .trainer
                ? (store.isBoostActiveForSandow ? "Boost to see reach" : "No client activity yet")
                : "Log workouts to build your score"
        }
    }

    private var todayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Latest day with score > 0, else today, else last bar.
    private var activeDayId: String {
        if let selectedDayId { return selectedDayId }
        if let latestActive = scores.last(where: { $0.score > 0 }) {
            return latestActive.id
        }
        if let today = scores.first(where: { $0.dateKey == todayKey }) {
            return today.id
        }
        return scores.last?.id ?? scores.first?.id ?? ""
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let topSafe = geo.safeAreaInsets.top
                let width = geo.size.width

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: heroHeight)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 10) {
                                identityBlock
                                sandowCard
                                metricsRow
                                extra()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, avatarSide / 2 + 14)
                            .padding(.bottom, 20)
                        }
                        .refreshable {
                            await store.loadSandowScore(period: period, force: true)
                        }
                        .ttTopRoundedSheet(radius: contentTopRadius, fill: canvas)
                    }

                    heroCard
                        .frame(height: heroHeight)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .allowsHitTesting(false)

                    chromeButtons(topSafe: topSafe)

                    overlappingAvatar(width: width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(charcoal.ignoresSafeArea(edges: .top))
            .ignoresSafeArea(edges: .top)
            .ttHideSystemNavigationBar()
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .accountSettings:
                    AccountSettingsView()
                case .personalInfo:
                    PersonalInformationSettingsView()
                }
            }
            // Pushed Account / Settings live on this stack — hide floating tab chrome off-root.
            .ttRootTabBarVisible(path.isEmpty)
            .ttSyncRootTabBarWithNavigationDepth()
            .task {
                period = store.sandowPeriod
                await store.loadSandowScore(period: period)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttSandowScoreShouldRefresh)) { _ in
                Task { await store.loadSandowScore(period: period, force: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttBoostCheckoutSucceeded)) { _ in
                Task { await store.loadSandowScore(period: period, force: true) }
            }
            .onChange(of: scores.map(\.id)) { _, _ in
                selectedDayId = nil
                selectedShort = nil
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ZStack {
            charcoal
            Image(heroImage)
                .resizable()
                .scaledToFill()
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Chrome (left / right)

    private func chromeButtons(topSafe _: CGFloat) -> some View {
        let top = heroHeight - chromeBottomPad - chromeButton

        return HStack {
            profileChromeButton(icon: showsBack ? .chevronLeft : .pencil1) {
                if showsBack {
                    dismiss()
                } else {
                    path.append(ProfileRoute.personalInfo)
                }
            }
            Spacer(minLength: 0)
            profileChromeButton(icon: .gear1) {
                path.append(ProfileRoute.accountSettings)
            }
        }
        .padding(.horizontal, chromeSidePad)
        .padding(.top, top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func profileChromeButton(icon: SandowIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TTIcon(icon: icon, filled: true, size: chromeIcon)
                .foregroundStyle(.white)
                .frame(width: chromeButton, height: chromeButton)
                .background(Color(white: 0.22).opacity(0.82))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == .gear1 ? "Settings" : (showsBack ? "Back" : "Edit"))
    }

    // MARK: - Avatar (half hero / half sheet)

    private func overlappingAvatar(width: CGFloat) -> some View {
        let corner = avatarSide * 0.28

        return TTUserAvatarView(
            avatarUrl: avatarUrl,
            avatarAsset: avatarAsset,
            userId: avatarUserId,
            name: name,
            size: avatarSide,
            shape: .roundedRect,
            cornerRadius: corner,
            strokeColor: .white,
            strokeWidth: 3.5
        )
        .shadow(color: .black.opacity(0.24), radius: 12, y: 4)
        .position(x: width / 2, y: heroHeight)
        .allowsHitTesting(false)
    }

    // MARK: - Identity (lives on the content sheet)

    private var identityBlock: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(name)
                    .font(TTFont.workSans(24, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .multilineTextAlignment(.center)
                AIProBadgeIfActive(entitlement: store.aiEntitlement, style: .compact)
            }

            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    TTIcon(icon: .mapPin1, size: 13)
                    Text(location)
                        .font(TTFont.textSM(.medium))
                }
                Circle()
                    .fill(TTColor.ink.opacity(0.25))
                    .frame(width: 3, height: 3)
                    .padding(.horizontal, 4)
                HStack(spacing: 4) {
                    TTIcon(icon: .user, size: 13)
                    Text(membership)
                        .font(TTFont.textSM(.medium))
                }
            }
            .foregroundStyle(TTColor.inkMuted)

            if let ai = store.aiEntitlement, ai.active {
                Text(ai.activeStatusLine)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .task {
            await store.refreshAIEntitlements()
        }
    }

    // MARK: Sandow Score

    private var sandowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        TTIcon(icon: .plus, filled: true, size: 14)
                            .foregroundStyle(TTColor.actionOrange)
                        Text(sandowTitle)
                            .font(TTFont.workSans(18, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                    }
                    if let sandowSubtitle {
                        Text(sandowSubtitle)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
                Spacer()
                Menu {
                    Button("Weekly") { selectPeriod(.week) }
                    Button("Monthly") { selectPeriod(.month) }
                } label: {
                    HStack(spacing: 6) {
                        TTIcon(icon: .calendar1, size: 12)
                        Text(period.menuTitle)
                            .font(TTFont.caption(12))
                        if store.isLoadingSandowScore {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            TTIcon(icon: .chevronDown, size: 10)
                        }
                    }
                    .foregroundStyle(TTColor.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(store.isLoadingSandowScore && scoresOverride == nil)
            }

            chart
                .frame(height: 150)
                .opacity(store.isLoadingSandowScore && scores.allSatisfy({ $0.score == 0 }) ? 0.55 : 1)

            if let emptyCaption {
                Text(emptyCaption)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func selectPeriod(_ next: SandowScorePeriod) {
        guard period != next else { return }
        period = next
        Task { await store.loadSandowScore(period: next, force: true) }
    }

    private var chartYDomain: ClosedRange<Int> {
        let maxScore = scores.map(\.score).max() ?? 0
        if maxScore <= 0 { return 0...100 }
        if maxScore <= 60 { return 0...100 }
        return 0...100
    }

    private var chartYMarks: [Int] { [0, 25, 50, 75, 100] }

    private var chart: some View {
        Chart(scores) { item in
            BarMark(
                x: .value("Day", item.short),
                y: .value("Score", item.score)
            )
            .foregroundStyle(item.id == activeDayId ? Color.black : Color(white: 0.82))
            .cornerRadius(period == .month ? 4 : 8)
            .annotation(position: .top, spacing: 6) {
                if item.id == activeDayId, period == .week || scores.count <= 10 {
                    Text("\(item.score)")
                        .font(TTFont.workSans(12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 10,
                                bottomLeadingRadius: 10,
                                bottomTrailingRadius: 10,
                                topTrailingRadius: 10,
                                style: .continuous
                            )
                            .fill(.black)
                        )
                }
            }
        }
        .chartYScale(domain: chartYDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: chartYMarks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.black.opacity(0.06))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkSubtle)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        // Monthly: thin labels — show every few ticks via length check.
                        Text(label)
                            .font(TTFont.caption(period == .month ? 9 : 11))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedShort)
        .onChange(of: selectedShort) { _, day in
            guard let day, let match = scores.first(where: { $0.short == day }) else { return }
            selectedDayId = match.id
        }
        .animation(.easeInOut(duration: 0.25), value: scores.map(\.score))
    }

    // MARK: Metrics

    private var metricsRow: some View {
        HStack(spacing: 8) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    TTIcon(icon: metric.icon, filled: true, size: 18)
                        .foregroundStyle(metric.iconColor)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(metric.value)
                            .font(TTFont.workSans(20, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Text(metric.unit)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Text(metric.label)
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

extension TTProfileScreen where Extra == EmptyView {
    init(
        name: String,
        location: String,
        membership: String,
        avatarAsset: String?,
        avatarUrl: String? = nil,
        avatarUserId: String? = nil,
        initials: String,
        scoresOverride: [TTSandowDayScore]? = nil,
        metrics: [TTProfileMetric],
        showsBack: Bool = false,
        heroImage: String = "ProfileHero"
    ) {
        self.init(
            name: name,
            location: location,
            membership: membership,
            avatarAsset: avatarAsset,
            avatarUrl: avatarUrl,
            avatarUserId: avatarUserId,
            initials: initials,
            scoresOverride: scoresOverride,
            metrics: metrics,
            showsBack: showsBack,
            heroImage: heroImage,
            extra: { EmptyView() }
        )
    }
}

#Preview("Profile Screen") {
    TTProfileScreen(
        name: "Makise Kurisu",
        location: "Tokyo, Japan",
        membership: "Basic Member",
        avatarAsset: TTAvatarCatalog.default,
        initials: "MK",
        scoresOverride: [
            TTSandowDayScore(id: "monday", weekday: .monday, score: 78),
            TTSandowDayScore(id: "tuesday", weekday: .tuesday, score: 95),
            TTSandowDayScore(id: "wednesday", weekday: .wednesday, score: 82),
            TTSandowDayScore(id: "thursday", weekday: .thursday, score: 74),
            TTSandowDayScore(id: "friday", weekday: .friday, score: 88),
            TTSandowDayScore(id: "saturday", weekday: .saturday, score: 70),
            TTSandowDayScore(id: "sunday", weekday: .sunday, score: 76)
        ],
        metrics: [
            TTProfileMetric(id: "age", icon: .calendar1, iconColor: Color(hex: 0xEF4444), value: "17", unit: "yr", label: "Current Age"),
            TTProfileMetric(id: "wt", icon: .weightScale, iconColor: Color(hex: 0x22C55E), value: "68", unit: "kg", label: "Weight"),
            TTProfileMetric(id: "cal", icon: .fire1, iconColor: Color(hex: 0x3B82F6), value: "978", unit: "kcal", label: "Daily Intake")
        ]
    )
    .ttPreviewTrainee()
}
