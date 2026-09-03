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

// MARK: - Floating bottom tab bar (Tab Bar Main)

/// Floating, highly rounded tab bar with a center elevated action and notched cradle.
struct TTFloatingTabBar<Tab: Hashable>: View {
    let tabs: [TTTabBarItem<Tab>]
    @Binding var selection: Tab
    var onCenterTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let barHeight: CGFloat = 68
    private let cornerRadius: CGFloat = 34
    private let centerSize: CGFloat = 56
    private let iconSize: CGFloat = 24
    private let indicatorWidth: CGFloat = 18
    private let indicatorHeight: CGFloat = 3

    /// Exactly four side tabs (two left, two right of the center FAB).
    private var leftTabs: [TTTabBarItem<Tab>] { Array(tabs.prefix(2)) }
    private var rightTabs: [TTTabBarItem<Tab>] { Array(tabs.dropFirst(2).prefix(2)) }

    var body: some View {
        ZStack(alignment: .top) {
            barBackground
                .frame(height: barHeight)
                .padding(.top, centerSize * 0.42)

            HStack(spacing: 0) {
                ForEach(leftTabs) { item in
                    tabButton(item)
                }

                Color.clear
                    .frame(width: centerSize + 12)

                ForEach(rightTabs) { item in
                    tabButton(item)
                }
            }
            .frame(height: barHeight)
            .padding(.top, centerSize * 0.42)

            centerButton
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private var barBackground: some View {
        TTTabBarNotchShape(
            cornerRadius: cornerRadius,
            notchRadius: centerSize * 0.58,
            notchPadding: 10
        )
        .fill(barFill)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 18, y: 8)
        .overlay {
            TTTabBarNotchShape(
                cornerRadius: cornerRadius,
                notchRadius: centerSize * 0.58,
                notchPadding: 10
            )
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.55), lineWidth: 0.5)
        }
    }

    private var barFill: Color {
        colorScheme == .dark
            ? Color(white: 0.18)
            : Color(white: 0.96)
    }

    private var activeIconColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.08)
    }

    private var inactiveIconColor: Color {
        colorScheme == .dark
            ? Color(white: 0.45)
            : Color(white: 0.62)
    }

    private func tabButton(_ item: TTTabBarItem<Tab>) -> some View {
        let isActive = selection == item.id

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = item.id
            }
        } label: {
            VStack(spacing: 6) {
                TTIcon(icon: item.icon, filled: isActive, size: iconSize)
                    .foregroundStyle(isActive ? activeIconColor : inactiveIconColor)

                Capsule()
                    .fill(isActive ? TTColor.actionOrange : Color.clear)
                    .frame(width: indicatorWidth, height: indicatorHeight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
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
                    .shadow(color: TTColor.actionOrange.opacity(0.45), radius: 16, y: 6)
                    .shadow(color: TTColor.actionOrange.opacity(0.25), radius: 6, y: 2)

                TTIcon(icon: .plus, filled: true, size: 22)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(TTTabBarCenterPressStyle())
        .accessibilityLabel("Quick action")
        .offset(y: 2)
    }
}

// MARK: - Notch shape

/// Capsule-like bar with a smooth concave cradle for the center FAB.
struct TTTabBarNotchShape: Shape {
    var cornerRadius: CGFloat
    var notchRadius: CGFloat
    var notchPadding: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 4)
        let midX = rect.midX
        let notchHalf = notchRadius + notchPadding
        let notchDepth = notchRadius * 0.95

        var path = Path()

        // Bottom-left corner start
        path.move(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(-90),
            clockwise: true
        )

        // Top edge → right side of notch
        path.addLine(to: CGPoint(x: midX + notchHalf, y: rect.minY))

        // Concave notch (cubic approximates a circular cradle)
        path.addCurve(
            to: CGPoint(x: midX - notchHalf, y: rect.minY),
            control1: CGPoint(x: midX + notchHalf * 0.35, y: rect.minY + notchDepth),
            control2: CGPoint(x: midX - notchHalf * 0.35, y: rect.minY + notchDepth)
        )

        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(-180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
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
    case display   // largest
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

/// Single pill tab control — selected: black + white text; unselected: muted.
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
