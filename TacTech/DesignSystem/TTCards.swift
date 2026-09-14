import SwiftUI

// MARK: - Cards & Lists 1 (TACTECH / Sandow)

/// Visual tokens from the Cards & Lists design sheet + 8pt grid.
enum TTCardTokens {
    static let corner: CGFloat = 20
    static let listCorner: CGFloat = 16
    static let thumbCorner: CGFloat = 12
    static let thumbSize: CGFloat = 48
    static let actionCorner: CGFloat = 12
    static let actionSize: CGFloat = 40
    static let padding: CGFloat = 12
    static let itemSpacing: CGFloat = 16
    static let listSpacing: CGFloat = 12
    static let badgeHorizontalPadding: CGFloat = 10

    static let accent = Color(hex: 0xFF8A00)
    static let listFillLight = Color(hex: 0xF9F9FB)
    static let listFillDark = Color(hex: 0x2C2C2E)
    static let mediaFillLight = Color.white
    static let mediaFillDark = Color(hex: 0x1C1C1E)
    static let metricBlock = Color(hex: 0x1C1C1E)
    static let titleSize: CGFloat = 14
    static let subtitleSize: CGFloat = 12

    static func listFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? listFillDark : listFillLight
    }

    static func mediaFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? mediaFillDark : mediaFillLight
    }
}

// MARK: - Shared pieces

struct TTCardBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(TTFont.workSans(11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, TTCardTokens.badgeHorizontalPadding)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.92))
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
    }
}

struct TTCardActionButton: View {
    var systemImage: String = "play.fill"

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: TTCardTokens.actionSize, height: TTCardTokens.actionSize)
            .background(TTCardTokens.accent)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.actionCorner, style: .continuous))
            .shadow(color: TTCardTokens.accent.opacity(0.30), radius: 6, x: 0, y: 3)
    }
}

// MARK: - 1. Media / Grid Activity Card

/// Continuous rounded media card with top-leading badge and bottom-trailing orange action.
struct TTMediaActivityCard<Media: View, Footer: View>: View {
    var badge: String?
    var actionSystemImage: String = "play.fill"
    var showsAction: Bool = true
    @ViewBuilder var media: () -> Media
    @ViewBuilder var footer: () -> Footer

    @Environment(\.colorScheme) private var colorScheme

    init(
        badge: String? = nil,
        actionSystemImage: String = "play.fill",
        showsAction: Bool = true,
        @ViewBuilder media: @escaping () -> Media,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.badge = badge
        self.actionSystemImage = actionSystemImage
        self.showsAction = showsAction
        self.media = media
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                media()
                    .frame(maxWidth: .infinity)
                    .clipped()

                if let badge, !badge.isEmpty {
                    TTCardBadge(text: badge)
                        .padding(TTCardTokens.padding)
                }

                if showsAction {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            TTCardActionButton(systemImage: actionSystemImage)
                                .padding(TTCardTokens.padding)
                        }
                    }
                }
            }

            footer()
                .padding(TTCardTokens.padding)
        }
        .background(TTCardTokens.mediaFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }
}

extension TTMediaActivityCard where Footer == EmptyView {
    init(
        badge: String? = nil,
        actionSystemImage: String = "play.fill",
        showsAction: Bool = true,
        @ViewBuilder media: @escaping () -> Media
    ) {
        self.init(
            badge: badge,
            actionSystemImage: actionSystemImage,
            showsAction: showsAction,
            media: media,
            footer: { EmptyView() }
        )
    }
}

// MARK: - 2. Horizontal List Tile

/// Soft-fill list row: 48×48 thumb + title/subtitle stack.
struct TTListTile<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: TTCardTokens.listSpacing) {
            leading()
                .frame(width: TTCardTokens.thumbSize, height: TTCardTokens.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.thumbCorner, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TTFont.workSans(TTCardTokens.titleSize, weight: .bold))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .medium))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(TTCardTokens.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTCardTokens.listFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.listCorner, style: .continuous))
    }
}

extension TTListTile where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.init(title: title, subtitle: subtitle, leading: leading, trailing: { EmptyView() })
    }
}

/// Convenience thumb from asset or system icon.
struct TTListTileThumb: View {
    var assetName: String? = nil
    var systemImage: String? = nil
    var tint: Color = TTCardTokens.accent

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if let systemImage {
                ZStack {
                    tint.opacity(0.14)
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
            } else {
                TTCardTokens.listFillLight
            }
        }
        .frame(width: TTCardTokens.thumbSize, height: TTCardTokens.thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.thumbCorner, style: .continuous))
    }
}

// MARK: - 3. Metric / Stat Split Card

/// Upper circular media + lower high-contrast metric block.
struct TTMetricSplitCard: View {
    var title: String
    var metadata: String?
    var systemImage: String? = nil
    var assetName: String? = nil
    var avatar: AnyView? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(white: 0.96)
                if let avatar {
                    avatar
                } else if let assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(TTCardTokens.accent)
                }
            }
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TTFont.workSans(TTCardTokens.titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let metadata, !metadata.isEmpty {
                    Text(metadata)
                        .font(TTFont.workSans(TTCardTokens.subtitleSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TTCardTokens.padding)
            .background(TTCardTokens.metricBlock)
        }
        .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }
}

// MARK: - Surface helper

extension View {
    /// Cards & Lists continuous surface (20pt / 12pt padding).
    func ttContentCard(padding: CGFloat = TTCardTokens.padding) -> some View {
        self
            .padding(padding)
            .background(TTCardTokens.mediaFillLight)
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.corner, style: .continuous))
    }

    func ttListSurface() -> some View {
        modifier(TTListSurfaceModifier())
    }
}

private struct TTListSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(TTCardTokens.padding)
            .background(TTCardTokens.listFill(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: TTCardTokens.listCorner, style: .continuous))
    }
}

#Preview("Cards & Lists") {
    ScrollView {
        VStack(spacing: TTCardTokens.itemSpacing) {
            TTMediaActivityCard(badge: "15-20 Min", actionSystemImage: "play.fill") {
                Image("OnboardingWorkouts")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
            } footer: {
                Text("Push Day")
                    .font(TTFont.workSans(14, weight: .bold))
            }

            TTListTile(
                title: "Grilled Chicken Bowl",
                subtitle: "420 kcal · 15 min"
            ) {
                TTListTileThumb(assetName: "OnboardingNutrition")
            }

            TTMetricSplitCard(title: "Hydration", metadata: "1.8 L today", systemImage: "drop.fill")
                .frame(width: 160)
        }
        .padding(TTSpace.screen)
    }
    .background(Color(white: 0.96))
}
