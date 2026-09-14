import SwiftUI

// MARK: - Design tokens (Inputs / selection controls)

/// Visual constants for TacTech checkbox & radio — Sandow Inputs sheet.
enum TTSelectionControl {
    static let size: CGFloat = 20
    static let borderWidth: CGFloat = 1.5
    static let checkboxCorner: CGFloat = 6
    static let radioDot: CGFloat = 8
    /// Mandatory gap between indicator and label.
    static let labelSpacing: CGFloat = 8
    static let disabledOpacity: Double = 0.4

    static let accent = Color(hex: 0xFF8A00)
    static let accentSoft = Color(hex: 0xFFEAD9)
    static let checkmark = Color(hex: 0x4A2B00)
    static let borderIdle = Color(white: 0.72)
    static let borderIdleDark = Color.white.opacity(0.55)

    static var stateAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.78)
    }
}

enum TTCheckboxState: Equatable {
    case off
    case on
    case mixed
}

enum TTSelectionSurface {
    /// Standard light canvas (design-sheet colors).
    case standard
    /// Indicator sits on an orange / dark filled card — inverted for contrast.
    case onAccent
}

// MARK: - Checkbox indicator (visual only)

struct TTCheckboxIndicator: View {
    var state: TTCheckboxState
    var surface: TTSelectionSurface = .standard
    var isEnabled: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TTSelectionControl.checkboxCorner, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: TTSelectionControl.checkboxCorner, style: .continuous)
                        .strokeBorder(border, lineWidth: TTSelectionControl.borderWidth)
                }

            if state == .on {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(mark)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if state == .mixed {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(mark)
                    .frame(width: 10, height: 2)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: TTSelectionControl.size, height: TTSelectionControl.size)
        .opacity(isEnabled ? 1 : TTSelectionControl.disabledOpacity)
        .animation(TTSelectionControl.stateAnimation, value: state)
        .accessibilityHidden(true)
    }

    private var isFilled: Bool { state == .on || state == .mixed }

    private var fill: Color {
        guard isFilled else { return .clear }
        switch surface {
        case .standard: return TTSelectionControl.accentSoft
        case .onAccent: return Color.white.opacity(0.92)
        }
    }

    private var border: Color {
        if isFilled {
            switch surface {
            case .standard: return TTSelectionControl.accent
            case .onAccent: return Color.white
            }
        }
        switch surface {
        case .standard: return TTSelectionControl.borderIdle
        case .onAccent: return TTSelectionControl.borderIdleDark
        }
    }

    private var mark: Color {
        switch surface {
        case .standard: return TTSelectionControl.checkmark
        case .onAccent: return TTSelectionControl.accent
        }
    }
}

// MARK: - Checkbox ToggleStyle

/// Drop-in `ToggleStyle` matching the design-system checkbox.
struct TTCheckboxToggleStyle: ToggleStyle {
    var surface: TTSelectionSurface = .standard

    func makeBody(configuration: Configuration) -> some View {
        TTCheckboxToggleBody(
            configuration: configuration,
            surface: surface
        )
    }
}

private struct TTCheckboxToggleBody: View {
    let configuration: ToggleStyleConfiguration
    var surface: TTSelectionSurface
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: TTSelectionControl.labelSpacing) {
                TTCheckboxIndicator(
                    state: configuration.isOn ? .on : .off,
                    surface: surface,
                    isEnabled: isEnabled
                )
                configuration.label
                    .opacity(isEnabled ? 1 : TTSelectionControl.disabledOpacity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

extension ToggleStyle where Self == TTCheckboxToggleStyle {
    static var ttCheckbox: TTCheckboxToggleStyle { TTCheckboxToggleStyle() }
    static func ttCheckbox(surface: TTSelectionSurface) -> TTCheckboxToggleStyle {
        TTCheckboxToggleStyle(surface: surface)
    }
}

/// Labeled checkbox that binds like a `Toggle` without changing call-site logic.
struct TTCheckbox: View {
    @Binding var isOn: Bool
    var surface: TTSelectionSurface = .standard
    var label: Text?

    init(isOn: Binding<Bool>, surface: TTSelectionSurface = .standard, label: Text? = nil) {
        self._isOn = isOn
        self.surface = surface
        self.label = label
    }

    var body: some View {
        if let label {
            Toggle(isOn: $isOn) { label }
                .toggleStyle(.ttCheckbox(surface: surface))
        } else {
            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(.ttCheckbox(surface: surface))
                .labelsHidden()
        }
    }
}

/// Visual checkbox for external selection (parent owns the Button / binding).
struct TTCheckboxMark: View {
    var isOn: Bool
    var isMixed: Bool = false
    var surface: TTSelectionSurface = .standard
    var isEnabled: Bool = true

    var body: some View {
        TTCheckboxIndicator(
            state: isMixed ? .mixed : (isOn ? .on : .off),
            surface: surface,
            isEnabled: isEnabled
        )
    }
}

// MARK: - Radio indicator (visual only)

struct TTRadioIndicator: View {
    var isSelected: Bool
    var surface: TTSelectionSurface = .standard
    var isEnabled: Bool = true

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .overlay {
                    Circle()
                        .strokeBorder(border, lineWidth: TTSelectionControl.borderWidth)
                }

            if isSelected {
                Circle()
                    .fill(dot)
                    .frame(width: TTSelectionControl.radioDot, height: TTSelectionControl.radioDot)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: TTSelectionControl.size, height: TTSelectionControl.size)
        .opacity(isEnabled ? 1 : TTSelectionControl.disabledOpacity)
        .animation(TTSelectionControl.stateAnimation, value: isSelected)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        guard isSelected else { return .clear }
        switch surface {
        case .standard: return TTSelectionControl.accentSoft
        case .onAccent: return Color.white.opacity(0.22)
        }
    }

    private var border: Color {
        if isSelected {
            switch surface {
            case .standard: return TTSelectionControl.accent
            case .onAccent: return Color.white
            }
        }
        switch surface {
        case .standard: return TTSelectionControl.borderIdle
        case .onAccent: return TTSelectionControl.borderIdleDark
        }
    }

    private var dot: Color {
        switch surface {
        case .standard: return TTSelectionControl.accent
        case .onAccent: return Color.white
        }
    }
}

/// Labeled radio row — parent supplies selection / action unchanged.
struct TTRadio: View {
    var title: String
    var isSelected: Bool
    var isEnabled: Bool = true
    var surface: TTSelectionSurface = .standard
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: TTSelectionControl.labelSpacing) {
                TTRadioIndicator(
                    isSelected: isSelected,
                    surface: surface,
                    isEnabled: isEnabled
                )
                Text(title)
                    .opacity(isEnabled ? 1 : TTSelectionControl.disabledOpacity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Selection controls") {
    VStack(alignment: .leading, spacing: 24) {
        Group {
            Text("Checkbox").font(.headline)
            HStack(spacing: 16) {
                TTCheckboxMark(isOn: false)
                TTCheckboxMark(isOn: true)
                TTCheckboxMark(isOn: false, isMixed: true)
                TTCheckboxMark(isOn: true, isEnabled: false)
            }
            Toggle("Remember me", isOn: .constant(true))
                .toggleStyle(.ttCheckbox)
        }

        Group {
            Text("Radio").font(.headline)
            HStack(spacing: 16) {
                TTRadioIndicator(isSelected: false)
                TTRadioIndicator(isSelected: true)
                TTRadioIndicator(isSelected: true, isEnabled: false)
            }
            TTRadio(title: "Trainee", isSelected: true, action: {})
            TTRadio(title: "Trainer", isSelected: false, action: {})
        }
    }
    .padding(24)
}
