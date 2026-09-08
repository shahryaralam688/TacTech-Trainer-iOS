import SwiftUI

/// Status chip under the home greeting (e.g. "88% Healthy", "Pro").
struct TTHomeProfileMetric: Identifiable, Hashable {
    let id: String
    let icon: SandowIcon
    let iconColor: Color
    let text: String

    init(id: String = UUID().uuidString, icon: SandowIcon, iconColor: Color, text: String) {
        self.id = id
        self.icon = icon
        self.iconColor = iconColor
        self.text = text
    }
}

/// How far home must scroll before the header is fully compact (name + chevron).
enum TTHomeHeaderCollapse {
    static let distance: CGFloat = 72

    static func progress(for offset: CGFloat) -> CGFloat {
        min(1, max(0, offset / distance))
    }
}

/// Figma home top bar — collapses with scroll to a sticky name + forward control.
struct TTHomeProfileHeader: View {
    let name: String
    var avatarSymbol: String? = nil
    var avatarUserId: String? = nil
    var avatarInitial: String? = nil
    var badgeCount: Int = 0
    var metrics: [TTHomeProfileMetric] = []
    var date: Date = .now
    /// 0 = expanded (date, bell, avatar, metrics). 1 = compact name + chevron.
    var collapseProgress: CGFloat = 0
    var onProfileTap: (() -> Void)? = nil
    var onNotificationTap: (() -> Void)? = nil

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let dateGrey = Color.white.opacity(0.55)
    private let bellBG = Color(white: 0.22)
    private let avatarSide: CGFloat = 58

    private var p: CGFloat { min(1, max(0, collapseProgress)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22 * (1 - p)) {
            topRow
                .opacity(Double(1 - p))
                .frame(height: 44 * (1 - p), alignment: .top)
                .clipped()
                .allowsHitTesting(p < 0.35)

            profileRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 22 - 10 * p)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.black
                TTHomeHeaderBands()
                    .fill(Color.white.opacity(0.07 * (1 - p)))
            }
            .ignoresSafeArea(edges: .top)
        }
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }

    // MARK: - Rows

    private var topRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                TTIcon(icon: .calendar1, size: 14)
                Text(formattedDate)
                    .font(TTFont.textSM(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(dateGrey)

            Spacer()

            Button {
                if let onNotificationTap {
                    onNotificationTap()
                } else {
                    onProfileTap?()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    TTIcon(icon: .bell1, size: 18)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(bellBG)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if badgeCount > 0 {
                        Text("\(min(badgeCount, 9))")
                            .font(TTFont.text2XS(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(orange)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(TTHomeHeaderPressStyle())
        }
    }

    private var profileRow: some View {
        Button {
            onProfileTap?()
        } label: {
            HStack(spacing: 14 * (1 - p)) {
                avatarView
                    .opacity(Double(1 - p))
                    .frame(width: avatarSide * (1 - p), height: avatarSide * (1 - p))
                    .clipped()

                VStack(alignment: .leading, spacing: 7 * (1 - p)) {
                    Text(p < 0.45 ? "Hello, \(name)!" : name)
                        .font(TTFont.workSans(28 - 8 * p, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if !metrics.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                                if index > 0 {
                                    Circle()
                                        .fill(Color.white.opacity(0.45))
                                        .frame(width: 3, height: 3)
                                        .padding(.horizontal, 2)
                                }
                                HStack(spacing: 5) {
                                    TTIcon(icon: metric.icon, size: 12)
                                        .foregroundStyle(metric.iconColor)
                                    Text(metric.text)
                                        .font(TTFont.textMD(.medium))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .opacity(Double(1 - p))
                        .frame(height: 22 * (1 - p), alignment: .top)
                        .clipped()
                    }
                }

                Spacer(minLength: 0)

                TTIcon(icon: .chevronRight, size: 22)
                    .foregroundStyle(.white)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TTHomeHeaderPressStyle())
        .accessibilityLabel("Open profile, \(name)")
        .accessibilityHint("Opens your profile")
    }

    private var avatarView: some View {
        Group {
            if TTAvatarCatalog.isCustom(avatarSymbol),
               let custom = TTAvatarCatalog.loadCustomImage(for: avatarUserId) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
                    .frame(width: avatarSide, height: avatarSide)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let avatarSymbol, TTAvatarCatalog.isAssetName(avatarSymbol) {
                Image(avatarSymbol)
                    .resizable()
                    .scaledToFill()
                    .frame(width: avatarSide, height: avatarSide)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: avatarSide, height: avatarSide)

                    if let avatarSymbol, !TTAvatarCatalog.hasRenderableAvatar(avatarSymbol) {
                        Image(systemName: avatarSymbol)
                            .font(TTFont.headingMD(.semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text((avatarInitial ?? String(name.prefix(1))).uppercased())
                            .font(TTFont.headingSM(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

/// Subtle diagonal ribbon texture for the home header card.
struct TTHomeHeaderBands: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -40, y: 20))
        path.addQuadCurve(to: CGPoint(x: 120, y: -10), control: CGPoint(x: 40, y: -30))
        path.addQuadCurve(to: CGPoint(x: -20, y: 90), control: CGPoint(x: 70, y: 40))
        path.closeSubpath()

        path.move(to: CGPoint(x: -30, y: 50))
        path.addQuadCurve(to: CGPoint(x: 90, y: 10), control: CGPoint(x: 30, y: 0))
        path.addQuadCurve(to: CGPoint(x: -10, y: 110), control: CGPoint(x: 50, y: 55))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.maxX + 30, y: rect.maxY - 10))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 130, y: rect.maxY + 20),
            control: CGPoint(x: rect.maxX - 40, y: rect.maxY + 40)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + 10, y: rect.maxY - 80),
            control: CGPoint(x: rect.maxX - 60, y: rect.maxY - 30)
        )
        path.closeSubpath()
        return path
    }
}

/// Press feedback without the default disabled/dull fade.
private struct TTHomeHeaderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Home scroll → header collapse

extension View {
    /// Attach to the home **ScrollView**. Pair content with `TTHomeScrollOffsetAnchor`.
    func ttHomeScrollCollapseOffset(_ offset: Binding<CGFloat>, space: String = "ttHomeScroll") -> some View {
        self
            .coordinateSpace(name: space)
            .onPreferenceChange(TTHomeScrollOffsetKey.self) { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    offset.wrappedValue = max(0, value)
                }
            }
    }
}

/// Put as the **first** child inside the home ScrollView content (above padding/sections).
struct TTHomeScrollOffsetAnchor: View {
    var space: String = "ttHomeScroll"

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: TTHomeScrollOffsetKey.self,
                value: -geo.frame(in: .named(space)).minY
            )
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

private struct TTHomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview("Home Header") {
    VStack(spacing: 24) {
        TTHomeProfileHeader(
            name: "Maya",
            badgeCount: 2,
            metrics: [
                TTHomeProfileMetric(id: "h", icon: .plus, iconColor: TTColor.actionOrange, text: "86% Healthy"),
                TTHomeProfileMetric(id: "p", icon: .starFull, iconColor: .blue, text: "Pro")
            ],
            onProfileTap: {}
        )
        TTHomeProfileHeader(
            name: "Maya",
            collapseProgress: 1,
            onProfileTap: {}
        )
    }
    .background(Color.black)
}
