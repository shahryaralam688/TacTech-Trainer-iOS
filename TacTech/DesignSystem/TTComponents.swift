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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TTIcon(icon: .chevronLeft, size: 16)
                .foregroundStyle(foreground)
                .frame(width: Self.size, height: Self.size)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(.horizontal, 20)
        .padding(.top, 10 - 2 * p)
        .padding(.bottom, 16 - 6 * p)
        .background {
            Rectangle()
                .fill(charcoal)
                .ignoresSafeArea(edges: .top)
        }
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.9), value: p)
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

    var body: some View {
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(TTFont.workSans(15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(TTFont.title(22))
                    .foregroundStyle(TTColor.ink)
                Text(title)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                Text(subtitle)
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .ttCard()
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
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
            Image(systemName: "chevron.down")
                .font(TTFont.workSans(11, weight: .semibold))
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
        NavigationStack {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(format(option)).tag(option)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.brand)
                }
            }
        }
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
    /// Settings / detail pages under `TTDarkPageHeader`.
    static let pageTopRadius: CGFloat = TTDarkPageHeader.contentTopRadius
}

extension View {
    /// Canvas sheet with rounded **top** corners. Clips scrolling content to the curve
    /// and adds a soft lift into the dark header so the lip reads as a real surface.
    func ttTopRoundedSheet(radius: CGFloat, fill: Color) -> some View {
        modifier(TTTopRoundedSheetModifier(radius: radius, fill: fill))
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
            .background {
                shape
                    .fill(fill)
                    .ignoresSafeArea(edges: .bottom)
            }
            // Keeps scroll / bounce content inside the top curve.
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
            // Upward contact shadow onto the black/charcoal header.
            .background {
                shape
                    .fill(fill)
                    .shadow(color: Color.black.opacity(0.38), radius: 16, y: -5)
                    .shadow(color: Color.black.opacity(0.16), radius: 3, y: -1)
                    .allowsHitTesting(false)
            }
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
