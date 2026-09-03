import SwiftUI

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
        case .onDark: TTColor.inkOnDark
        }
    }

    private var background: Color {
        switch style {
        case .onLight: TTColor.surfaceAlt
        case .onDark: TTColor.headerWell
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
            .frame(height: TTSpace.buttonHeight)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TTRadius.lg, style: .continuous)
                    .stroke(border, lineWidth: style == .secondary ? 1 : 0)
            )
        }
        .buttonStyle(TTPressStyle())
        .disabled(isLoading)
    }

    private var foreground: Color {
        switch style {
        case .primary: TTColor.inkOnDark
        case .secondary, .ghost: TTColor.ink
        }
    }

    private var background: Color {
        switch style {
        case .primary: TTColor.accent
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
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
                .tracking(0.6)
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(TTColor.inkMuted)
                        .frame(width: 20)
                }
                Group {
                    if isSecure {
                        SecureField("", text: $text, prompt: Text(title).foregroundStyle(TTColor.inkSubtle))
                    } else {
                        TextField("", text: $text, prompt: Text(title).foregroundStyle(TTColor.inkSubtle))
                    }
                }
                .font(TTFont.body(16))
                .foregroundStyle(TTColor.ink)
            }
            .padding(.horizontal, TTSpace.md)
            .frame(height: TTSpace.fieldHeight)
            .background(TTColor.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: TTRadius.sm, style: .continuous))
        }
    }
}

struct TTAvatar: View {
    let name: String
    var size: CGFloat = 48
    var tint: Color = TTColor.brand

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .semibold))
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
                    .font(.system(size: 15, weight: .semibold))
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
                .font(.system(size: 28, weight: .medium))
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
                .font(.system(size: 11, weight: .semibold))
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
