import SwiftUI

// MARK: - Alert / Notification tokens (Sandow v1.2)

enum TTAlertTone: Equatable {
    case warning
    case success
    case info
    case error
    case accent

    var background: Color {
        switch self {
        case .warning: Color(hex: 0xFFF4E5)
        case .success: Color(hex: 0xEDF7ED)
        case .info: Color(hex: 0xF4F5F7)
        case .error: Color(hex: 0xFDEDEE)
        case .accent: Color(hex: 0xE8F4FD)
        }
    }

    var stroke: Color {
        switch self {
        case .warning: Color(hex: 0xFF8A00)
        case .success: Color(hex: 0x34C759)
        case .info: Color(hex: 0x8E8E93)
        case .error: Color(hex: 0xE11D48)
        case .accent: Color(hex: 0x3B82F6)
        }
    }

    var iconFill: Color { stroke }

    var accessibilityName: String {
        switch self {
        case .warning: "Warning"
        case .success: "Success"
        case .info: "Information"
        case .error: "Error"
        case .accent: "Notice"
        }
    }

    var systemIcon: String {
        switch self {
        case .warning: "exclamationmark"
        case .success: "checkmark"
        case .info: "gearshape.fill"
        case .error: "exclamationmark"
        case .accent: "star.fill"
        }
    }

    /// Maps backend notification `type` → semantic tone (visual only).
    static func forNotificationType(_ type: String) -> TTAlertTone {
        switch type.lowercased() {
        case "chat_call", "call", "incoming_call":
            return .warning
        case "chat", "message":
            return .info
        case "error", "failure", "permission":
            return .error
        case "success", "completed":
            return .success
        case "pro", "subscription", "promo":
            return .accent
        default:
            return .info
        }
    }
}

enum TTAlertMetrics {
    static let corner: CGFloat = 16
    static let borderWidth: CGFloat = 1
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let iconSize: CGFloat = 22
    static let contentSpacing: CGFloat = 10
    static let titleSize: CGFloat = 13
    static let subtitleSize: CGFloat = 11
    static let actionCorner: CGFloat = 12
    static let titleColor = Color(hex: 0x1C1C1E)
    static let subtitleColor = Color(hex: 0x1C1C1E).opacity(0.55)
}

/// Sandow Alerts & Notifications banner — visual shell only.
///
/// Variants:
/// - Standard: icon + title (+ optional subtitle)
/// - Dismissable: + trailing close
/// - Actionable: + trailing dark pill action
struct TTAlertBanner: View {
    var tone: TTAlertTone
    var title: String
    var subtitle: String? = nil
    var onDismiss: (() -> Void)? = nil
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: TTAlertMetrics.contentSpacing) {
            leadingIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TTFont.workSans(TTAlertMetrics.titleSize, weight: .bold))
                    .foregroundStyle(TTAlertMetrics.titleColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TTFont.workSans(TTAlertMetrics.subtitleSize, weight: .regular))
                        .foregroundStyle(TTAlertMetrics.subtitleColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(TTFont.workSans(12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: TTAlertMetrics.actionCorner, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TTAlertMetrics.titleColor.opacity(0.45))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, TTAlertMetrics.horizontalPadding)
        .padding(.vertical, TTAlertMetrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: TTAlertMetrics.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: TTAlertMetrics.corner, style: .continuous)
                .strokeBorder(tone.stroke.opacity(0.55), lineWidth: TTAlertMetrics.borderWidth)
        }
        .accessibilityElement(children: .combine)
    }

    private var leadingIcon: some View {
        ZStack {
            Circle()
                .fill(tone.iconFill)
            Image(systemName: tone.systemIcon)
                .font(.system(size: tone == .accent || tone == .info ? 10 : 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: TTAlertMetrics.iconSize, height: TTAlertMetrics.iconSize)
        .accessibilityHidden(true)
    }
}

#Preview("Alert banners") {
    ScrollView {
        VStack(spacing: 12) {
            TTAlertBanner(tone: .warning, title: "Fitness schedule updated.")
            TTAlertBanner(tone: .success, title: "Nutrition list updated.", onDismiss: {})
            TTAlertBanner(
                tone: .info,
                title: "Chatbot Settings Updated.",
                actionTitle: "Learn More",
                onAction: {}
            )
            TTAlertBanner(
                tone: .error,
                title: "You don't have permission.",
                subtitle: "Please contact admin.",
                onDismiss: {}
            )
            TTAlertBanner(
                tone: .accent,
                title: "Subscribed to pro!",
                subtitle: "Let's get ripped!",
                actionTitle: "Learn More",
                onAction: {}
            )
        }
        .padding()
    }
}
