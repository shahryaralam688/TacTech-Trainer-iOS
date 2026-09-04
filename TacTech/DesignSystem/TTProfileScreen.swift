import Charts
import SwiftUI

// MARK: - Sandow Profile Screen
// Layout matches Sandow UI Kit profile (gym hero + score chart + metric tiles).

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
    let initials: String
    let scores: [TTSandowDayScore]
    let metrics: [TTProfileMetric]
    var showsBack: Bool = false
    /// Static top card background — same family as Profile / Setup headers.
    var heroImage: String = "ProfileHero"
    var onEdit: (() -> Void)? = nil
    @ViewBuilder var extra: () -> Extra

    @State private var selectedDayId: String?
    @State private var selectedShort: String?
    @State private var rangeLabel = "Weekly"
    @State private var showSettings = false

    private let canvas = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private let avatarSize: CGFloat = 112
    /// Visible hero card height (includes status-bar bleed when ignoring top safe area).
    private let heroCardHeight: CGFloat = 236
    private let headerBottomRadius: CGFloat = 36
    private let chromeButton: CGFloat = 52
    private let chromeIcon: CGFloat = 22
    private let chromeBottomPad: CGFloat = 20
    private let chromeSidePad: CGFloat = 20

    private var activeDayId: String {
        selectedDayId ?? scores.max(by: { $0.score < $1.score })?.id ?? scores.first?.id ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // One block: card + half-overlapping avatar + name (no empty white spacer).
                    headerBlock

                    sandowCard
                        .padding(.horizontal, 20)
                        .padding(.top, 22)
                    metricsRow
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    extra()
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 36)
                }
            }
            .background(canvas.ignoresSafeArea())
            .ignoresSafeArea(edges: .top)
            .ttHideSystemNavigationBar()
            .navigationDestination(isPresented: $showSettings) {
                AccountSettingsView()
            }
        }
    }

    // MARK: Header
    // Avatar center on card bottom → half on image / half above name.
    // Name sits right under the avatar (no dead white div).

    private var headerBlock: some View {
        ZStack(alignment: .top) {
            staticTopCard
                .overlay(alignment: .bottom) {
                    HStack {
                        profileChromeButton(icon: showsBack ? .chevronLeft : .pencil1) {
                            if showsBack {
                                dismiss()
                            } else {
                                onEdit?()
                                if onEdit == nil { showSettings = true }
                            }
                        }
                        Spacer(minLength: 0)
                        profileChromeButton(icon: .gear1) {
                            showSettings = true
                        }
                    }
                    .padding(.horizontal, chromeSidePad)
                    .padding(.bottom, chromeBottomPad)
                }

            VStack(spacing: 12) {
                Color.clear
                    .frame(height: heroCardHeight - avatarSize / 2)
                profileAvatar
                identity
            }
        }
    }

    /// Static top card — bleeds under status bar; bottom corners like Profile/Setup.
    private var staticTopCard: some View {
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
        .frame(maxWidth: .infinity)
        .frame(height: heroCardHeight)
        .clipped()
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: headerBottomRadius,
                bottomTrailingRadius: headerBottomRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }

    private var profileAvatar: some View {
        let corner = avatarSize * 0.28
        return Group {
            if let avatarAsset, TTAvatarCatalog.isAssetName(avatarAsset) {
                Image(avatarAsset)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials.uppercased())
                    .font(TTFont.workSans(36, weight: .bold))
                    .foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.92))
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white, lineWidth: 3.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
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

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: 8) {
            Text(name)
                .font(TTFont.workSans(26, weight: .bold))
                .foregroundStyle(TTColor.ink)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    TTIcon(icon: .mapPin1, size: 13)
                    Text(location)
                        .font(TTFont.textSM(.medium))
                }
                Circle()
                    .fill(TTColor.inkSubtle)
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
        .padding(.horizontal, 24)
    }

    // MARK: Sandow Score

    private var sandowCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    TTIcon(icon: .plus, filled: true, size: 14)
                        .foregroundStyle(TTColor.actionOrange)
                    Text("Sandow Score")
                        .font(TTFont.headingLG(.bold))
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
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(TTColor.inkMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            chart
                .frame(height: 180)
        }
        .padding(16)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        HStack(spacing: 10) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 10) {
                    TTIcon(icon: metric.icon, filled: true, size: 18)
                        .foregroundStyle(metric.iconColor)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(metric.value)
                            .font(TTFont.workSans(22, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Text(metric.unit)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Text(metric.label)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(cardFill)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        initials: String,
        scores: [TTSandowDayScore],
        metrics: [TTProfileMetric],
        showsBack: Bool = false,
        heroImage: String = "ProfileHero",
        onEdit: (() -> Void)? = nil
    ) {
        self.init(
            name: name,
            location: location,
            membership: membership,
            avatarAsset: avatarAsset,
            initials: initials,
            scores: scores,
            metrics: metrics,
            showsBack: showsBack,
            heroImage: heroImage,
            onEdit: onEdit,
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
