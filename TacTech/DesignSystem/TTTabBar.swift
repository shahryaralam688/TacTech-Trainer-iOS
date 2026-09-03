import SwiftUI

// MARK: - Tokens

extension TTColor {
    /// Tab-bar FAB + active indicator — Sandow accent orange (#FF6B00).
    static let actionOrange = Color(hex: 0xFF6B00)
}

// MARK: - Tab item model

struct TTTabBarItem<Tab: Hashable>: Identifiable {
    let id: Tab
    let icon: SandowIcon
    var accessibilityLabel: String

    init(_ id: Tab, icon: SandowIcon, label: String) {
        self.id = id
        self.icon = icon
        self.accessibilityLabel = label
    }
}

// MARK: - Docked bottom tab bar (Tab Bar Main)

/// Full-width docked tab bar — not a floating pill.
/// Top corners rounded with a center notch; orange plus floats above the cradle.
/// Extends into the bottom safe area so the home-indicator strip matches the bar.
struct TTFloatingTabBar<Tab: Hashable>: View {
    let tabs: [TTTabBarItem<Tab>]
    @Binding var selection: Tab
    var onCenterTap: () -> Void
    /// Device home-indicator inset — passed from a full-screen GeometryReader.
    var bottomInset: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    private let barHeight: CGFloat = 70
    private let topCornerRadius: CGFloat = 28
    private let centerSize: CGFloat = 56
    /// How far the plus sits above the bar’s top edge.
    private let fabLift: CGFloat = 24
    private let iconSize: CGFloat = 24
    private let indicatorWidth: CGFloat = 16
    private let indicatorHeight: CGFloat = 3

    /// Height above the home indicator (FAB overhang + icon row).
    static var contentHeight: CGFloat { 24 + 70 }

    private var leftTabs: [TTTabBarItem<Tab>] { Array(tabs.prefix(2)) }
    private var rightTabs: [TTTabBarItem<Tab>] { Array(tabs.dropFirst(2).prefix(2)) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                TTTabBarNotchShape(
                    topCornerRadius: topCornerRadius,
                    notchRadius: centerSize * 0.62,
                    notchPadding: 8
                )
                .fill(barFill)
                .frame(height: barHeight)
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                    radius: 16,
                    y: -4
                )
                .padding(.top, fabLift)

                HStack(spacing: 0) {
                    ForEach(leftTabs) { item in
                        tabButton(item)
                    }

                    Color.clear
                        .frame(width: centerSize + 8)

                    ForEach(rightTabs) { item in
                        tabButton(item)
                    }
                }
                .frame(height: barHeight)
                .padding(.top, fabLift)
                .padding(.horizontal, 4)

                centerButton
            }
            .frame(height: fabLift + barHeight)
            .frame(maxWidth: .infinity)

            // Same fill as the bar — no separate strip under the home indicator.
            barFill
                .frame(height: max(bottomInset, 0))
                .frame(maxWidth: .infinity)
        }
        .background(barFill)
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var barFill: Color {
        colorScheme == .dark ? Color(white: 0.16) : .white
    }

    private var activeIconColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.08)
    }

    private var inactiveIconColor: Color {
        colorScheme == .dark ? Color(white: 0.48) : Color(white: 0.68)
    }

    private var activeChipFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color(white: 0.93)
    }

    private func tabButton(_ item: TTTabBarItem<Tab>) -> some View {
        let isActive = selection == item.id

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = item.id
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? activeChipFill : Color.clear)
                        .frame(width: 46, height: 34)

                    TTIcon(icon: item.icon, filled: isActive, size: iconSize)
                        .foregroundStyle(isActive ? activeIconColor : inactiveIconColor)
                }

                Capsule()
                    .fill(isActive ? TTColor.actionOrange : Color.clear)
                    .frame(width: indicatorWidth, height: indicatorHeight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight - 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var centerButton: some View {
        Button(action: onCenterTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(TTColor.actionOrange)
                    .frame(width: centerSize, height: centerSize)
                    .shadow(color: TTColor.actionOrange.opacity(0.42), radius: 14, y: 6)
                    .shadow(color: TTColor.actionOrange.opacity(0.22), radius: 4, y: 2)

                TTIcon(icon: .plus, filled: false, size: 20)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(TTTabBarCenterPressStyle())
        .accessibilityLabel("Quick action")
    }
}

// MARK: - Notch shape

/// Full-width bar: rounded top corners, square bottom, concave cradle for the FAB.
struct TTTabBarNotchShape: Shape {
    var topCornerRadius: CGFloat
    var notchRadius: CGFloat
    var notchPadding: CGFloat

    init(topCornerRadius: CGFloat, notchRadius: CGFloat, notchPadding: CGFloat) {
        self.topCornerRadius = topCornerRadius
        self.notchRadius = notchRadius
        self.notchPadding = notchPadding
    }

    /// Backward-compatible alias.
    init(cornerRadius: CGFloat, notchRadius: CGFloat, notchPadding: CGFloat) {
        self.topCornerRadius = cornerRadius
        self.notchRadius = notchRadius
        self.notchPadding = notchPadding
    }

    func path(in rect: CGRect) -> Path {
        let r = min(topCornerRadius, rect.height, rect.width / 4)
        let midX = rect.midX
        let notchHalf = notchRadius + notchPadding
        let notchDepth = notchRadius * 0.88

        var path = Path()

        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: midX - notchHalf, y: rect.minY))

        // Concave cradle under the floating plus.
        path.addCurve(
            to: CGPoint(x: midX + notchHalf, y: rect.minY),
            control1: CGPoint(x: midX - notchHalf * 0.28, y: rect.minY + notchDepth),
            control2: CGPoint(x: midX + notchHalf * 0.28, y: rect.minY + notchDepth)
        )

        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Center button press

private struct TTTabBarCenterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Pill segmented tabs (Tab Single / Tab Group Text)

enum TTPillTabSize {
    case display
    case large
    case medium
    case small
    case xsmall

    var font: Font {
        switch self {
        case .display: TTFont.headingSM(.semibold)
        case .large: TTFont.textLG(.semibold)
        case .medium: TTFont.textMD(.semibold)
        case .small: TTFont.textSM(.semibold)
        case .xsmall: TTFont.textXS(.semibold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .display: 20
        case .large: 16
        case .medium: 14
        case .small: 12
        case .xsmall: 10
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .display: 12
        case .large: 10
        case .medium: 8
        case .small: 6
        case .xsmall: 5
        }
    }
}

/// Single pill tab — selected: black + white text; unselected: muted.
struct TTPillTab: View {
    let title: String
    var isSelected: Bool
    var size: TTPillTabSize = .medium
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(size.font)
                .foregroundStyle(isSelected ? selectedForeground : mutedForeground)
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? selectedBackground : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedBackground: Color {
        colorScheme == .dark ? Color.white : Color(white: 0.08)
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? Color(white: 0.08) : .white
    }

    private var mutedForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.45) : Color(white: 0.55)
    }
}

/// Horizontal group of pill tabs (Tab Group Text).
struct TTPillTabBar: View {
    let titles: [String]
    @Binding var selection: Int
    var size: TTPillTabSize = .medium
    var showsGroupBackground: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(titles.indices, id: \.self) { index in
                TTPillTab(
                    title: titles[index],
                    isSelected: selection == index,
                    size: size
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = index
                    }
                }
            }
        }
        .padding(showsGroupBackground ? 4 : 0)
        .background {
            if showsGroupBackground {
                Capsule(style: .continuous)
                    .fill(groupFill)
            }
        }
    }

    private var groupFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(white: 0.94)
    }
}

/// Generic pill tab bar bound to a `Hashable` selection value.
struct TTSegmentedPillTabs<Value: Hashable>: View {
    let items: [(Value, String)]
    @Binding var selection: Value
    var size: TTPillTabSize = .medium
    var showsGroupBackground: Bool = true

    var body: some View {
        let titles = items.map(\.1)
        let index = items.firstIndex(where: { $0.0 == selection }) ?? 0

        TTPillTabBar(
            titles: titles,
            selection: Binding(
                get: { index },
                set: { newIndex in
                    guard items.indices.contains(newIndex) else { return }
                    selection = items[newIndex].0
                }
            ),
            size: size,
            showsGroupBackground: showsGroupBackground
        )
    }
}
