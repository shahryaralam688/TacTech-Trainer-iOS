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

private struct ProfileScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    // Avatar picker (pencil badge on the avatar)
    @State private var showAvatarPicker = false
    @State private var avatarDraft = TTAvatarCatalog.default
    @State private var isUpdatingPhoto = false
    @State private var photoToast: TTToastMessage?
    @State private var scrollOffset: CGFloat = 0

    private let canvas = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = TTColor.charcoal
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
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: ProfileScrollOffsetKey.self,
                                        value: max(0, -g.frame(in: .named("profileScroll")).minY)
                                    )
                                }
                                .frame(height: 0)

                                identityBlock
                                sandowCard
                                metricsRow
                                extra()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, avatarSide / 2 + 14)
                            .padding(.bottom, 20)
                        }
                        .coordinateSpace(name: "profileScroll")
                        .onPreferenceChange(ProfileScrollOffsetKey.self) { offset in
                            scrollOffset = offset
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

                    let avatarFade = max(0, 1 - scrollOffset / (avatarSide * 0.7))
                    overlappingAvatar(width: width)
                        .offset(y: -scrollOffset)
                        .opacity(avatarFade)

                    avatarEditBadge(width: width)
                        .offset(y: -scrollOffset)
                        .opacity(avatarFade)
                        .allowsHitTesting(avatarFade > 0.2)
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
            .ttToast($photoToast)
            // Pencil badge → same "Choose your avatar" screen as onboarding, with Save/Cancel only.
            .sheet(isPresented: $showAvatarPicker) {
                NavigationStack {
                    AssessmentAvatarStep(
                        selection: $avatarDraft,
                        userId: avatarUserId ?? store.session?.userId,
                        remoteAvatarUrl: avatarUrl ?? store.remoteAvatarURL
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAvatarPicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task { await commitAvatarPicker() }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .ttModalSheetPresentation()
            }
        }
    }

    // MARK: - Avatar Picker

    @MainActor
    private func commitAvatarPicker() async {
        guard !isUpdatingPhoto else { return }
        showAvatarPicker = false
        isUpdatingPhoto = true
        defer { isUpdatingPhoto = false }

        do {
            let uid = avatarUserId ?? store.session?.userId
            if TTAvatarCatalog.isCustom(avatarDraft),
               let image = TTAvatarCatalog.loadCustomImage(for: uid),
               let data = CoachImageEncoder.jpegData(from: image) ?? image.jpegData(compressionQuality: 0.88) {
                try await store.uploadProfileAvatar(jpegData: data, previewImage: image)
            } else if TTAvatarCatalog.isAssetName(avatarDraft) {
                try await store.saveMeProfile(UpdateMeProfileBody(avatarAsset: avatarDraft))
            }
            photoToast = TTToastMessage(text: "Avatar updated", style: .success)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            photoToast = TTToastMessage(
                text: (error as? AppError)?.errorDescription ?? "Couldn’t update avatar",
                style: .error
            )
        }
    }

    /// Small pencil badge at the avatar's bottom-right; the tap target is 44 × 44 pt. A spinner replaces it while
    /// the avatar is being saved.
    private func avatarEditBadge(width: CGFloat) -> some View {
        let half = avatarSide / 2
        return Button {
            guard !isUpdatingPhoto else { return }
            if !(avatarUrl ?? "").isEmpty {
                avatarDraft = TTAvatarCatalog.customToken
            } else if let avatarAsset, TTAvatarCatalog.isAssetName(avatarAsset) {
                avatarDraft = avatarAsset
            } else {
                avatarDraft = TTAvatarCatalog.default
            }
            showAvatarPicker = true
        } label: {
            ZStack {
                Circle()
                    .fill(TTColor.actionOrange)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                if isUpdatingPhoto {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    TTIcon(icon: .pencil1, filled: true, size: 13)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: width / 2 + half - 6, y: heroHeight + half - 6)
        .accessibilityLabel("Edit profile photo")
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
            if showsBack {
                profileChromeButton(icon: .chevronLeft) {
                    dismiss()
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
        .opacity(isUpdatingPhoto ? 0.55 : 1)
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
                if !membership.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    private var chartXAxisValues: [String] {
        guard scores.count > 10 else { return scores.map(\.id) }
        let step = max(1, scores.count / 5)
        var ids: [String] = []
        for idx in stride(from: 0, to: scores.count, by: step) {
            ids.append(scores[idx].id)
        }
        if let last = scores.last, ids.last != last.id {
            if let prev = ids.last,
               let prevIdx = scores.firstIndex(where: { $0.id == prev }),
               scores.count - 1 - prevIdx < max(2, step / 2) {
                ids.removeLast()
            }
            ids.append(last.id)
        }
        return ids
    }

    private func xAxisLabel(for id: String) -> String {
        guard let item = scores.first(where: { $0.id == id }) else { return "" }
        if period == .month, let dateKey = item.dateKey, dateKey.count >= 10 {
            // "yyyy-MM-dd" -> day number (e.g. "26")
            let dayPart = String(dateKey.suffix(2))
            if let dayInt = Int(dayPart) { return "\(dayInt)" }
        }
        return item.short
    }

    private var chart: some View {
        Chart(scores) { item in
            BarMark(
                x: .value("Day", item.id),
                y: .value("Score", min(100, max(0, item.score)))
            )
            .foregroundStyle(item.id == activeDayId ? Color.black : Color(white: 0.82))
            .cornerRadius(period == .month ? 3 : 8)
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
        .chartPlotStyle { plot in
            plot.clipped()
        }
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
            AxisMarks(values: chartXAxisValues) { value in
                AxisValueLabel {
                    if let id = value.as(String.self) {
                        Text(xAxisLabel(for: id))
                            .font(TTFont.caption(period == .month ? 10 : 11))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDayId)
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
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
