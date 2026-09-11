import Charts
import SwiftUI

// MARK: - Sandow Profile Screen
// Hero + overlapping avatar + sheet identity; header collapses on scroll.

struct TTProfileMetric: Identifiable {
    let id: String
    let icon: SandowIcon
    let iconColor: Color
    let value: String
    let unit: String
    let label: String
}

struct TTSandowDayScore: Identifiable {
    let id: String
    let weekday: Weekday
    let score: Int
    var short: String { weekday.short }
}

/// Shared profile chrome — hero, identity, Sandow Score, metric tiles.
struct TTProfileScreen<Extra: View>: View {
    @Environment(\.dismiss) private var dismiss

    let name: String
    let location: String
    let membership: String
    let avatarAsset: String?
    var avatarUserId: String? = nil
    let initials: String
    let scores: [TTSandowDayScore]
    let metrics: [TTProfileMetric]
    var showsBack: Bool = false
    /// Static top card background — same family as Profile / Setup headers.
    var heroImage: String = "ProfileHero"
    @ViewBuilder var extra: () -> Extra

    @State private var selectedDayId: String?
    @State private var selectedShort: String?
    @State private var rangeLabel = "Weekly"
    @State private var path = NavigationPath()
    @StateObject private var scrollCollapse = TTHomeScrollCollapseModel()

    private let canvas = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let expandedAvatar: CGFloat = 112
    private let collapsedAvatar: CGFloat = 44
    private let expandedHero: CGFloat = 236
    private let collapsedHero: CGFloat = 108
    private let contentTopRadius: CGFloat = 36
    private let chromeButton: CGFloat = 52
    private let chromeIcon: CGFloat = 22
    private let chromeBottomPad: CGFloat = 20
    private let chromeSidePad: CGFloat = 20
    private let scrollSpace = "profileScreen"

    private enum ProfileRoute: Hashable {
        case accountSettings
        case personalInfo
    }

    private var p: CGFloat { scrollCollapse.progress }
    private var expand: CGFloat { 1 - p }

    private var heroHeight: CGFloat {
        collapsedHero + (expandedHero - collapsedHero) * expand
    }

    private var avatarSide: CGFloat {
        collapsedAvatar + (expandedAvatar - collapsedAvatar) * expand
    }

    private var activeDayId: String {
        selectedDayId ?? scores.max(by: { $0.score < $1.score })?.id ?? scores.first?.id ?? ""
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
                            VStack(spacing: 0) {
                                TTHomeScrollCollapseProbe(model: scrollCollapse, space: scrollSpace)

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
                        }
                        .ttTopRoundedSheet(radius: contentTopRadius, fill: canvas)
                        .ttObserveHomeScrollCollapse(scrollCollapse, space: scrollSpace)
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
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ZStack {
            charcoal
            Image(heroImage)
                .resizable()
                .scaledToFill()
                .opacity(0.55 + 0.45 * Double(expand))
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

    // MARK: - Chrome (left / right) — rise on collapse

    private func chromeButtons(topSafe: CGFloat) -> some View {
        let collapsedTop = topSafe + 8
        let expandedTop = heroHeight - chromeBottomPad - chromeButton
        let top = collapsedTop + (expandedTop - collapsedTop) * expand
        let buttonScale = 1 - 0.12 * p

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
        .scaleEffect(buttonScale, anchor: .top)
        .padding(.horizontal, chromeSidePad)
        .padding(.top, top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func profileChromeButton(icon: SandowIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TTIcon(icon: icon, filled: true, size: chromeIcon - 2 * p)
                .foregroundStyle(.white)
                .frame(width: chromeButton - 6 * p, height: chromeButton - 6 * p)
                .background(Color(white: 0.22).opacity(0.82))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16 - 2 * p, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == .gear1 ? "Settings" : (showsBack ? "Back" : "Edit"))
    }

    // MARK: - Avatar (half hero / half sheet → shrink + slide left)

    private func overlappingAvatar(width: CGFloat) -> some View {
        let corner = avatarSide * 0.28
        let expandedX = width / 2
        let collapsedX = chromeSidePad + (chromeButton - 6) + 10 + avatarSide / 2
        let x = expandedX + (collapsedX - expandedX) * p
        let y = heroHeight

        return TTAvatarImage(
            assetName: avatarAsset,
            userId: avatarUserId,
            initials: initials,
            size: avatarSide
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white, lineWidth: 3.5 - p)
        )
        .shadow(color: .black.opacity(0.16 * Double(expand) + 0.08), radius: 12 - 6 * p, y: 4 - 2 * p)
        .position(x: x, y: y)
        .allowsHitTesting(false)
    }

    // MARK: - Identity (lives on the content sheet)

    private var identityBlock: some View {
        VStack(spacing: 6) {
            Text(name)
                .font(TTFont.workSans(24 - 2 * p, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)

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
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .opacity(Double(0.35 + 0.65 * expand))
    }

    // MARK: Sandow Score

    private var sandowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    TTIcon(icon: .plus, filled: true, size: 14)
                        .foregroundStyle(TTColor.actionOrange)
                    Text("Sandow Score")
                        .font(TTFont.workSans(18, weight: .bold))
                        .foregroundStyle(TTColor.ink)
                }
                Spacer()
                Menu {
                    Button("Weekly") { rangeLabel = "Weekly" }
                    Button("Monthly") { rangeLabel = "Monthly" }
                } label: {
                    HStack(spacing: 6) {
                        TTIcon(icon: .calendar1, size: 12)
                        Text(rangeLabel)
                            .font(TTFont.caption(12))
                        TTIcon(icon: .chevronDown, size: 10)
                    }
                    .foregroundStyle(TTColor.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            chart
                .frame(height: 150)
        }
        .padding(12)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var chart: some View {
        Chart(scores) { item in
            BarMark(
                x: .value("Day", item.short),
                y: .value("Score", item.score)
            )
            .foregroundStyle(item.id == activeDayId ? Color.black : Color(white: 0.82))
            .cornerRadius(8)
            .annotation(position: .top, spacing: 6) {
                if item.id == activeDayId {
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
        .chartYScale(domain: 60...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [60, 70, 80, 90, 100]) { value in
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
                        Text(label)
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.inkMuted)
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
        avatarUserId: String? = nil,
        initials: String,
        scores: [TTSandowDayScore],
        metrics: [TTProfileMetric],
        showsBack: Bool = false,
        heroImage: String = "ProfileHero"
    ) {
        self.init(
            name: name,
            location: location,
            membership: membership,
            avatarAsset: avatarAsset,
            avatarUserId: avatarUserId,
            initials: initials,
            scores: scores,
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
        scores: [
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
