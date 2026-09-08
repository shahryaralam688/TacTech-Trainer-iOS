import SwiftUI
import UIKit

/// Status chip under the home greeting (e.g. "88% Healthy", "Pro").
struct TTHomeProfileMetric: Identifiable, Hashable {
    let id: String
    let icon: SandowIcon
    let iconColor: Color
    let text: String

    init(id: String = UUID().uuidString, icon: SandowIcon, iconColor: Color, text: String) {
        self.id = id
        self.icon = icon
        self.iconColor = iconColor
        self.text = text
    }
}

/// How far home must scroll before the header is fully compact.
enum TTHomeHeaderCollapse {
    /// Slightly longer travel so the shrink feels paced, not abrupt.
    static let distance: CGFloat = 110

    /// Smoothstep 0…1 so layout eases in/out with the finger.
    static func progress(for offset: CGFloat) -> CGFloat {
        let raw = min(1, max(0, offset / distance))
        return raw * raw * (3 - 2 * raw)
    }
}

/// Home top bar — scroll-synced collapse to avatar + name + forward.
struct TTHomeProfileHeader: View {
    let name: String
    var avatarSymbol: String? = nil
    var avatarUserId: String? = nil
    var avatarInitial: String? = nil
    var badgeCount: Int = 0
    var metrics: [TTHomeProfileMetric] = []
    var date: Date = .now
    /// 0 = expanded. 1 = compact (avatar + name + chevron).
    var collapseProgress: CGFloat = 0
    var onProfileTap: (() -> Void)? = nil
    var onNotificationTap: (() -> Void)? = nil

    private let orange = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    private let dateGrey = Color.white.opacity(0.55)
    private let bellBG = Color(white: 0.22)

    private var p: CGFloat { min(1, max(0, collapseProgress)) }
    private var expand: CGFloat { 1 - p }

    private var avatarSide: CGFloat { 58 - 18 * p } // 58 → 40
    private var avatarRadius: CGFloat { 16 - 4 * p } // 16 → 12
    private var titleSize: CGFloat { 28 - 8 * p } // 28 → 20
    private var rowSpacing: CGFloat { 14 - 2 * p }

    var body: some View {
        VStack(alignment: .leading, spacing: 22 * expand) {
            topRow
                .opacity(Double(expand))
                .frame(height: 44 * expand, alignment: .top)
                .clipped()
                .allowsHitTesting(p < 0.35)

            profileRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 10 - 2 * p)
        .padding(.bottom, 22 - 10 * p)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color.black
                TTHomeHeaderBands()
                    .fill(Color.white.opacity(0.07 * Double(expand)))
            }
            .ignoresSafeArea(edges: .top)
        }
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }

    // MARK: - Rows

    private var topRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                TTIcon(icon: .calendar1, size: 14)
                Text(formattedDate)
                    .font(TTFont.textSM(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(dateGrey)

            Spacer()

            Button {
                if let onNotificationTap {
                    onNotificationTap()
                } else {
                    onProfileTap?()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    TTIcon(icon: .bell1, size: 18)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(bellBG)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if badgeCount > 0 {
                        Text("\(min(badgeCount, 9))")
                            .font(TTFont.text2XS(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(orange)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(TTHomeHeaderPressStyle())
        }
    }

    private var profileRow: some View {
        Button {
            onProfileTap?()
        } label: {
            HStack(spacing: rowSpacing) {
                avatarView(side: avatarSide, corner: avatarRadius)

                VStack(alignment: .leading, spacing: 7 * expand) {
                    Text(p < 0.55 ? "Hello, \(name)!" : name)
                        .font(TTFont.workSans(titleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if !metrics.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                                if index > 0 {
                                    Circle()
                                        .fill(Color.white.opacity(0.45))
                                        .frame(width: 3, height: 3)
                                        .padding(.horizontal, 2)
                                }
                                HStack(spacing: 5) {
                                    TTIcon(icon: metric.icon, size: 12)
                                        .foregroundStyle(metric.iconColor)
                                    Text(metric.text)
                                        .font(TTFont.textMD(.medium))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .opacity(Double(expand))
                        .frame(height: 22 * expand, alignment: .top)
                        .clipped()
                    }
                }

                Spacer(minLength: 0)

                TTIcon(icon: .chevronRight, size: 22 - 2 * p)
                    .foregroundStyle(.white)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TTHomeHeaderPressStyle())
        .accessibilityLabel("Open profile, \(name)")
        .accessibilityHint("Opens your profile")
    }

    private func avatarView(side: CGFloat, corner: CGFloat) -> some View {
        Group {
            if TTAvatarCatalog.isCustom(avatarSymbol),
               let custom = TTAvatarCatalog.loadCustomImage(for: avatarUserId) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if let avatarSymbol, TTAvatarCatalog.isAssetName(avatarSymbol) {
                Image(avatarSymbol)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    if let avatarSymbol, !TTAvatarCatalog.hasRenderableAvatar(avatarSymbol) {
                        Image(systemName: avatarSymbol)
                            .font(TTFont.workSans(side * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    } else {
                        Text((avatarInitial ?? String(name.prefix(1))).uppercased())
                            .font(TTFont.workSans(side * 0.36, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
        )
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

/// Subtle diagonal ribbon texture for the home header card.
struct TTHomeHeaderBands: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -40, y: 20))
        path.addQuadCurve(to: CGPoint(x: 120, y: -10), control: CGPoint(x: 40, y: -30))
        path.addQuadCurve(to: CGPoint(x: -20, y: 90), control: CGPoint(x: 70, y: 40))
        path.closeSubpath()

        path.move(to: CGPoint(x: -30, y: 50))
        path.addQuadCurve(to: CGPoint(x: 90, y: 10), control: CGPoint(x: 30, y: 0))
        path.addQuadCurve(to: CGPoint(x: -10, y: 110), control: CGPoint(x: 50, y: 55))
        path.closeSubpath()

        path.move(to: CGPoint(x: rect.maxX + 30, y: rect.maxY - 10))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 130, y: rect.maxY + 20),
            control: CGPoint(x: rect.maxX - 40, y: rect.maxY + 40)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + 10, y: rect.maxY - 80),
            control: CGPoint(x: rect.maxX - 60, y: rect.maxY - 30)
        )
        path.closeSubpath()
        return path
    }
}

/// Press feedback without the default disabled/dull fade.
private struct TTHomeHeaderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - Reliable scroll offset (UIKit) → header collapse

/// Embed as the **first** child inside the home ScrollView content.
struct TTHomeScrollOffsetAnchor: View {
    @Binding var offset: CGFloat

    var body: some View {
        TTHomeScrollOffsetObserver(offset: $offset)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Finds the parent vertical UIScrollView and mirrors `contentOffset.y`.
private struct TTHomeScrollOffsetObserver: UIViewRepresentable {
    @Binding var offset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(from: uiView)
    }

    final class Coordinator {
        private var offset: Binding<CGFloat>
        private var observation: NSKeyValueObservation?
        private weak var scrollView: UIScrollView?

        init(offset: Binding<CGFloat>) {
            self.offset = offset
        }

        deinit {
            observation?.invalidate()
        }

        func attach(from view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let scroll = Self.findVerticalScrollView(from: view) else { return }
                if scroll === self.scrollView { return }

                self.observation?.invalidate()
                self.scrollView = scroll
                self.observation = scroll.observe(\.contentOffset, options: [.new, .initial]) { [weak self] scrollView, _ in
                    guard let self else { return }
                    let y = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        self.offset.wrappedValue = y
                    }
                }
            }
        }

        private static func findVerticalScrollView(from view: UIView) -> UIScrollView? {
            var current: UIView? = view.superview
            var candidate: UIScrollView?
            while let node = current {
                if let scroll = node as? UIScrollView {
                    // Prefer the tallest vertical scroller (home page), skip narrow horizontal strips.
                    let mostlyVertical = scroll.contentSize.height >= scroll.contentSize.width
                        || scroll.contentSize.height > scroll.bounds.height + 40
                    if mostlyVertical {
                        candidate = scroll
                    } else if candidate == nil {
                        candidate = scroll
                    }
                }
                current = node.superview
            }
            return candidate
        }
    }
}

#Preview("Home Header") {
    VStack(spacing: 24) {
        TTHomeProfileHeader(
            name: "Maya",
            badgeCount: 2,
            metrics: [
                TTHomeProfileMetric(id: "h", icon: .plus, iconColor: TTColor.actionOrange, text: "86% Healthy"),
                TTHomeProfileMetric(id: "p", icon: .starFull, iconColor: .blue, text: "Pro")
            ],
            onProfileTap: {}
        )
        TTHomeProfileHeader(
            name: "Maya",
            avatarSymbol: nil,
            collapseProgress: 1,
            onProfileTap: {}
        )
    }
    .background(Color.black)
}
