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

    private var charcoal: Color { TTColor.charcoal }

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

    /// Same eased progress as `TTHomeProfileHeader`, so every dark header shrinks with one feel.
    private var p: CGFloat { TTHomeHeaderCollapse.displayProgress(from: min(1, max(0, collapseProgress))) }
    private var expand: CGFloat { 1 - p }

    /// Natural height of the large title (1–2 lines), measured once so its slot can shrink smoothly.
    @State private var largeTitleHeight: CGFloat = 0

    /// Compact title in the back-button row: fades in from p = 0.35 → 1.
    private var inlineOpacity: Double { Double(min(1, max(0, (p - 0.35) / 0.65))) }
    /// Large title fades out faster than the slot closes.
    private var largeOpacity: Double { Double(max(0, 1 - p * 1.6)) }

    var body: some View {
        Group {
            if showsBack { backLayout } else { plainLayout }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, TTSpace.screen)
        .padding(.top, 10 - 2 * p)
        .padding(.bottom, 16 - 8 * p)
        .background {
            Rectangle()
                .fill(charcoal)
                .ignoresSafeArea(edges: .top)
        }
        // Scroll-driven only — spring here lagged expand on the way back down.
    }

    /// Back button + compact title in one row; the large title sits below and folds away (same pattern as Home's top row).
    private var backLayout: some View {
        VStack(alignment: .leading, spacing: 10 * expand) {
            HStack(alignment: .center, spacing: 12) {
                TTBackButton(style: .onDark) { onBack?() }
                Text(title)
                    .font(TTFont.workSans(18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .opacity(inlineOpacity)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: TTBackButton.size)

            Text(title)
                .font(TTFont.workSans(26, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geo in
                    Color.clear.onAppear { measure(geo.size.height) }
                        .onChange(of: geo.size.height) { _, h in measure(h) }
                })
                .opacity(largeOpacity)
                .accessibilityAddTraits(.isHeader)
                .frame(height: largeTitleHeight > 0 ? largeTitleHeight * expand : (expand < 0.001 ? 0 : nil), alignment: .top)
                .clipped()
        }
    }

    /// No back button: one title that settles in place; ~108pt expanded, ~56pt compact.
    private var plainLayout: some View {
        Text(title)
            .font(TTFont.workSans(26, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .scaleEffect(1 - 0.3 * p, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 56 + 52 * expand, alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }

    private func measure(_ h: CGFloat) {
        if abs(h - largeTitleHeight) > 0.5 { largeTitleHeight = h }
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
    var avatarUrl: String? = nil
    var avatarAsset: String? = nil
    var userId: String? = nil
    @Environment(\.redactionReasons) private var redaction

    var body: some View {
        if redaction.contains(.placeholder) {
            Circle().fill(Color.ttSkeletonFill).frame(width: size, height: size)
        } else if avatarUrl != nil || avatarAsset != nil || userId != nil {
            TTUserAvatarView(
                avatarUrl: avatarUrl,
                avatarAsset: avatarAsset,
                userId: userId,
                name: name,
                size: size,
                shape: .circle,
                initialsForeground: tint,
                initialsBackground: tint.opacity(0.16)
            )
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
            // Canvas fill + upward contact shadow onto the black/charcoal header (single background pass).
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

// MARK: - Meals (shared by Trainee and Trainer)

/// Meal categories the backend accepts in `mealType`.
enum TTMealType: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    /// Default chip by time of day.
    static func suggested(at date: Date = .now) -> TTMealType {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<15: .lunch
        case 15..<18: .snack
        case 18..<23: .dinner
        default: .snack
        }
    }
}

/// Hand-off for "trainer taps a meal notification → that trainee's Progress > Meals".
/// Set before `.ttOpenTraineeMeals` is posted, because the Home tab may not be mounted yet.
@MainActor
enum TTMealDeepLink {
    struct Target: Equatable {
        var traineeId: String
        var mealId: String?
    }
    static var pending: Target?
}

/// Meal photo: remote thumbnail (or full image) with a neutral placeholder when there is no photo.
struct TTMealPhoto: View {
    let urlString: String?
    /// Pixel bucket for the cached thumbnail; ignored when `full` is true.
    var maxPixel: Int = 192
    var full = false

    @State private var image: UIImage?

    /// The server returns `/uploads/...` paths; make them absolute against the API host (one cache key everywhere).
    static func resolvedURL(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: APIConfig.baseURL)?.absoluteURL.absoluteString ?? raw
        }
        return raw
    }

    var body: some View {
        ZStack {
            Color.ttMealPlaceholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                TTIcon(icon: .forkKnife, filled: true, size: full ? 34 : 20)
                    .foregroundStyle(TTColor.actionOrange.opacity(0.7))
            }
        }
        .clipped()
        .task(id: urlString) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard let urlString = Self.resolvedURL(urlString) else { image = nil; return }
        let loaded: UIImage?
        if full {
            loaded = await TTRemoteImageCache.shared.image(for: urlString)
        } else {
            loaded = await TTRemoteImageCache.shared.thumbnail(for: urlString, maxPixel: maxPixel, allowDownload: true)
        }
        if !Task.isCancelled { image = loaded }
    }
}

private extension Color {
    static let ttMealPlaceholder = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255).opacity(0.10)
}

/// The one meal row used by the Trainee day list and the Trainer's Progress > Meals.
/// Pass `onDelete` for the trainee's own list (adds a visible Delete button and a swipe shortcut).
struct TTMealRow: View {
    let meal: Meal
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button { onTap?() } label: {
                HStack(spacing: 12) {
                    TTMealPhoto(urlString: meal.photoUrl)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(meal.name)
                            .font(TTFont.workSans(15, weight: .semibold))
                            .foregroundStyle(TTColor.ink)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let type = TTMealType(rawValue: meal.mealType ?? "") {
                                Text(type.title)
                                    .font(TTFont.workSans(11, weight: .semibold))
                                    .foregroundStyle(Color(red: 194 / 255, green: 65 / 255, blue: 12 / 255))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(TTColor.actionOrange.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            if let detail = meal.detail, !detail.isEmpty {
                                Text(verbatim: "\(detail) · \(meal.eatenAt.formatted(date: .omitted, time: .shortened))")
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(TTColor.inkMuted)
                                    .lineLimit(1)
                            } else {
                                Text(meal.eatenAt.formatted(date: .omitted, time: .shortened))
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(TTColor.inkMuted)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    Group {
                        if meal.macros.calories > 0 {
                            Text("\(meal.macros.calories) kcal")
                        } else {
                            Text("Pending estimate")
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .font(TTFont.workSans(meal.macros.calories > 0 ? 14 : 12, weight: .semibold))
                    .foregroundStyle(meal.macros.calories > 0 ? TTColor.ink : TTColor.inkMuted)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)

            if let onDelete {
                Button(action: onDelete) {
                    TTIcon(icon: .trash1, size: 16)
                        .foregroundStyle(TTColor.inkMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete meal")
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .ttSwipeToDelete(onDelete)
    }

    private var accessibilitySummary: Text {
        var parts: [Text] = [Text(verbatim: meal.name)]
        if let type = TTMealType(rawValue: meal.mealType ?? "") { parts.append(Text(type.title)) }
        parts.append(Text(verbatim: meal.eatenAt.formatted(date: .omitted, time: .shortened)))
        parts.append(meal.macros.calories > 0 ? Text(verbatim: "\(meal.macros.calories) kcal") : Text("Pending estimate"))
        return parts.dropFirst().reduce(parts[0]) { $0 + Text(verbatim: ", ") + $1 }
    }
}

private extension View {
    /// Swipe toward the leading edge to delete (mirrors in RTL). A shortcut only: the row also has a visible Delete button.
    @ViewBuilder
    func ttSwipeToDelete(_ action: (() -> Void)?) -> some View {
        if let action {
            modifier(TTSwipeToDelete(action: action))
        } else {
            self
        }
    }
}

private struct TTSwipeToDelete: ViewModifier {
    let action: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    private var sign: CGFloat { layoutDirection == .rightToLeft ? 1 : -1 }
    private let threshold: CGFloat = 90

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: layoutDirection == .rightToLeft ? .leading : .trailing) {
                if abs(offset) > 4 {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.red.opacity(min(1, abs(offset) / threshold)))
                        .overlay(alignment: layoutDirection == .rightToLeft ? .leading : .trailing) {
                            TTIcon(icon: .trash1, size: 18)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                        }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        let dx = value.translation.width
                        guard abs(dx) > abs(value.translation.height) * 1.5 else { return }
                        // Only toward the delete direction, with a little resistance.
                        offset = dx * sign > 0 ? sign * min(abs(dx), 140) * 0.8 : 0
                    }
                    .onEnded { value in
                        let triggered = abs(offset) >= threshold * 0.8 && value.translation.width * sign > 0
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { offset = 0 }
                        if triggered { action() }
                    }
            )
            .accessibilityAction(named: Text("Delete meal"), action)
    }
}

/// Meal Detail: large photo, type + time, notes, macros and the "Estimate" label. Read-only, for both roles.
struct TTMealDetailSheet: View {
    let meal: Meal
    @Environment(\.dismiss) private var dismiss

    private var typeTitle: LocalizedStringKey? { TTMealType(rawValue: meal.mealType ?? "")?.title }

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: meal.name,
                subtitle: meal.eatenAt.formatted(date: .abbreviated, time: .shortened),
                background: .white
            )
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    TTMealPhoto(urlString: meal.photoUrl, full: true)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)

                    HStack(spacing: 8) {
                        if let typeTitle {
                            chip(Text(typeTitle), tint: TTColor.actionOrange)
                        }
                        if meal.isEstimate {
                            chip(Text("Estimate"), tint: TTColor.inkMuted)
                        }
                        Text("\(Int(meal.portionGrams)) g")
                            .font(TTFont.caption(13))
                            .foregroundStyle(TTColor.inkMuted)
                    }

                    if let notes = meal.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(TTFont.workSans(14, weight: .semibold))
                                .foregroundStyle(TTColor.ink)
                            Text(notes)
                                .font(TTFont.body(15))
                                .foregroundStyle(TTColor.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if meal.macros.calories > 0 {
                        HStack(spacing: 10) {
                            macroTile("Calories", "\(meal.macros.calories)", TTColor.calorie)
                            macroTile("Protein", String(format: "%.0f g", meal.macros.protein), TTColor.protein)
                            macroTile("Carbs", String(format: "%.0f g", meal.macros.carbs), TTColor.carbs)
                            macroTile("Fat", String(format: "%.0f g", meal.macros.fat), TTColor.fat)
                        }
                    } else {
                        Text("Pending estimate")
                            .font(TTFont.workSans(14, weight: .semibold))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                }
                .padding(.horizontal, TTSpace.screen)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .ttHideSystemNavigationBar()
    }

    private func chip(_ text: Text, tint: Color) -> some View {
        text
            .font(TTFont.workSans(12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func macroTile(_ title: LocalizedStringKey, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value)
                .font(TTFont.workSans(15, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Camera picker (moved from the removed FoodScannerView)

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraImagePicker
        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
    }
}
