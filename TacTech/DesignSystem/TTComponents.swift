import SwiftUI

extension View {
    /// Hide the system nav bar / back chevron when a custom `TTBackButton` is shown.
    func ttHideSystemNavigationBar() -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
    }
}

/// Shared navigation back control — Sandow chevron in a rounded square.
struct TTBackButton: View {
    enum Style {
        /// Dark icon on light gray (auth, assessment, light headers).
        case onLight
        /// White icon on charcoal (dark headers like Account Settings).
        case onDark
    }

    static let size: CGFloat = 40

    var style: Style = .onLight
    /// Visual square size (default matches legacy screens).
    var size: CGFloat = Self.size
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TTIcon(icon: .chevronLeft, size: max(14, size * 0.4))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var foreground: Color {
        switch style {
        case .onLight: TTColor.ink
        case .onDark: .white
        }
    }

    private var background: Color {
        switch style {
        case .onLight: Color(white: 0.94)
        case .onDark: Color(white: 0.28)
        }
    }
}

/// Trailing disclosure chevron — same Sandow mark as `TTBackButton`, mirrored to point right.
struct TTChevronForward: View {
    var size: CGFloat = 14
    var color: Color = Color(white: 0.55)

    var body: some View {
        TTIcon(icon: .chevronRight, size: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// Shared dark settings header — rectangular top bar, status-bar bleed.
/// Scroll collapse morphs the title from under the back button to beside it.
struct TTDarkPageHeader: View {
    /// Same card height everywhere (below status bar content area).
    static let cardHeight: CGFloat = 148
    /// Compact single-row height (back + title side by side).
    static let compactHeight: CGFloat = 64
    /// Radius for the content sheet under this header (was previously on the header bottom).
    static let bottomRadius: CGFloat = 36
    static var contentTopRadius: CGFloat { bottomRadius }

    let title: String
    var showsBack: Bool = true
    var collapseProgress: CGFloat = 0
    var onBack: (() -> Void)? = nil

    private let charcoal = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    init(
        title: String,
        showsBack: Bool = true,
        collapseProgress: CGFloat = 0,
        onBack: (() -> Void)? = nil
    ) {
        self.title = title
        self.showsBack = showsBack
        self.collapseProgress = collapseProgress
        self.onBack = onBack
    }

    /// Trailing-closure convenience — always shows the back button.
    init(title: String, collapseProgress: CGFloat = 0, onBack: @escaping () -> Void) {
        self.title = title
        self.showsBack = true
        self.collapseProgress = collapseProgress
        self.onBack = onBack
    }

    private var p: CGFloat { min(1, max(0, collapseProgress)) }
    private var expand: CGFloat { 1 - p }

    private var headerHeight: CGFloat {
        Self.compactHeight + (Self.cardHeight - Self.compactHeight) * expand
    }

    /// Title slides from below the back control into the same row.
    private var titleOffsetX: CGFloat {
        guard showsBack else { return 0 }
        return (TTBackButton.size + 12) * p
    }

    private var titleOffsetY: CGFloat {
        guard showsBack else { return 4 * expand }
        // Expanded: under the back button. Collapsed: vertically centered with it.
        let expandedY = TTBackButton.size + 14
        let collapsedY = (TTBackButton.size - (28 - 10 * p)) / 2
        return expandedY * expand + collapsedY * p
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsBack {
                TTBackButton(style: .onDark) {
                    onBack?()
                }
                .scaleEffect(1 - 0.06 * p, anchor: .topLeading)
            }

            Text(title)
                .font(TTFont.workSans(28 - 10 * p, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(p > 0.55 ? 1 : 2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, titleOffsetX + 4)
                .offset(x: titleOffsetX, y: titleOffsetY)
        }
        .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)
        .padding(.horizontal, TTSpace.screen)
        .padding(.top, 10 - 2 * p)
        .padding(.bottom, 16 - 6 * p)
        .background {
            Rectangle()
                .fill(charcoal)
                .ignoresSafeArea(edges: .top)
        }
        // Scroll-driven only — spring here lagged expand on the way back down.
    }
}

/// One shared "Copy invite code" button: copies, shows "Copied" with a checkmark for 2 s,
/// plays a success haptic and announces it for VoiceOver. Each caller supplies its own look.
struct TTCopyCodeButton<Label: View>: View {
    let code: String
    @ViewBuilder var label: (_ copied: Bool) -> Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Invite code copied"))
            setCopied(true)
            // Tapping again restarts the 2 seconds.
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { setCopied(false) }
            }
        } label: {
            label(copied)
        }
        .onDisappear { resetTask?.cancel() }
    }

    private func setCopied(_ value: Bool) {
        if reduceMotion {
            copied = value
        } else {
            withAnimation(.easeInOut(duration: 0.15)) { copied = value }
        }
    }
}

/// "Copy" ↔ "Copied" with a checkmark. Font and colour come from the caller's styling.
struct TTCopyCodeLabel: View {
    let copied: Bool
    var font: Font

    var body: some View {
        HStack(spacing: 6) {
            if copied {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(copied ? "Copied" : "Copy")
                .font(font)
        }
    }
}

struct TTButton: View {
    enum Style { case primary, secondary, ghost }

    let title: String
    var icon: String?
    var style: Style = .primary
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(TTFont.heading(16))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous)
                    .stroke(border, lineWidth: style == .secondary ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var foreground: Color {
        switch style {
        case .primary: TTColor.surface
        case .secondary, .ghost: TTColor.ink
        }
    }

    private var background: Color {
        switch style {
        case .primary: TTColor.brand
        case .secondary: TTColor.surface
        case .ghost: .clear
        }
    }

    private var border: Color {
        style == .secondary ? TTColor.line : .clear
    }
}

struct TTTextField: View {
    let title: String
    var icon: String?
    var isSecure: Bool = false
    var isError: Bool = false
    var axis: Axis = .horizontal
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
                .tracking(0.6)
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(focused ? TTColor.actionOrange : TTColor.inkMuted)
                        .frame(width: 20)
                }
                Group {
                    if isSecure {
                        SecureField("", text: $text, prompt: Text(title).foregroundStyle(TTColor.inkSubtle))
                    } else {
                        TextField("", text: $text, prompt: Text(title).foregroundStyle(TTColor.inkSubtle), axis: axis)
                    }
                }
                .font(TTFont.body(16))
                .foregroundStyle(TTColor.ink)
                .focused($focused)
                .tint(TTColor.actionOrange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, axis == .vertical ? 12 : 0)
            .frame(minHeight: TTSpace.fieldHeight, alignment: .leading)
            .ttInputChrome(
                focused: focused,
                isError: isError,
                cornerRadius: TTRadius.sm,
                idleFill: TTColor.surfaceAlt
            )
        }
    }
}

/// Labeled Sandow text field with Inputs-1 active orange border (no SF Symbol required).
struct TTSandowLabeledField: View {
    let title: String
    var prompt: String = ""
    var axis: Axis = .horizontal
    var isError: Bool = false
    var idleFill: Color = TTInputChrome.whiteFill
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
            TextField("", text: $text, prompt: Text(prompt.isEmpty ? title : prompt).foregroundStyle(TTColor.inkSubtle), axis: axis)
                .lineLimit(axis == .vertical ? 3...6 : 1...1)
                .font(TTFont.body(16))
                .foregroundStyle(TTColor.ink)
                .focused($focused)
                .tint(TTColor.actionOrange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ttInputChrome(
                    focused: focused,
                    isError: isError,
                    cornerRadius: 12,
                    idleFill: idleFill
                )
        }
    }
}

struct TTAvatar: View {
    let name: String
    var size: CGFloat = 48
    var tint: Color = TTColor.brand
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        if redaction.contains(.placeholder) {
            Circle().fill(Color.ttSkeletonFill).frame(width: size, height: size)
        } else {
            avatar
        }
    }

    private var avatar: some View {
        Text(initials)
            .font(TTFont.workSans(size * 0.36, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16))
            .clipShape(Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

struct TTSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(TTFont.title(20))
                .foregroundStyle(TTColor.ink)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.brand)
            }
        }
    }
}

struct TTChip: View {
    let title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TTFont.caption(13))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? TTColor.surface : TTColor.ink)
                .background(isSelected ? TTColor.brand : TTColor.surfaceAlt)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct TTMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        TTMetricSplitCard(
            title: value,
            metadata: "\(title) · \(subtitle)",
            systemImage: icon
        )
    }
}

struct TTProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 10
    var size: CGFloat = 86

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct TTWeekStrip: View {
    @Binding var selected: Date
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                Button {
                    selected = day
                } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(TTFont.caption(11))
                        Text(day.formatted(.dateTime.day()))
                            .font(TTFont.heading(15))
                    }
                    .foregroundStyle(isSelected ? TTColor.surface : TTColor.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? TTColor.brand : TTColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? .clear : TTColor.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var days: [Date] {
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selected)) ?? selected
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

struct TTScreenHeader: View {
    let eyebrow: String
    let title: String
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkMuted)
                    .tracking(0.8)
                Text(title)
                    .font(TTFont.display(28))
                    .foregroundStyle(TTColor.ink)
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct TTEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(TTFont.workSans(28, weight: .medium))
                .foregroundStyle(TTColor.brand)
                .frame(width: 64, height: 64)
                .background(TTColor.brandSoft)
                .clipShape(Circle())
            Text(title)
                .font(TTFont.heading(17))
                .foregroundStyle(TTColor.ink)
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

struct TTDropPicker<Value: Hashable>: View {
    var title: String = ""
    @Binding var selection: Value
    let options: [Value]
    var format: (Value) -> String = { "\($0)" }

    @State private var showSheet = false

    private var resolvedOptions: [Value] {
        options.contains(selection) ? options : [selection] + options
    }

    private var usesSheet: Bool { resolvedOptions.count > 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(TTFont.caption(10))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            Group {
                if usesSheet {
                    Button { showSheet = true } label: { chip }
                } else {
                    Menu {
                        ForEach(resolvedOptions, id: \.self) { option in
                            Button {
                                selection = option
                            } label: {
                                if option == selection {
                                    Label(format(option), systemImage: "checkmark")
                                } else {
                                    Text(format(option))
                                }
                            }
                        }
                    } label: {
                        chip
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showSheet) {
            TTDropPickerSheet(
                title: title.isEmpty ? "Select" : title,
                selection: $selection,
                options: resolvedOptions,
                format: format
            )
            .ttModalSheetPresentation(detents: [.medium])
        }
    }

    private var chip: some View {
        HStack(spacing: 6) {
            Text(format(selection))
                .font(TTFont.heading(14))
                .foregroundStyle(TTColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            TTIcon(icon: .chevronDown, size: 11)
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(TTColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(TTColor.line, lineWidth: 1)
        )
    }
}

private struct TTDropPickerSheet<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    var format: (Value) -> String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(title: title, background: .white) {
                Button("Done") { dismiss() }
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(TTColor.brand)
            }

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(format(option)).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }
}

#Preview("Dark Page Header") {
    VStack(spacing: 0) {
        TTDarkPageHeader(title: "Profile", showsBack: true, onBack: {})
        Spacer()
    }
    .background(Color.white)
}

// MARK: - Reversed chrome: rectangular header + top-rounded content sheet

enum TTSheetChrome {
    /// Home dashboard — continuous squircle, slightly softer than a hard 56pt bubble.
    static let homeTopRadius: CGFloat = 44
    /// Compact home lip when header is fully collapsed.
    static let homeTopRadiusCompact: CGFloat = 28
    /// Settings / detail pages under `TTDarkPageHeader`.
    static let pageTopRadius: CGFloat = TTDarkPageHeader.contentTopRadius

    /// Morph home sheet lip with header collapse (0 = expanded, 1 = compact).
    static func homeTopRadius(collapseProgress: CGFloat) -> CGFloat {
        let t = TTHomeHeaderCollapse.displayProgress(from: collapseProgress)
        return homeTopRadius + (homeTopRadiusCompact - homeTopRadius) * t
    }
}

/// Shared chrome for modal `.sheet` presentations (Create Plan, library, assign, inbox, …).
enum TTModalSheetChrome {
    /// Side inset — matches content cards so back square lines up with card edges.
    static let horizontalPadding: CGFloat = TTSpace.screen
    /// Equal top/bottom inset around header controls.
    static let headerVerticalPadding: CGFloat = 16
    static let headerSpacing: CGFloat = 14
    static let contentTopPadding: CGFloat = 16
    static let contentBottomPadding: CGFloat = 32
    static let contentSpacing: CGFloat = 18
    static let cornerRadius: CGFloat = 28
    /// Larger than page back (40) so sheet chrome doesn’t feel cramped.
    static let controlSize: CGFloat = 44
    static let controlCornerRadius: CGFloat = 14
}

/// Modal sheet top bar — back/close, title (+ optional subtitle), optional trailing.
/// Side inset matches body cards; controls are vertically centered with equal bar padding.
struct TTModalSheetHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var background: Color = .white
    var showsBack: Bool = true
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        subtitle: String? = nil,
        background: Color = .white,
        showsBack: Bool = true,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.background = background
        self.showsBack = showsBack
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: TTModalSheetChrome.headerSpacing) {
            if showsBack {
                TTBackButton(
                    style: .onLight,
                    size: TTModalSheetChrome.controlSize
                ) {
                    if let onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TTFont.workSans(20, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TTFont.caption(13))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
                .frame(minWidth: TTModalSheetChrome.controlSize, alignment: .trailing)
        }
        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
        .padding(.vertical, TTModalSheetChrome.headerVerticalPadding)
        .frame(maxWidth: .infinity)
        .background(background)
    }
}

extension TTModalSheetHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        background: Color = .white,
        showsBack: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            background: background,
            showsBack: showsBack,
            onBack: onBack,
            trailing: { EmptyView() }
        )
    }
}

/// Compact trailing control for modal headers (matches `TTBackButton` footprint).
struct TTModalSheetIconButton: View {
    var icon: SandowIcon
    var filled: Bool = true
    var enabled: Bool = true
    var tint: Color = .white
    var background: Color = TTColor.actionOrange
    var disabledBackground: Color = Color(white: 0.75)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TTIcon(icon: icon, filled: filled, size: 16)
                .foregroundStyle(tint)
                .frame(width: TTModalSheetChrome.controlSize, height: TTModalSheetChrome.controlSize)
                .background(enabled ? background : disabledBackground)
                .clipShape(RoundedRectangle(cornerRadius: TTModalSheetChrome.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

extension View {
    /// Canvas sheet with rounded **top** corners. Clips scrolling content to the curve
    /// and adds a soft lift into the dark header so the lip reads as a real surface.
    func ttTopRoundedSheet(radius: CGFloat, fill: Color) -> some View {
        modifier(TTTopRoundedSheetModifier(radius: radius, fill: fill))
    }

    /// Standard modal sheet lip: grabber + continuous corner radius (+ optional detents).
    func ttModalSheetPresentation(
        detents: Set<PresentationDetent>? = nil,
        dragIndicator: Visibility = .visible
    ) -> some View {
        modifier(TTModalSheetPresentationModifier(detents: detents, dragIndicator: dragIndicator))
    }
}

private struct TTModalSheetPresentationModifier: ViewModifier {
    let detents: Set<PresentationDetent>?
    let dragIndicator: Visibility

    func body(content: Content) -> some View {
        let styled = content
            .presentationDragIndicator(dragIndicator)
            .presentationCornerRadius(TTModalSheetChrome.cornerRadius)
            .onAppear { PerfTemp.interval("sheet.present", seconds: 0.5) } // PERF-TEMP
            .onDisappear { PerfTemp.event("sheet.dismiss") } // PERF-TEMP
        if let detents {
            styled.presentationDetents(detents)
        } else {
            styled
        }
    }
}

private struct TTTopRoundedSheetModifier: ViewModifier {
    let radius: CGFloat
    let fill: Color

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            // Clip scroll / bounce to the top curve only — applied before the fill
            // so the canvas can still extend under the home indicator.
            .clipShape(shape)
            .overlay {
                // Soft rim light along the top lip only.
                shape
                    .stroke(Color.white.opacity(0.5), lineWidth: 0.7)
                    .mask(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.14)
                        )
                    )
                    .allowsHitTesting(false)
            }
            // Canvas fill behind clipped content — no bottom safe-area gap.
            .background {
                shape
                    .fill(fill)
                    .ignoresSafeArea(edges: .bottom)
            }
            // Upward contact shadow onto the black/charcoal header.
            .background {
                shape
                    .fill(fill)
                    .shadow(color: Color.black.opacity(0.38), radius: 16, y: -5)
                    .shadow(color: Color.black.opacity(0.16), radius: 3, y: -1)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(edges: .bottom)
            }
    }
}

// MARK: - Toast

enum TTToastStyle {
    case success
    case error
    case info
    case warning
    case accent

    var alertTone: TTAlertTone {
        switch self {
        case .success: .success
        case .error: .error
        case .info: .info
        case .warning: .warning
        case .accent: .accent
        }
    }
}

struct TTToastMessage: Equatable {
    let text: String
    var style: TTToastStyle = .success
    var subtitle: String? = nil
    var action: TTToastAction? = nil
}

/// Optional trailing link on a toast (e.g. "Undo"). Each instance is unique for equality.
struct TTToastAction: Equatable {
    let title: String
    let handler: () -> Void
    private let id = UUID()

    init(title: String, handler: @escaping () -> Void) {
        self.title = title
        self.handler = handler
    }

    static func == (lhs: TTToastAction, rhs: TTToastAction) -> Bool { lhs.id == rhs.id }
}

/// Floating bottom toast — Sandow alert chrome; auto-dismisses after `duration`.
///
/// Presentation follows WCAG 2.2 Timing Adjustable + Material Snackbar:
/// - status is announced to assistive tech
/// - user can dismiss early (does not change call-site trigger logic)
/// - error/warning stay visible longer by default
struct TTToastBanner: View {
    let message: TTToastMessage
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        if let action = message.action {
            TTAlertBanner(
                tone: message.style.alertTone,
                title: message.text,
                subtitle: message.subtitle,
                actionTitle: action.title,
                onAction: {
                    action.handler()
                    onDismiss?()
                },
                actionStyle: .link
            )
            .frame(maxWidth: 360)
            .padding(.horizontal, TTSpace.screen)
            // Reads "<message>, <action> button"; double-tap runs the action.
            .accessibilityElement(children: .combine)
        } else {
            TTAlertBanner(
                tone: message.style.alertTone,
                title: message.text,
                subtitle: message.subtitle,
                onDismiss: onDismiss
            )
            .frame(maxWidth: 360)
            .padding(.horizontal, TTSpace.screen)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(.isStaticText)
        }
    }

    private var accessibilitySummary: String {
        var parts = [message.style.accessibilityRoleName, message.text]
        if let subtitle = message.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        return parts.joined(separator: ". ")
    }
}

extension TTToastStyle {
    /// Spoken role prefix for VoiceOver / TalkBack-style announcements.
    var accessibilityRoleName: String {
        switch self {
        case .success: "Success"
        case .error: "Error"
        case .info: "Information"
        case .warning: "Warning"
        case .accent: "Notice"
        }
    }

    /// WCAG 2.2.1 — give critical statuses more time before auto-dismiss.
    var minimumReadableDuration: TimeInterval {
        switch self {
        case .error, .warning: 4.0
        case .success, .info, .accent: 1.8
        }
    }
}

extension View {
    /// Shows a floating toast overlay. Pass `nil` to hide; auto-clears after `duration`.
    ///
    /// Automatically sits **above** the floating root tab bar via `ttRootTabBarClearance`
    /// (Material snackbar / above-bottom-nav standard). `bottomInset` is extra gap above that chrome.
    func ttToast(
        _ message: Binding<TTToastMessage?>,
        duration: TimeInterval = 1.8,
        bottomInset: CGFloat = 16
    ) -> some View {
        modifier(TTToastModifier(message: message, duration: duration, bottomInset: bottomInset))
    }
}

private struct TTToastModifier: ViewModifier {
    @Binding var message: TTToastMessage?
    let duration: TimeInterval
    let bottomInset: CGFloat
    @State private var dismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ttRootTabBarClearance) private var tabBarClearance

    /// Gap above tab bar (or screen bottom when chrome is hidden).
    private var resolvedBottomInset: CGFloat {
        bottomInset + max(tabBarClearance, 0)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    TTToastBanner(message: message) {
                        dismissToast()
                    }
                    .padding(.bottom, resolvedBottomInset)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    // Hit-testing on so dismiss control meets WCAG / Material snackbar norms.
                    .allowsHitTesting(true)
                    .zIndex(1000)
                }
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86),
                value: message
            )
            .onChange(of: message) { _, newValue in
                dismissTask?.cancel()
                guard let newValue else { return }
                announce(newValue)
                // Actionable toasts (e.g. Undo) stay long enough to reach the button.
                let hold = newValue.action != nil
                    ? 5.0
                    : max(duration, newValue.style.minimumReadableDuration)
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    dismissToast()
                }
            }
    }

    private func dismissToast() {
        withAnimation(reduceMotion ? .easeIn(duration: 0.12) : .easeIn(duration: 0.2)) {
            message = nil
        }
    }

    private func announce(_ message: TTToastMessage) {
        #if canImport(UIKit)
        var parts = [message.style.accessibilityRoleName, message.text]
        if let subtitle = message.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        UIAccessibility.post(notification: .announcement, argument: parts.joined(separator: ". "))
        #endif
    }
}

// MARK: - Assign success feedback (Material snackbar + iOS success haptic)

/// Fires toast + haptic + brief celebration when a plan is assigned.
@MainActor
enum TTAssignSuccessFeedback {
    static func play(
        toast: Binding<TTToastMessage?>,
        celebrate: Binding<Bool>,
        planTitle: String,
        traineeName: String
    ) {
        toast.wrappedValue = TTToastMessage(
            text: "Plan assigned",
            style: .success,
            subtitle: "\(planTitle) → \(traineeName)"
        )
        celebrate.wrappedValue = true
        TTHomeHaptics.success()
    }

    static func playUnassign(
        toast: Binding<TTToastMessage?>,
        traineeName: String
    ) {
        toast.wrappedValue = TTToastMessage(
            text: "Plan unassigned",
            style: .info,
            subtitle: traineeName
        )
        TTHomeHaptics.soft()
    }
}

extension View {
    /// Toast + confetti burst for assign success. Pair with `TTAssignSuccessFeedback.play`.
    func ttAssignSuccessChrome(
        toast: Binding<TTToastMessage?>,
        celebrate: Binding<Bool>,
        bottomInset: CGFloat = 16
    ) -> some View {
        modifier(
            TTAssignSuccessChromeModifier(
                toast: toast,
                celebrate: celebrate,
                bottomInset: bottomInset
            )
        )
    }
}

private struct TTAssignSuccessChromeModifier: ViewModifier {
    @Binding var toast: TTToastMessage?
    @Binding var celebrate: Bool
    var bottomInset: CGFloat

    func body(content: Content) -> some View {
        content
            .ttToast($toast, duration: 2.4, bottomInset: bottomInset)
            .ttHomeWin(celebrate: $celebrate, tint: TTColor.success)
    }
}

/// Primary CTA that morphs to a green “Assigned” state after success.
struct TTAssignSuccessButton: View {
    var title: String
    var successTitle: String = "Assigned"
    var isEnabled: Bool
    var isLoading: Bool
    var showSuccess: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if showSuccess {
                    TTIcon(icon: .check, filled: true, size: 16)
                    Text(successTitle)
                        .font(TTFont.workSans(16, weight: .bold))
                } else {
                    Text(title)
                        .font(TTFont.workSans(16, weight: .semibold))
                    TTIcon(icon: .check, filled: true, size: 14)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(showSuccess ? TTColor.success : (isEnabled ? Color.black : Color(white: 0.72)))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(showSuccess && !reduceMotion ? 1.02 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.78),
                value: showSuccess
            )
            .animation(.easeOut(duration: 0.15), value: isLoading)
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.98))
        .disabled(!isEnabled || isLoading || showSuccess)
        .accessibilityLabel(showSuccess ? successTitle : title)
    }
}

#Preview("Buttons & Fields") {
    VStack(spacing: 16) {
        TTBackButton(style: .onLight) {}
        TTButton(title: "Continue", action: {})
        TTButton(title: "Secondary", style: .secondary, action: {})
        TTAvatar(name: "Maya Athlete", size: 64)
    }
    .padding()
    .ttPreviewTrainee()
}

// MARK: - PERF-TEMP measuring layer (remove in Phase 3)

/// PERF-TEMP: one switch per suspect. `defaultValue` is today's behaviour, so a fresh install is unchanged.
enum PerfTempKey: String, CaseIterable, Identifiable { // PERF-TEMP
    case homeShadow, homeEars, homeCopies // PERF-TEMP
    case fabBlur, fabLoops // PERF-TEMP
    case liveSync // PERF-TEMP
    case fpsMeter // PERF-TEMP
    case homeScrollObserver // PERF-TEMP
    case realtime // PERF-TEMP
    case compactNetLogs // PERF-TEMP
    case printChanges // PERF-TEMP
    case plusTouchLog // PERF-TEMP
    case bubbleMenu // PERF-TEMP

    var id: String { rawValue }

    /// Today's behaviour (the "baseline").
    var defaultValue: Bool {
        switch self {
        case .printChanges, .compactNetLogs, .fpsMeter, .plusTouchLog: return false
        default: return true
        }
    }

    var title: String {
        switch self {
        case .homeShadow: return "Header extra shadow"
        case .homeEars: return "Header corner mask (ears)"
        case .homeCopies: return "Hidden header copies (measuring)"
        case .fabBlur: return "+ menu blur + contrast"
        case .fabLoops: return "+ menu repeatForever loops"
        case .liveSync: return "TrainerLiveSync refresh"
        case .fpsMeter: return "FPS meter pill + hitch counting (default OFF)"
        case .homeScrollObserver: return "Home scroll observer (collapse progress)"
        case .realtime: return "Realtime clients (OFF = don't connect)"
        case .compactNetLogs: return "Compact network error logs"
        case .printChanges: return "Print redraws (_printChanges)"
        case .plusTouchLog: return "+ button touch log (default OFF)" // PERF-TEMP
        case .bubbleMenu: return "Bubble menu (new)" // PERF-TEMP
        }
    }
}

#if DEBUG || PERF_TEMP
import os

/// PERF-TEMP: bumps when a switch changes so views that read a switch redraw.
@MainActor @Observable
final class PerfTempState { // PERF-TEMP
    static let shared = PerfTempState()
    var revision = 0
}

enum PerfTemp { // PERF-TEMP
    static let signposter = OSSignposter(subsystem: "com.tactech.trainer.perf", category: "PerfTemp")

    /// Any thread. Not observed.
    nonisolated static func raw(_ key: PerfTempKey) -> Bool {
        (UserDefaults.standard.object(forKey: "perftemp." + key.rawValue) as? Bool) ?? key.defaultValue
    }

    /// Main actor (views). Reading it makes the view redraw when a switch flips.
    @MainActor static func on(_ key: PerfTempKey) -> Bool {
        _ = PerfTempState.shared.revision
        return raw(key)
    }

    @MainActor static func set(_ key: PerfTempKey, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: "perftemp." + key.rawValue)
        PerfTempState.shared.revision += 1
        if key == .fpsMeter { PerfMeter.shared.sync() }
        if key == .plusTouchLog { PlusTapProbe.shared.sync() } // PERF-TEMP
    }

    @MainActor static func resetAll() {
        for key in PerfTempKey.allCases { UserDefaults.standard.removeObject(forKey: "perftemp." + key.rawValue) }
        PerfTempState.shared.revision += 1
        PerfMeter.shared.sync()
        PlusTapProbe.shared.sync() // PERF-TEMP
    }

    /// Signpost interval that starts now and ends after `seconds` (the animation's nominal length).
    nonisolated static func interval(_ name: StaticString, seconds: TimeInterval) {
        let label = "\(name)"
        DispatchQueue.main.async { MainActor.assumeIsolated { PerfMeter.shared.beginMoment(label, seconds: seconds) } }
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            signposter.endInterval(name, state)
        }
    }

    nonisolated static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    /// Names the visible tab for the meter's per-screen counts.
    @MainActor static func screenTab(_ name: String) { PerfMeter.shared.setBase(name) } // PERF-TEMP

    /// PERF-TEMP: printed once per screen visit by each scroll reader, to find the one behind the
    /// "<OnScrollGeometryChange Modifier> tried to update multiple times per frame" warning.
    nonisolated static func scrollReaderFired(_ file: String, _ line: Int) { // PERF-TEMP
        print("PERF-TEMP scroll-reader: \(file):\(line)")
    }

    /// Body-run counter (Instruments shows these as events) and optional `_printChanges`.
    @MainActor static func trace(_ name: String, _ printChanges: () -> Void) {
        signposter.emitEvent("body", "\(name)")
        if raw(.printChanges) {
            print("PERF-TEMP body: \(name)")
            printChanges()
        }
    }
}

/// PERF-TEMP: prints `scrollReaderFired` the first time `value` changes (e.g. a `scrollPosition` binding).
private struct PerfTempFirstChange<V: Equatable>: ViewModifier { // PERF-TEMP
    let value: V
    let file: String
    let line: Int
    @State private var printed = false

    func body(content: Content) -> some View {
        content.onChange(of: value) { _, _ in
            guard !printed else { return }
            printed = true
            PerfTemp.scrollReaderFired(file, line)
        }
    }
}

extension View {
    func perfTempFirstChange<V: Equatable>(of value: V, file: String, line: Int) -> some View { // PERF-TEMP
        modifier(PerfTempFirstChange(value: value, file: file, line: line))
    }
}

struct PerfTempSheet: View { // PERF-TEMP
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                section("1 · Home header", [.homeShadow, .homeEars, .homeCopies])
                section("2 · + menu", [.bubbleMenu, .fabBlur, .fabLoops])
                section("5 · Refresh", [.liveSync])
                section("Diagnostics", [.homeScrollObserver, .realtime, .compactNetLogs])
                section("Logging", [.printChanges])
                Section("FPS meter") {
                    Toggle(PerfTempKey.fpsMeter.title, isOn: Binding(
                        get: { PerfTemp.on(.fpsMeter) },
                        set: { PerfTemp.set(.fpsMeter, $0) }
                    ))
                    NavigationLink("Hitch report") { PerfMeterReportView() }
                }
                PlusTapReportSections() // PERF-TEMP
                PerfBubbleRecorderSection() // PERF-TEMP
                Section {
                    Button("Reset all to baseline") { PerfTemp.resetAll() }
                } footer: {
                    Text("Baseline = today's behaviour. Switches change performance only. Debug sheet: long-press the date at the top of Home.")
                }
            }
            .navigationTitle("PERF-TEMP")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func section(_ title: String, _ keys: [PerfTempKey]) -> some View {
        Section(title) {
            ForEach(keys) { key in
                Toggle(key.title, isOn: Binding(
                    get: { PerfTemp.on(key) },
                    set: { PerfTemp.set(key, $0) }
                ))
            }
        }
    }
}
#else
/// PERF-TEMP: release stub — every switch returns today's behaviour, every probe is a no-op.
enum PerfTemp { // PERF-TEMP
    nonisolated static func raw(_ key: PerfTempKey) -> Bool { key.defaultValue }
    @MainActor static func on(_ key: PerfTempKey) -> Bool { key.defaultValue }
    nonisolated static func interval(_ name: StaticString, seconds: TimeInterval) {}
    nonisolated static func event(_ name: StaticString) {}
    nonisolated static func scrollReaderFired(_ file: String, _ line: Int) {} // PERF-TEMP
    @MainActor static func screenTab(_ name: String) {} // PERF-TEMP
    @MainActor static func trace(_ name: String, _ printChanges: () -> Void) {}
}

extension View {
    func perfTempFirstChange<V: Equatable>(of value: V, file: String, line: Int) -> some View { self } // PERF-TEMP
    func perfTempPlusButton(menu: Bool, chat: Bool) -> some View { self } // PERF-TEMP
}
#endif

// MARK: - PERF-TEMP FPS meter + hitch report (DEBUG / -DPERF_TEMP only, default OFF)

#if DEBUG || PERF_TEMP
import QuartzCore

/// PERF-TEMP: frame-time meter. A CADisplayLink measures the time between main-thread frames; a frame longer
/// than 2× the display's expected frame time is a hitch. Stats are kept per screen and per animation moment.
/// NOTE: it only sees main-thread stalls (not GPU/render-server hitches), and the link asks for up to 120 Hz,
/// so with the meter ON the display may run faster than it otherwise would.
@MainActor @Observable
final class PerfMeter { // PERF-TEMP
    static let shared = PerfMeter()

    struct Stat { var hitches = 0; var worstMs = 0.0; var frames = 0 }
    struct Row: Identifiable {
        let id: String
        let kind: String
        let name: String
        let stat: Stat
    }

    // Pill — refreshed once per second.
    var fps = 0
    var worstMsLastSecond = 0.0
    var level = 0 // 0 green, 1 yellow, 2 red
    var totalHitches = 0
    var currentScreen = "app"
    var isRunning = false
    private(set) var revision = 0 // bumped once per second so the report view refreshes

    @ObservationIgnored private var screenStats: [String: Stat] = [:]
    @ObservationIgnored private var momentStats: [String: Stat] = [:]
    @ObservationIgnored private var activeMoments: [String: CFTimeInterval] = [:]
    @ObservationIgnored private var screenStack: [String] = []
    @ObservationIgnored private var baseScreen = "app"
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var linkTarget: LinkTarget?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var windowStart: CFTimeInterval = 0
    @ObservationIgnored private var windowFrames = 0
    @ObservationIgnored private var windowWorst: CFTimeInterval = 0
    @ObservationIgnored private var totalFrames = 0
    @ObservationIgnored private var pillWindow: UIWindow?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// PERF-TEMP (+ touch log): frame times of the last second, for "worst frame in the previous 300 ms".
    @ObservationIgnored private var recentFrames: [(t: CFTimeInterval, ms: Double)] = []

    private final class LinkTarget: NSObject {
        var handler: ((CADisplayLink) -> Void)?
        @objc func tick(_ link: CADisplayLink) { handler?(link) }
    }

    private final class PassthroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    var expectedMs: Double { 1000.0 / Double(UIScreen.main.maximumFramesPerSecond) }

    // MARK: Start / stop

    /// Reads the debug-sheet switch and starts or stops the meter.
    func sync() {
        if PerfTemp.raw(.fpsMeter) { start() } else { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        lastTimestamp = 0
        let target = LinkTarget()
        target.handler = { [weak self] link in
            MainActor.assumeIsolated { self?.tick(link) }
        }
        let link = CADisplayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        linkTarget = target
        observers = [
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.link?.isPaused = true }
            },
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lastTimestamp = 0; self?.link?.isPaused = false }
            }
        ]
        showPill()
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        link?.invalidate()
        link = nil
        linkTarget = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        pillWindow?.isHidden = true
        pillWindow = nil
    }

    private func showPill() {
        guard pillWindow == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: PerfMeterPill())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        pillWindow = window
    }

    // MARK: Screens and moments

    func pushScreen(_ name: String) {
        screenStack.append(name)
        currentScreen = screenStack.last ?? baseScreen
    }

    func popScreen(_ name: String) {
        if let index = screenStack.lastIndex(of: name) { screenStack.remove(at: index) }
        currentScreen = screenStack.last ?? baseScreen
    }

    func setBase(_ name: String) {
        baseScreen = name
        currentScreen = screenStack.last ?? baseScreen
    }

    /// An animation moment (tab.switch, fab.open, …) is "active" for its nominal duration.
    func beginMoment(_ name: String, seconds: TimeInterval) {
        activeMoments[name] = CACurrentMediaTime() + seconds
        if momentStats[name] == nil { momentStats[name] = Stat() }
    }

    // MARK: Frame tick

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { windowStart = now; return }
        let dt = now - lastTimestamp
        if dt > 1.0 { windowStart = now; return } // app was suspended / paused — not a hitch
        let expected = 1.0 / Double(UIScreen.main.maximumFramesPerSecond)
        let ms = dt * 1000
        let hitch = dt > 2 * expected
        recentFrames.append((now, ms)) // PERF-TEMP
        recentFrames.removeAll { $0.t < now - 1 } // PERF-TEMP

        windowFrames += 1
        totalFrames += 1
        windowWorst = max(windowWorst, dt)

        var s = screenStats[currentScreen, default: Stat()]
        s.frames += 1
        s.worstMs = max(s.worstMs, ms)
        if hitch { s.hitches += 1; totalHitches += 1 }
        screenStats[currentScreen] = s

        if !activeMoments.isEmpty {
            for (name, end) in activeMoments {
                if end < now { activeMoments[name] = nil; continue }
                var m = momentStats[name, default: Stat()]
                m.frames += 1
                m.worstMs = max(m.worstMs, ms)
                if hitch { m.hitches += 1 }
                momentStats[name] = m
            }
        }

        if now - windowStart >= 1 {
            fps = windowFrames
            worstMsLastSecond = windowWorst * 1000
            let ratio = windowWorst / expected
            level = ratio <= 1.5 ? 0 : (ratio <= 2 ? 1 : 2)
            windowFrames = 0
            windowWorst = 0
            windowStart = now
            revision += 1
        }
    }

    // MARK: PERF-TEMP + touch log queries (nil = meter is off, so there is no data)

    /// Worst frame time (ms) among frames that ended within `seconds` before `now`.
    func worstMs(lastSeconds seconds: Double, now: CFTimeInterval) -> Double? {
        guard isRunning else { return nil }
        return recentFrames.filter { $0.t >= now - seconds }.map(\.ms).max() ?? 0
    }

    /// Time since the last display-link frame. Large = the main thread was busy until just now.
    func msSinceLastFrame(now: CFTimeInterval) -> Double? {
        guard isRunning, lastTimestamp > 0 else { return nil }
        return max(0, (now - lastTimestamp) * 1000)
    }

    // MARK: Report

    func reset() {
        screenStats = [:]
        momentStats = [:]
        totalHitches = 0
        totalFrames = 0
        revision += 1
    }

    var topRows: [Row] {
        _ = revision
        let rows = screenStats.map { Row(id: "s-" + $0.key, kind: "screen", name: $0.key, stat: $0.value) }
            + momentStats.map { Row(id: "m-" + $0.key, kind: "moment", name: $0.key, stat: $0.value) }
        return rows
            .sorted { ($0.stat.hitches, $0.stat.worstMs) > ($1.stat.hitches, $1.stat.worstMs) }
            .prefix(10)
            .map { $0 }
    }

    /// Plain text for pasting into a message. No tokens, no account or personal data.
    func reportText() -> String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameRateDuration")
        var lines = [
            "TacTech hitch report",
            "Device: \(machine), iOS \(UIDevice.current.systemVersion)",
            "Display max \(UIScreen.main.maximumFramesPerSecond) Hz, expected frame \(String(format: "%.1f", expectedMs)) ms, hitch = frame > \(String(format: "%.1f", expectedMs * 2)) ms",
            "Info.plist CADisableMinimumFrameRateDuration: \(plistKey.map { "\($0)" } ?? "MISSING")",
            "Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off"), thermal state: \(ProcessInfo.processInfo.thermalState.rawValue) (0 nominal … 3 critical)",
            "Frames measured: \(totalFrames), hitches: \(totalHitches)",
            "Top 10 by hitches, then worst frame:"
        ]
        for (index, row) in topRows.enumerated() {
            lines.append("\(index + 1). [\(row.kind)] \(row.name): hitches \(row.stat.hitches), worst \(String(format: "%.0f", row.stat.worstMs)) ms, frames \(row.stat.frames)")
        }
        return lines.joined(separator: "\n")
    }
}

/// PERF-TEMP: the on-screen pill (lives in its own touch-transparent window, so it also shows over sheets).
struct PerfMeterPill: View { // PERF-TEMP
    private let meter = PerfMeter.shared

    var body: some View {
        let color: Color = meter.level == 0 ? .green : (meter.level == 1 ? .yellow : .red)
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text("\(meter.fps) fps · worst \(Int(meter.worstMsLastSecond.rounded())) ms")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            Text("\(meter.currentScreen) · hitches \(meter.totalHitches)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.78), in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
        .allowsHitTesting(false)
    }
}

/// PERF-TEMP: "Hitch report" page of the debug sheet.
struct PerfMeterReportView: View { // PERF-TEMP
    private let meter = PerfMeter.shared
    @State private var copied = false

    var body: some View {
        List {
            Section("Setup") {
                Text("Display max \(UIScreen.main.maximumFramesPerSecond) Hz · hitch = frame over \(String(format: "%.1f", meter.expectedMs * 2)) ms")
                Text("Info.plist CADisableMinimumFrameRateDuration: \(Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameRateDuration").map { "\($0)" } ?? "MISSING")")
                Text("Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON (caps frame rate)" : "off")")
                if !meter.isRunning { Text("Meter is OFF — switch it on in the previous page.").foregroundStyle(.secondary) }
            }
            Section("Top 10 by hitches, then worst frame") {
                let rows = meter.topRows
                if rows.isEmpty { Text("Nothing recorded yet.") }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("[\(row.kind)] \(row.name)").font(.system(size: 14, weight: .semibold))
                        Text("hitches \(row.stat.hitches) · worst \(Int(row.stat.worstMs.rounded())) ms · frames \(row.stat.frames)")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            Section {
                Button(copied ? "Copied" : "Copy as text") {
                    UIPasteboard.general.string = meter.reportText()
                    copied = true
                }
                Button("Reset", role: .destructive) { meter.reset(); copied = false }
            }
        }
        .navigationTitle("Hitch report")
    }
}

/// PERF-TEMP: tells the meter which screen is on top (stack: pushed screens, sheets).
private struct PerfTempScreenModifier: ViewModifier { // PERF-TEMP
    let name: String
    func body(content: Content) -> some View {
        content
            .onAppear { PerfMeter.shared.pushScreen(name) }
            .onDisappear { PerfMeter.shared.popScreen(name) }
    }
}

extension View {
    func perfTempScreen(_ name: String) -> some View { // PERF-TEMP
        modifier(PerfTempScreenModifier(name: name))
    }
}
#else
extension View {
    func perfTempScreen(_ name: String) -> some View { self } // PERF-TEMP
}
#endif

// MARK: - PERF-TEMP centre "+" touch log (DEBUG / -DPERF_TEMP only, default OFF; remove with `git grep PERF-TEMP`)

#if DEBUG || PERF_TEMP
/// PERF-TEMP: tells a LOST tap from a SLOW tap from a tap IGNORED by our own guards. Record only: it never
/// consumes or changes a touch. Touch-downs come from a non-consuming recognizer on the button's window
/// (a `simultaneousGesture` on the button itself would not see touches while the button has hit testing off).
@MainActor @Observable
final class PlusTapProbe { // PERF-TEMP
    static let shared = PlusTapProbe()

    var touchDowns = 0
    var actions = 0
    var ignoredMenuFlag = 0
    var ignoredChatFlag = 0
    var ignoredHitTestOff = 0
    var opens = 0
    var lost = 0
    /// Newest first, at most 20.
    var events: [String] = []

    private struct Pending {
        var downAt: CFTimeInterval
        var resolved = false
        var explained = false
        var heldMs = 0
        var movedPt = 0.0
        var cancelled = false
    }

    @ObservationIgnored weak var anchor: UIView?
    @ObservationIgnored private weak var installedWindow: UIWindow?
    @ObservationIgnored private var recognizer: PlusTouchRecognizer?
    @ObservationIgnored private var menuFlag = false
    @ObservationIgnored private var chatFlag = false
    @ObservationIgnored private var lastCloseAt: CFTimeInterval?
    @ObservationIgnored private var lastCloseKind = ""
    @ObservationIgnored private var pendings: [Int: Pending] = [:]
    @ObservationIgnored private var nextId = 1
    @ObservationIgnored private var lastDownAt: CFTimeInterval?
    @ObservationIgnored private let t0 = CACurrentMediaTime()

    private var on: Bool { PerfTemp.raw(.plusTouchLog) }

    // MARK: Wiring

    /// Installs or removes the recognizer to match the debug-sheet switch.
    func sync() {
        if on, let window = anchor?.window {
            guard installedWindow !== window else { return }
            remove()
            let r = PlusTouchRecognizer()
            r.probe = self
            window.addGestureRecognizer(r)
            recognizer = r
            installedWindow = window
        } else if !on {
            remove()
        }
    }

    private func remove() {
        if let recognizer { installedWindow?.removeGestureRecognizer(recognizer) }
        recognizer = nil
        installedWindow = nil
    }

    func setFlags(menu: Bool, chat: Bool) {
        menuFlag = menu
        chatFlag = chat
    }

    func closed(_ kind: String) {
        lastCloseAt = CACurrentMediaTime()
        lastCloseKind = kind
    }

    // MARK: Events

    /// Touch began anywhere in the window; only touches inside the button's hit area are recorded.
    fileprivate func touchBegan(at point: CGPoint, window: UIWindow) -> Int? {
        guard on, let anchor, anchor.window === window else { return nil }
        let r = anchor.convert(anchor.bounds, to: window)
        guard r.width > 1 else { return nil }
        // Same numbers as the button's hit shape (TTCenterHitShape): +4 left/right, +12 up, +4 down.
        let hit = CGRect(x: r.minX - 4, y: r.minY - 12, width: r.width + 8, height: r.height + 16)
        guard hit.contains(point) else { return nil }

        let now = CACurrentMediaTime()
        let id = nextId
        nextId += 1
        touchDowns += 1
        lastDownAt = now
        var pending = Pending(downAt: now)

        let hitTestOff = menuFlag || chatFlag // = allowsHitTesting(false) on the button
        if hitTestOff {
            ignoredHitTestOff += 1
            pending.explained = true
        }
        pendings[id] = pending

        let sinceClose = lastCloseAt.map { "\(Int((now - $0) * 1000))ms(\(lastCloseKind))" } ?? "none"
        let meter = PerfMeter.shared
        let worst = meter.worstMs(lastSeconds: 0.3, now: now).map { "\(Int($0))ms" } ?? "n/a(meter off)"
        let sinceFrame = meter.msSinceLastFrame(now: now).map { "\(Int($0))ms" } ?? "n/a"
        let scrolling = RunLoop.current.currentMode == .tracking ? "tracking" : "no"
        let dx = Int((point.x - r.midX).rounded()), dy = Int((point.y - r.midY).rounded())
        add("#\(id) DOWN menu=\(menuFlag ? 1 : 0) chat=\(chatFlag ? 1 : 0) hitTestOff=\(hitTestOff ? "YES" : "no") sinceClose=\(sinceClose) scroll=\(scrolling) worst300=\(worst) sinceFrame=\(sinceFrame) loc=(\(dx),\(dy))")
        return id
    }

    fileprivate func touchEnded(id: Int, held: Double, moved: Double, cancelled: Bool) {
        guard on, var p = pendings[id] else { return }
        p.heldMs = Int(held * 1000)
        p.movedPt = moved
        p.cancelled = cancelled
        pendings[id] = p
        print("PERF-TEMP plus: #\(id) UP held=\(p.heldMs)ms moved=\(Int(moved))pt\(cancelled ? " CANCELLED" : "")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated { self?.checkLost(id) }
        }
    }

    private func checkLost(_ id: Int) {
        guard let p = pendings.removeValue(forKey: id) else { return }
        guard !p.resolved, !p.explained else { return }
        lost += 1
        add("#\(id) LOST no action 600ms after touch end (held=\(p.heldMs)ms moved=\(Int(p.movedPt))pt\(p.cancelled ? " cancelled" : ""))")
    }

    /// The Button action ran (called first thing in the action, before the guards).
    func action(menu: Bool, chat: Bool) {
        guard on else { return }
        actions += 1
        var result = "OPEN requested"
        if menu { ignoredMenuFlag += 1; result = "IGNORED menuFlag" }
        else if chat { ignoredChatFlag += 1; result = "IGNORED chatFlag" }
        var tag = "no touch-down seen"
        if let id = pendings.filter({ !$0.value.resolved }).max(by: { $0.key < $1.key })?.key {
            pendings[id]?.resolved = true
            let ms = Int((CACurrentMediaTime() - (pendings[id]?.downAt ?? 0)) * 1000)
            tag = "touch #\(id) +\(ms)ms after down"
        }
        add("ACTION \(result) (\(tag))")
    }

    /// The quick-actions overlay appeared for the first time.
    func opened() {
        guard on else { return }
        opens += 1
        let ms = lastDownAt.map { "\(Int((CACurrentMediaTime() - $0) * 1000))ms" } ?? "n/a"
        add("OPEN overlay appeared \(ms) after last touch-down")
    }

    // MARK: Output

    private func add(_ line: String) {
        let stamp = String(format: "t+%.1fs", CACurrentMediaTime() - t0)
        let full = "\(stamp) \(line)"
        events.insert(full, at: 0)
        if events.count > 20 { events.removeLast(events.count - 20) }
        print("PERF-TEMP plus: \(full)")
    }

    func reset() {
        touchDowns = 0; actions = 0; ignoredMenuFlag = 0; ignoredChatFlag = 0
        ignoredHitTestOff = 0; opens = 0; lost = 0
        events = []
        pendings = [:]
    }

    /// Plain text for pasting. No tokens, no account or personal data.
    func reportText() -> String {
        var lines = [
            "TacTech + button touch log",
            "iOS \(UIDevice.current.systemVersion), FPS meter \(PerfMeter.shared.isRunning ? "ON" : "OFF (frame fields n/a)")",
            "touchDowns \(touchDowns), actions \(actions), ignored_menuFlag \(ignoredMenuFlag), ignored_chatFlag \(ignoredChatFlag), ignored_hitTestOff \(ignoredHitTestOff), opens \(opens), lost \(lost)",
            "Last \(events.count) events (newest first):"
        ]
        lines += events
        return lines.joined(separator: "\n")
    }
}

/// Window-level recognizer: records touch begin/end, never recognizes, never cancels or delays touches.
private final class PlusTouchRecognizer: UIGestureRecognizer {
    weak var probe: PlusTapProbe?
    private var id: Int?
    private var start: CGPoint = .zero
    private var startTime: CFTimeInterval = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let window = view as? UIWindow, id == nil else { state = .failed; return }
        let point = touch.location(in: window)
        let found = MainActor.assumeIsolated { probe?.touchBegan(at: point, window: window) }
        guard let found else { state = .failed; return }
        id = found
        start = point
        startTime = CACurrentMediaTime()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        defer { id = nil; state = .failed }
        guard let id, let touch = touches.first, let window = view as? UIWindow else { return }
        let p = touch.location(in: window)
        let moved = hypot(p.x - start.x, p.y - start.y)
        let held = CACurrentMediaTime() - startTime
        MainActor.assumeIsolated { probe?.touchEnded(id: id, held: held, moved: moved, cancelled: cancelled) }
    }

    override func reset() { id = nil }
}

/// Zero-size, touch-transparent UIView behind the button: gives the probe the button's live window frame.
private struct PlusTapAnchor: UIViewRepresentable {
    final class AnchorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { MainActor.assumeIsolated { PlusTapProbe.shared.sync() } }
        }
    }

    func makeUIView(context: Context) -> UIView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        MainActor.assumeIsolated { PlusTapProbe.shared.anchor = view }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct PerfTempPlusButtonModifier: ViewModifier {
    let menu: Bool
    let chat: Bool

    func body(content: Content) -> some View {
        content
            .background(PlusTapAnchor().allowsHitTesting(false))
            .onAppear { PlusTapProbe.shared.setFlags(menu: menu, chat: chat) }
            .onChange(of: menu) { old, new in
                PlusTapProbe.shared.setFlags(menu: new, chat: chat)
                if old && !new { PlusTapProbe.shared.closed("menu") }
            }
            .onChange(of: chat) { old, new in
                PlusTapProbe.shared.setFlags(menu: menu, chat: new)
                if old && !new { PlusTapProbe.shared.closed("aiChat") }
            }
    }
}

extension View {
    /// PERF-TEMP: put on the centre "+" button. Record only.
    func perfTempPlusButton(menu: Bool, chat: Bool) -> some View {
        modifier(PerfTempPlusButtonModifier(menu: menu, chat: chat))
    }
}

/// PERF-TEMP: switch, counters, last 20 events and Copy, shown inside the debug sheet's Form.
struct PlusTapReportSections: View { // PERF-TEMP
    private let probe = PlusTapProbe.shared

    var body: some View {
        Section("+ button touches") {
            Toggle(PerfTempKey.plusTouchLog.title, isOn: Binding(
                get: { PerfTemp.on(.plusTouchLog) },
                set: { PerfTemp.set(.plusTouchLog, $0) }
            ))
            row("touchDowns", probe.touchDowns)
            row("actions", probe.actions)
            row("ignored_menuFlag", probe.ignoredMenuFlag)
            row("ignored_chatFlag", probe.ignoredChatFlag)
            row("ignored_hitTestOff", probe.ignoredHitTestOff)
            row("opens", probe.opens)
            row("lost", probe.lost)
            Button("Copy counters + last 20 events") { UIPasteboard.general.string = probe.reportText() }
            Button("Reset counters", role: .destructive) { probe.reset() }
        }
        Section("Last 20 events (newest first)") {
            if probe.events.isEmpty {
                Text("No events yet. Switch the log on, close this sheet, tap the + button, reopen it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(probe.events.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 10, design: .monospaced))
            }
        }
    }

    private func row(_ name: String, _ value: Int) -> some View {
        LabeledContent(name, value: "\(value)")
    }
}
#endif


// MARK: - PERF-TEMP bubble menu log (DEBUG / -DPERF_TEMP only; remove with `git grep PERF-TEMP`)

#if DEBUG || PERF_TEMP
/// PERF-TEMP: prints what the bubble menu is doing, so a "no bubbles" report can be pasted. No personal data.
@MainActor
enum PerfBubbleLog { // PERF-TEMP
    static var canvasSize: CGSize = .zero
    static var center: CGPoint = .zero
    static var bodyRuns = 0

    static func line(_ text: String) { print("PERF-TEMP bubbles: \(text)") }

    static func present(driver: Bool, phase: String, reduceMotion: Bool, isPresented: Bool, barButton: CGPoint?) {
        line("present phase=\(phase) driver=\(driver ? "started" : "NOT started") reduceMotion=\(reduceMotion) isPresented=\(isPresented) canvas=\(Int(canvasSize.width))x\(Int(canvasSize.height)) computedCentre=(\(Int(center.x)),\(Int(center.y))) barButtonCentre=\(barButton.map { "(\(Int($0.x)),\(Int($0.y)))" } ?? "none")")
    }

    /// Prints "+100ms / +300ms / +700ms" progress and positions.
    static func scheduleSnapshots(_ snapshot: @escaping () -> String) {
        for ms in [100, 300, 700] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
                line("+\(ms)ms \(snapshot())")
            }
        }
    }

    static var autoOpen: Bool { ProcessInfo.processInfo.arguments.contains("-perfTempOpenBubbles") }
}
#endif


// MARK: - PERF-TEMP bubble menu recorder (DEBUG / -DPERF_TEMP only; remove with `git grep PERF-TEMP`)

#if DEBUG || PERF_TEMP
/// PERF-TEMP: for every open and close of the bubble menu, records frame-to-frame times, tick + draw time per frame
/// and the time from the tap to the first frame that moves. Plain counters only in the frame path (no logging there);
/// one summary line is printed when the motion settles. No personal data.
@MainActor @Observable
final class PerfBubbleRecorder { // PERF-TEMP
    static let shared = PerfBubbleRecorder()

    /// Newest first, at most 12 sessions. Read only by the debug sheet.
    var lines: [String] = []

    @ObservationIgnored private var active = false
    @ObservationIgnored private var kind = ""
    @ObservationIgnored private var commandAt: CFTimeInterval = 0
    @ObservationIgnored private var startMaster = 0.0
    @ObservationIgnored private var moveMs: Double?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var dtMin = Double.infinity
    @ObservationIgnored private var dtMax = 0.0
    @ObservationIgnored private var dtSum = 0.0
    @ObservationIgnored private var dtOver = 0
    @ObservationIgnored private var curFrameMs = 0.0
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var frameSum = 0.0
    @ObservationIgnored private var frameMax = 0.0

    private var expectedMs: Double { 1000.0 / Double(UIScreen.main.maximumFramesPerSecond) }

    static func begin(_ kind: String, master: Double) {
        let r = shared
        if r.active { r.finish(suffix: " (interrupted)") }
        r.active = true
        r.kind = kind
        r.commandAt = CACurrentMediaTime()
        r.startMaster = master
        r.moveMs = nil
        r.lastTimestamp = 0
        r.frames = 0
        r.dtMin = .infinity; r.dtMax = 0; r.dtSum = 0; r.dtOver = 0
        r.curFrameMs = 0; r.frameCount = 0; r.frameSum = 0; r.frameMax = 0
    }

    /// Called once per display-link tick. `timestamp` is the link's frame timestamp; `tickMs` the tick's own cost.
    static func tick(timestamp: CFTimeInterval, tickMs: Double) {
        let r = shared
        guard r.active else { return }
        if r.frames > 0 { r.closeFrame() }
        if r.lastTimestamp > 0 {
            let dt = (timestamp - r.lastTimestamp) * 1000
            r.dtMin = min(r.dtMin, dt); r.dtMax = max(r.dtMax, dt); r.dtSum += dt
            if dt > 1.5 * r.expectedMs { r.dtOver += 1 }
        }
        r.lastTimestamp = timestamp
        r.frames += 1
        r.curFrameMs = tickMs
    }

    static func renderBegan() -> CFTimeInterval { CACurrentMediaTime() }

    /// Called at the end of each Canvas render: adds the draw time to the current frame, notes the first moving frame.
    static func renderEnded(began: CFTimeInterval, master: Double) {
        let r = shared
        guard r.active else { return }
        let now = CACurrentMediaTime()
        r.curFrameMs += (now - began) * 1000
        if r.moveMs == nil, abs(master - r.startMaster) > 0.0005 { r.moveMs = (now - r.commandAt) * 1000 }
    }

    static func end() { shared.finish(suffix: "") }

    private func closeFrame() {
        frameCount += 1
        frameSum += curFrameMs
        frameMax = max(frameMax, curFrameMs)
    }

    private func finish(suffix: String) {
        guard active else { return }
        if frames > 0 { closeFrame() }
        active = false
        let n = max(frames - 1, 1)
        let f = { (v: Double) in String(format: "%.1f", v) }
        let line = "\(kind)\(suffix) frames=\(frames) dt min/avg/max=\(f(dtMin.isFinite ? dtMin : 0))/\(f(dtSum / Double(n)))/\(f(dtMax))ms over1.5x(\(f(1.5 * expectedMs))ms)=\(dtOver) tick+draw avg/max=\(f(frameSum / Double(max(frameCount, 1))))/\(f(frameMax))ms tap->move=\(moveMs.map { f($0) } ?? "n/a")ms"
        lines.insert(line, at: 0)
        if lines.count > 12 { lines.removeLast(lines.count - 12) }
        print("PERF-TEMP bubbles-rec: \(line)")
    }

    func reset() { lines = [] }

    func reportText() -> String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let header = "TacTech bubble menu recorder\n\(machine), iOS \(UIDevice.current.systemVersion), display max \(UIScreen.main.maximumFramesPerSecond) Hz (frame \(String(format: "%.1f", expectedMs)) ms)"
        return ([header] + lines).joined(separator: "\n")
    }
}

/// PERF-TEMP: recorder lines + Copy, shown inside the debug sheet's Form.
struct PerfBubbleRecorderSection: View { // PERF-TEMP
    private let recorder = PerfBubbleRecorder.shared

    var body: some View {
        Section("Bubble menu recorder (last 12 opens / closes)") {
            if recorder.lines.isEmpty {
                Text("Open and close the + menu, then come back here.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(recorder.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 10, design: .monospaced))
            }
            Button("Copy") { UIPasteboard.general.string = recorder.reportText() }
            Button("Reset", role: .destructive) { recorder.reset() }
        }
    }
}
#endif

// MARK: - Loading states (skeletons, empty, error)
// Rules and a how-to live in CLAUDE.md > "Loading states and skeletons". Reference: the published
// "Skeleton loading rules" prototype.

/// The timing rules, in one place. Change them here only.
enum TTLoadTiming {
    /// Nothing is shown for a load shorter than this, so quick loads never flash a skeleton.
    static let showDelay: TimeInterval = 0.2
    /// Once shown, the skeleton stays at least this long, so it never blinks.
    static let minVisible: TimeInterval = 0.4
    /// Skeleton → content crossfade.
    static let crossfade: TimeInterval = 0.2
    /// One full calm opacity pulse for a whole section.
    static let pulsePeriod: TimeInterval = 1.4
    /// Never more placeholder rows than this.
    static let maxPlaceholderRows = 6

    /// Placeholder rows for a list: as many as fit the screen, at most `maxPlaceholderRows`.
    static func placeholderRows(rowHeight: CGFloat, screenHeight: CGFloat = UIScreen.main.bounds.height) -> Int {
        guard rowHeight > 0 else { return 1 }
        return min(maxPlaceholderRows, max(1, Int((screenHeight / rowHeight).rounded(.up))))
    }
}

/// One shared pulse for a whole section (not one per block). Opacity only, so it is GPU-cheap; it stops when the
/// view leaves the screen and is completely off with Reduce Motion (placeholders stay static).
private struct TTSkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || !dimmed ? 1 : 0.55)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: TTLoadTiming.pulsePeriod / 2).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .onDisappear {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dimmed = false }
            }
    }
}

extension Color {
    /// The one neutral fill used for every skeleton shape (adapts to light and dark).
    static var ttSkeletonFill: Color { Color.primary.opacity(0.10) }
    /// Neutral card/background tint for a skeleton surface.
    static var ttSkeletonSurface: Color { Color.primary.opacity(0.04) }
    /// Neutral hairline for a skeleton surface.
    static var ttSkeletonLine: Color { Color.primary.opacity(0.08) }
}

extension View {
    /// Turns a section into a skeleton: the REAL view rendered with placeholder data (so paddings, heights and radii
    /// match the content exactly), redacted, not tappable, hidden from VoiceOver, with one shared calm pulse.
    func ttSkeleton() -> some View {
        self
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .modifier(TTSkeletonPulse())
    }
}

/// Applies the timing rules to one section.
/// - `isLoading`: a request for this section is in flight (or has not started yet).
/// - `hasData`: the store already has data for it. Then the content shows at once and refreshes quietly: no skeleton.
/// While waiting (first `showDelay`) neither skeleton nor content is drawn (the skeleton's space is reserved), so an
/// empty or error state never flashes.
struct TTLoadGate<Skeleton: View, Content: View>: View {
    let isLoading: Bool
    var hasData: Bool = false
    /// Spoken once for the whole section while it loads.
    let loadingLabel: LocalizedStringKey
    @ViewBuilder var skeleton: () -> Skeleton
    @ViewBuilder var content: () -> Content

    @State private var showingSkeleton = false
    @State private var shownAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case waiting, skeleton, content }

    private var phase: Phase {
        if hasData { return .content }
        if showingSkeleton { return .skeleton }
        return isLoading ? .waiting : .content
    }

    var body: some View {
        ZStack {
            switch phase {
            case .waiting:
                // Reserve the skeleton's size without drawing it, so nothing shifts when it appears.
                skeleton().hidden().accessibilityHidden(true)
            case .skeleton:
                skeleton()
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(loadingLabel))
            case .content:
                content()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: TTLoadTiming.crossfade), value: phase)
        // Restart when either input changes (data can disappear while a load is running).
        .task(id: [isLoading, hasData]) {
            if isLoading {
                guard !hasData else { return }
                try? await Task.sleep(for: .seconds(TTLoadTiming.showDelay))
                guard !Task.isCancelled, isLoading else { return }
                shownAt = Date()
                showingSkeleton = true
            } else if showingSkeleton {
                let elapsed = Date().timeIntervalSince(shownAt ?? Date())
                let remaining = max(0, TTLoadTiming.minVisible - elapsed)
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                showingSkeleton = false
                AccessibilityNotification.LayoutChanged().post()
            }
        }
    }
}

/// Empty state: one sentence about what the screen is for, and at most ONE action.
struct TTLoadEmpty: View {
    let icon: SandowIcon
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            TTIcon(icon: icon, size: 28)
                .foregroundStyle(TTColor.inkMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(TTFont.workSans(16, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(TTColor.actionOrange)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Error state: calm text and a Try again button. Use `TTStaleNotice` instead when stale content exists.
struct TTLoadError: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey = "Check your connection and try again."
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            TTIcon(icon: .infoCircle, size: 28)
                .foregroundStyle(TTColor.inkMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(TTFont.workSans(16, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Try again")
                    .font(TTFont.workSans(15, weight: .semibold))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(TTColor.actionOrange)
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Quiet inline notice shown ABOVE stale content that stays visible after a failed refresh.
struct TTStaleNotice: View {
    var message: LocalizedStringKey = "Couldn’t refresh. Showing your last update."
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TTIcon(icon: .infoCircle, filled: true, size: 14)
                .foregroundStyle(TTColor.inkMuted)
                .accessibilityHidden(true)
            Text(message)
                .font(TTFont.caption(13))
                .foregroundStyle(TTColor.inkMuted)
            Spacer(minLength: 8)
            Button(action: retry) {
                Text("Try again")
                    .font(TTFont.workSans(13, weight: .semibold))
                    .foregroundStyle(TTColor.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .background(TTColor.surfaceAlt.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
