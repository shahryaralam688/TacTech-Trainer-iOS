import SwiftUI

/// Confirmed AI Coach Pro subscriber chip — distinct from Boost / Verified.
struct AIProBadge: View {
    enum Style {
        /// Compact “Pro” for headers / name rows.
        case compact
        /// Uses `badgeFullLabel` or “AI Coach Pro”.
        case full
    }

    var style: Style = .compact
    var label: String? = nil
    var fullLabel: String? = nil

    private var text: String {
        switch style {
        case .compact:
            let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
            return "Pro"
        case .full:
            let trimmed = fullLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
            return "AI Coach Pro"
        }
    }

    var body: some View {
        Text(text)
            .font(TTFont.caption(style == .full ? 11 : 10))
            .fontWeight(.bold)
            .foregroundStyle(TTColor.ink)
            .padding(.horizontal, style == .full ? 10 : 8)
            .padding(.vertical, style == .full ? 4 : 3)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: 0xFDBA74).opacity(0.95),
                        Color(hex: 0xFB923C).opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
            .accessibilityLabel("AI Coach Pro subscriber")
    }
}

/// Convenience: only renders when `active`.
struct AIProBadgeIfActive: View {
    var entitlement: MeAIResponse?
    var style: AIProBadge.Style = .compact

    var body: some View {
        if let entitlement, entitlement.active {
            AIProBadge(
                style: style,
                label: entitlement.resolvedBadgeLabel,
                fullLabel: entitlement.resolvedFullLabel
            )
        }
    }
}

#Preview("AI Pro Badge") {
    VStack(spacing: 12) {
        AIProBadge(style: .compact)
        AIProBadge(style: .full)
    }
    .padding()
}
