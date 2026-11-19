import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    /// Optional visible title under the icon. nil (default) keeps the icon-only look.
    var title: String?

    init(_ id: Tab, icon: SandowIcon, label: String, title: String? = nil) {
        self.id = id
        self.icon = icon
        self.accessibilityLabel = label
        self.title = title
    }
}

// MARK: - Floating capsule tab bar

/// Floating capsule bottom bar with an inverted rectangular top-center notch.
/// Orange square FAB hovers freely in the cutout (does not touch the bar).
struct TTFloatingTabBar<Tab: Hashable>: View {
    let tabs: [TTTabBarItem<Tab>]
    @Binding var selection: Tab
    var onCenterTap: () -> Void
    /// Device home-indicator inset — passed from a full-screen GeometryReader.
    var bottomInset: CGFloat = 0
    var aiChatNamespace: Namespace.ID? = nil
    var isAIChatPresented: Bool = false
    var isCenterMenuPresented: Bool = false
    var liquidFABNamespace: Namespace.ID? = nil
    /// Liquid-bubble menu (trainer). When set, the centre button observes ONLY this small object (not the screen's
    /// state) to hide itself while the menu is open, so opening the menu re-runs no other body. Default nil = original behaviour.
    var bubbleEngine: TTBubbleEngine? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if canImport(UIKit)
    /// One generator for the centre button (medium), prepared on appear and after each use.
    @State private var centerHaptic = TTCenterHaptic()
    #endif

    // 8pt grid — base 375×812; outer margin 16; micro 2/4/6; scale 8/16/32/64.
    private let barHeight: CGFloat = TTSpace.s64
    private let capsuleCorner: CGFloat = TTSpace.s32
    private let horizontalInset: CGFloat = TTSpace.screen
    private let floatGap: CGFloat = TTSpace.s8
    private let centerSize: CGFloat = 56
    private let fabCorner: CGFloat = TTSpace.s16
    private let iconSize: CGFloat = 24
    private let indicatorWidth: CGFloat = TTSpace.s16
    private let indicatorHeight: CGFloat = TTSpace.micro2

    /// Even air between FAB and notch walls (left / right / bottom) — micro scale.
    private let notchGap: CGFloat = TTSpace.micro4
    private var notchWidth: CGFloat { centerSize + notchGap * 2 }
    private var notchDepth: CGFloat { 24 }
    private var notchCorner: CGFloat { TTSpace.s16 }
    /// Chrome height reserved above the capsule so the FAB isn’t clipped.
    private var fabLift: CGFloat { max(0, centerSize - notchDepth + notchGap) }

    /// Solid capsule height (excludes FAB overhang). Use for content bottom padding.
    static var barBodyHeight: CGFloat { TTSpace.s64 + TTSpace.s8 }
    static var contentHeight: CGFloat { 56 - 24 + TTSpace.micro4 + TTSpace.s64 }
    static var centerFABSize: CGFloat { 56 }
    static var fabLiftAmount: CGFloat { 56 - 24 + TTSpace.micro4 }
    /// Overlay FAB bottom padding above the home-indicator so it sits on the cradle +.
    static var liquidMenuFABBottomReserve: CGFloat {
        barBodyHeight - centerFABSize + fabLiftAmount
    }
    /// Sticky bottom CTAs (Save bars) inside tab roots — clears the floating capsule + small gap.
    static var stickyCTABottomInset: CGFloat { barBodyHeight + TTSpace.s8 }

    private var leftTabs: [TTTabBarItem<Tab>] { Array(tabs.prefix(2)) }
    private var rightTabs: [TTTabBarItem<Tab>] { Array(tabs.dropFirst(2).prefix(2)) }

    var body: some View {
        VStack(spacing: 0) {
            // No GeometryReader / .position: the centre button lives in the same layout pass as the bar, so it
            // moves with the bar (slide-in, tab change) and never lags behind or jumps into place.
            let fabTop = Self.fabFrameInChrome(
                containerWidth: 0,
                fabLift: fabLift,
                centerSize: centerSize,
                notchDepth: notchDepth,
                notchGap: notchGap
            ).minY

            ZStack(alignment: .top) {
                    capsuleBar
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, fabLift)

                    // 4-column tab row: 2 left + notch + 2 right, screen-margin aligned.
                    HStack(spacing: 0) {
                        ForEach(leftTabs) { item in
                            tabButton(item)
                        }

                        Color.clear
                            .frame(width: notchWidth)

                        ForEach(rightTabs) { item in
                            tabButton(item)
                        }
                    }
                    .frame(height: barHeight)
                    .padding(.horizontal, horizontalInset + TTSpace.micro6)
                    .padding(.top, fabLift)

                    Group {
                        if let bubbleEngine {
                            TTBubbleCenterButton(
                                engine: bubbleEngine,
                                isAIChatPresented: isAIChatPresented,
                                onCenterTap: onCenterTap
                            )
                        } else {
                            centerButton
                        }
                    }
                        .frame(width: centerSize, height: centerSize)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, fabTop)
            }
            .frame(height: fabLift + barHeight)
            .frame(maxWidth: .infinity)

            Color.clear
                .frame(height: floatGap + max(bottomInset, 0))
                .frame(maxWidth: .infinity)
        }
        .background(Color.clear)
        .accessibilityElement(children: .contain)
    }

    /// Centers the FAB on the notch: equal `notchGap` on left, right, and bottom.
    private static func fabFrameInChrome(
        containerWidth: CGFloat,
        fabLift: CGFloat,
        centerSize: CGFloat,
        notchDepth: CGFloat,
        notchGap: CGFloat
    ) -> CGRect {
        let barTop = fabLift
        let notchFloor = barTop + notchDepth
        let fabTop = notchFloor - notchGap - centerSize
        let fabLeft = (containerWidth - centerSize) * 0.5
        return CGRect(x: fabLeft, y: fabTop, width: centerSize, height: centerSize)
    }

    // MARK: - Capsule

    private var capsuleBar: some View {
        TTTabBarNotchShape(
            cornerRadius: capsuleCorner,
            notchWidth: notchWidth,
            notchDepth: notchDepth,
            notchCornerRadius: notchCorner
        )
        .fill(barFill)
        .frame(height: barHeight)
        .overlay {
            TTTabBarNotchShape(
                cornerRadius: capsuleCorner,
                notchWidth: notchWidth,
                notchDepth: notchDepth,
                notchCornerRadius: notchCorner
            )
            .stroke(barStroke, lineWidth: 0.75)
        }
        .shadow(color: barShadow, radius: 18, y: 8)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 4, y: 2)
    }

    // MARK: - Pieces

    private var barFill: Color {
        colorScheme == .dark
            ? Color(white: 0.14)
            : Color.white
    }

    private var barStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.05)
    }

    private var barShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.55)
            : Color.black.opacity(0.12)
    }

    private var activeIconColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.08)
    }

    private var inactiveIconColor: Color {
        colorScheme == .dark ? Color(white: 0.48) : Color(white: 0.62)
    }

    private var activeChipFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color(white: 0.94)
    }

    private func tabButton(_ item: TTTabBarItem<Tab>) -> some View {
        let isActive = selection == item.id

        return Button {
            guard selection != item.id else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selection = item.id
            }
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            VStack(spacing: TTSpace.micro4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? activeChipFill : Color.clear)
                        .frame(width: 48, height: 32)

                    TTIcon(icon: item.icon, filled: isActive, size: iconSize)
                        .foregroundStyle(isActive ? activeIconColor : inactiveIconColor)
                }

                if let title = item.title {
                    // Fixed 11pt so the bar height never changes with Dynamic Type; VoiceOver uses the label.
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isActive ? activeIconColor : inactiveIconColor)
                        .accessibilityHidden(true)
                }

                Capsule()
                    .fill(isActive ? TTColor.actionOrange : Color.clear)
                    .frame(width: indicatorWidth, height: indicatorHeight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight - TTSpace.micro6)
            .contentShape(Rectangle())
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86),
                value: isActive
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var centerButton: some View {
        Button {
            #if DEBUG || PERF_TEMP
            PlusTapProbe.shared.action(menu: isCenterMenuPresented, chat: isAIChatPresented) // PERF-TEMP
            #endif
            // Already opening/open (or AI chat up): ignore — no second open, no second haptic.
            guard !isCenterMenuPresented, !isAIChatPresented else { return }
            #if canImport(UIKit)
            centerHaptic.fire()
            #endif
            onCenterTap()
        } label: {
            TTCenterSquareFace() // the ORIGINAL rounded-square face (same view the bubble overlay draws)
            // Bigger tap target, no visual change: 64×72 (56×56 + 4 each side + 12 up + 4 down).
            // 64pt wide = the notch gap exactly, so it never reaches the Plans / Chat buttons.
            .contentShape(TTCenterHitShape())
        }
        .buttonStyle(TTTabBarCenterPressStyle())
        #if canImport(UIKit)
        .onAppear { centerHaptic.prepare() }
        #endif
        .opacity(isCenterMenuPresented || isAIChatPresented ? 0 : 1)
        .allowsHitTesting(!(isCenterMenuPresented || isAIChatPresented))
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9),
            value: isCenterMenuPresented
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9),
            value: isAIChatPresented
        )
        .modifier(TTOptionalMatchedGeometry(
            id: TTLiquidFABPortal.matchedID,
            namespace: liquidFABNamespace,
            isSource: !isCenterMenuPresented && !isAIChatPresented
        ))
        .accessibilityLabel("Open quick actions")
        .accessibilityHint("AI assistant, create plan, assign, or view assignments")
        .perfTempPlusButton(menu: isCenterMenuPresented, chat: isAIChatPresented) // PERF-TEMP
    }
}

/// Applies `matchedGeometryEffect` only when a namespace is provided.
private struct TTOptionalMatchedGeometry: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    var isSource: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}

// MARK: - Inverted rectangular notch (soft corner radii)

/// Capsule bar path with a smooth inverted rectangular cutout on the top-center edge.
struct TTTabBarNotchShape: Shape {
    var cornerRadius: CGFloat
    var notchWidth: CGFloat
    var notchDepth: CGFloat
    var notchCornerRadius: CGFloat

    /// Legacy initializer — maps old circular cradle params into the rectangular notch.
    init(topCornerRadius: CGFloat, notchRadius: CGFloat, notchPadding: CGFloat) {
        self.cornerRadius = topCornerRadius
        self.notchWidth = (notchRadius + notchPadding) * 2
        self.notchDepth = notchRadius * 0.75
        self.notchCornerRadius = min(14, notchRadius * 0.45)
    }

    init(cornerRadius: CGFloat, notchRadius: CGFloat, notchPadding: CGFloat) {
        self.init(topCornerRadius: cornerRadius, notchRadius: notchRadius, notchPadding: notchPadding)
    }

    init(
        cornerRadius: CGFloat,
        notchWidth: CGFloat,
        notchDepth: CGFloat,
        notchCornerRadius: CGFloat
    ) {
        self.cornerRadius = cornerRadius
        self.notchWidth = notchWidth
        self.notchDepth = notchDepth
        self.notchCornerRadius = notchCornerRadius
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 4)
        let midX = rect.midX
        let halfNotch = min(notchWidth, rect.width * 0.42) / 2
        let depth = min(notchDepth, rect.height * 0.55)
        let nr = min(notchCornerRadius, halfNotch * 0.9, depth * 0.9)

        let left = midX - halfNotch
        let right = midX + halfNotch
        let floorY = rect.minY + depth

        var path = Path()

        // Top-left outer corner → notch entry
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: left - nr, y: rect.minY))

        // Soft curve into the notch (top-left of cutout)
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.minY + nr),
            control: CGPoint(x: left, y: rect.minY)
        )

        // Down the left wall
        path.addLine(to: CGPoint(x: left, y: floorY - nr))

        // Bottom-left notch corner
        path.addQuadCurve(
            to: CGPoint(x: left + nr, y: floorY),
            control: CGPoint(x: left, y: floorY)
        )

        // Notch floor
        path.addLine(to: CGPoint(x: right - nr, y: floorY))

        // Bottom-right notch corner
        path.addQuadCurve(
            to: CGPoint(x: right, y: floorY - nr),
            control: CGPoint(x: right, y: floorY)
        )

        // Up the right wall
        path.addLine(to: CGPoint(x: right, y: rect.minY + nr))

        // Soft curve out of the notch (top-right of cutout)
        path.addQuadCurve(
            to: CGPoint(x: right + nr, y: rect.minY),
            control: CGPoint(x: right, y: rect.minY)
        )

        // Top edge → top-right outer corner
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right → bottom-right → bottom → bottom-left → left → close
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
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

/// The ORIGINAL centre button face (rounded square, orange fill, two shadows, hairline border, "+"), unchanged from the
/// last commit. Shared by the tab bar and the bubble overlay so the hand-off is identical. `glyphDegrees` turns "+" into "x".
struct TTCenterSquareFace: View {
    var glyphDegrees: Double = 0
    private let side: CGFloat = 56
    private let corner: CGFloat = TTSpace.s16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(TTColor.actionOrange)
                .frame(width: side, height: side)
                .shadow(color: TTColor.actionOrange.opacity(0.50), radius: 16, y: 6)
                .shadow(color: TTColor.actionOrange.opacity(0.28), radius: 5, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                }

            TTIcon(icon: .plus, filled: false, size: 20)
                .foregroundStyle(.white)
                .rotationEffect(.degrees(glyphDegrees))
        }
    }
}

/// Centre button for the liquid-bubble menu. Same look, hit area, guards and haptic as the bar's own button; the only
/// difference is that it reads `engine.presented` itself, so the menu opening re-runs just this small view.
private struct TTBubbleCenterButton: View {
    let engine: TTBubbleEngine
    let isAIChatPresented: Bool
    let onCenterTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focused: Bool
    #if canImport(UIKit)
    @State private var haptic = TTCenterHaptic()
    #endif

    var body: some View {
        let menuOpen = engine.presented // observed: this view only
        let hidden = menuOpen || isAIChatPresented
        Button {
            #if DEBUG || PERF_TEMP
            PlusTapProbe.shared.action(menu: menuOpen, chat: isAIChatPresented) // PERF-TEMP
            #endif
            // Already opening/open (or AI chat up): ignore — no second open, no second haptic.
            guard !engine.presented, !isAIChatPresented else { return }
            #if canImport(UIKit)
            haptic.fire()
            #endif
            onCenterTap()
        } label: {
            TTCenterSquareFace()
                // Bigger tap target, no visual change: 64×72 (56×56 + 4 each side + 12 up + 4 down).
                .contentShape(TTCenterHitShape())
        }
        .buttonStyle(TTTabBarCenterPressStyle())
        #if canImport(UIKit)
        .onAppear { haptic.prepare() }
        #endif
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        // The menu hand-off is instant (the overlay draws the same square on top); only the AI chat keeps its fade.
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.9), value: isAIChatPresented)
        .accessibilityLabel("Open quick actions")
        .accessibilityHint("AI assistant, create plan, assign, or view assignments")
        .accessibilityFocused($focused)
        // Report where this button really is, so the menu's "+" is drawn on exactly the same spot.
        .onGeometryChange(for: CGPoint.self) { proxy in
            let f = proxy.frame(in: .global)
            return CGPoint(x: f.midX, y: f.midY)
        } action: { p in
            if engine.buttonCenter != p, !engine.presented { engine.buttonCenter = p }
        }
        #if canImport(UIKit)
        // Bubble menu closed: VoiceOver focus goes back to the centre button.
        .onChange(of: menuOpen) { old, new in
            if old, !new, UIAccessibility.isVoiceOverRunning { focused = true }
        }
        #endif
        .perfTempPlusButton(menu: menuOpen, chat: isAIChatPresented) // PERF-TEMP
    }
}

/// Hit-test area of the centre button: the 56pt label plus 4pt left/right, 12pt up, 4pt down.
private struct TTCenterHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - 4, y: rect.minY - 12, width: rect.width + 8, height: rect.height + 16))
    }
}

#if canImport(UIKit)
/// Holds the single medium impact generator for the centre button.
final class TTCenterHaptic {
    private let generator = UIImpactFeedbackGenerator(style: .medium)
    func prepare() { generator.prepare() }
    func fire() {
        generator.impactOccurred()
        generator.prepare()
    }
}
#endif

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

#Preview("Tab Bar · Light") {
    struct Demo: View {
        @State private var tab = 0
        private let items = [
            TTTabBarItem(0, icon: .house1, label: "Home"),
            TTTabBarItem(1, icon: .barbellDiagonal, label: "Workout"),
            TTTabBarItem(2, icon: .forkKnife, label: "Nutrition"),
            TTTabBarItem(3, icon: .user, label: "Profile")
        ]
        var body: some View {
            ZStack(alignment: .bottom) {
                Color(white: 0.96).ignoresSafeArea()
                TTFloatingTabBar(tabs: items, selection: $tab, onCenterTap: {}, bottomInset: 34)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
    return Demo()
}

#Preview("Tab Bar · Dark") {
    struct Demo: View {
        @State private var tab = 0
        private let items = [
            TTTabBarItem(0, icon: .house1, label: "Home"),
            TTTabBarItem(1, icon: .barbellDiagonal, label: "Workout"),
            TTTabBarItem(2, icon: .forkKnife, label: "Nutrition"),
            TTTabBarItem(3, icon: .user, label: "Profile")
        ]
        var body: some View {
            ZStack(alignment: .bottom) {
                Color(white: 0.08).ignoresSafeArea()
                TTFloatingTabBar(tabs: items, selection: $tab, onCenterTap: {}, bottomInset: 34)
            }
            .ignoresSafeArea(edges: .bottom)
            .preferredColorScheme(.dark)
        }
    }
    return Demo()
}

#Preview("Pill Tabs") {
    struct Demo: View {
        @State private var selection = 0
        var body: some View {
            TTPillTabBar(titles: ["Week", "Month", "Year"], selection: $selection)
                .padding()
        }
    }
    return Demo()
}
