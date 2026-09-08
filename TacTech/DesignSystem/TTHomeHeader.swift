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

// MARK: - Stable scroll → header collapse (survives header height changes)

/// Shared collapse progress for home dashboards. Updated from UIKit without relying on
/// a GeometryReader inside scroll content (that breaks after the first layout pass).
@MainActor
final class TTHomeScrollCollapseModel: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    private var lastProgress: CGFloat = -1

    func setOffsetY(_ y: CGFloat) {
        let next = TTHomeHeaderCollapse.progress(for: max(0, y))
        // ~80 visual steps — smooth, but skips no-op SwiftUI invalidations.
        let stepped = (next * 80).rounded() / 80
        guard abs(stepped - lastProgress) > 0.0001 else { return }
        lastProgress = stepped
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            progress = stepped
        }
    }
}

extension View {
    /// Attach to the home **ScrollView**. Keeps observing across header shrink/expand.
    func ttObserveHomeScrollCollapse(_ model: TTHomeScrollCollapseModel) -> some View {
        background {
            TTHomeScrollCollapseBridge(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// UIKit bridge that re-binds whenever SwiftUI recreates the underlying UIScrollView.
private struct TTHomeScrollCollapseBridge: UIViewRepresentable {
    let model: TTHomeScrollCollapseModel

    func makeUIView(context: Context) -> TTHomeScrollCollapseHostView {
        let view = TTHomeScrollCollapseHostView()
        view.model = model
        return view
    }

    func updateUIView(_ uiView: TTHomeScrollCollapseHostView, context: Context) {
        uiView.model = model
        uiView.rebindScrollViewIfNeeded()
    }
}

private final class TTHomeScrollCollapseHostView: UIView {
    var model: TTHomeScrollCollapseModel?
    private var observation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: TTHomeScrollDisplayLinkProxy?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        observation?.invalidate()
        displayLink?.invalidate()
        displayLinkProxy = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        rebindScrollViewIfNeeded()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        rebindScrollViewIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebindScrollViewIfNeeded()
    }

    func rebindScrollViewIfNeeded() {
        guard window != nil else { return }
        guard let scroll = findVerticalScrollView() else { return }

        if scroll !== observedScrollView || observation == nil {
            observation?.invalidate()
            observedScrollView = scroll
            observation = scroll.observe(\.contentOffset, options: [.new, .initial]) { [weak self] scrollView, _ in
                self?.publish(from: scrollView)
                self?.syncDisplayLink(with: scrollView)
            }
        }

        publish(from: scroll)
        syncDisplayLink(with: scroll)
    }

    private func publish(from scrollView: UIScrollView) {
        let y = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        if Thread.isMainThread {
            model?.setOffsetY(y)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.model?.setOffsetY(y)
            }
        }
    }

    private func syncDisplayLink(with scrollView: UIScrollView) {
        let tracking = scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking
        if tracking {
            if displayLink == nil {
                let proxy = TTHomeScrollDisplayLinkProxy(owner: self)
                displayLinkProxy = proxy
                let link = CADisplayLink(target: proxy, selector: #selector(TTHomeScrollDisplayLinkProxy.tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        } else if displayLink != nil {
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy = nil
        }
    }

    @objc fileprivate func handleDisplayLink() {
        guard let scrollView = observedScrollView else {
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy = nil
            return
        }
        publish(from: scrollView)
        if !scrollView.isDragging && !scrollView.isDecelerating && !scrollView.isTracking {
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy = nil
        }
    }

    private func findVerticalScrollView() -> UIScrollView? {
        var node: UIView? = self
        var best: UIScrollView?

        while let current = node {
            if let scroll = current as? UIScrollView, isMostlyVertical(scroll) {
                best = scroll
            }

            for subview in current.subviews {
                if let scroll = subview as? UIScrollView, isMostlyVertical(scroll) {
                    // Prefer larger vertical home scroller over tiny horizontal strips.
                    if best == nil || scroll.bounds.height > (best?.bounds.height ?? 0) {
                        best = scroll
                    }
                }
            }

            if let parent = current.superview {
                for sibling in parent.subviews {
                    if let scroll = sibling as? UIScrollView, isMostlyVertical(scroll) {
                        if best == nil || scroll.bounds.height > (best?.bounds.height ?? 0) {
                            best = scroll
                        }
                    }
                    for nested in sibling.subviews where nested is UIScrollView {
                        if let scroll = nested as? UIScrollView, isMostlyVertical(scroll) {
                            if best == nil || scroll.bounds.height > (best?.bounds.height ?? 0) {
                                best = scroll
                            }
                        }
                    }
                }
            }

            node = current.superview
        }

        return best
    }

    private func isMostlyVertical(_ scroll: UIScrollView) -> Bool {
        // Horizontal chips/strips are short; home scroll fills most of the screen.
        if scroll.bounds.height < 80 { return false }
        return scroll.contentSize.height + 20 >= scroll.contentSize.width
            || scroll.contentSize.height > scroll.bounds.height + 40
            || scroll.bounds.height > scroll.bounds.width * 0.55
    }
}

/// Breaks CADisplayLink → view retain cycles.
private final class TTHomeScrollDisplayLinkProxy: NSObject {
    weak var owner: TTHomeScrollCollapseHostView?

    init(owner: TTHomeScrollCollapseHostView) {
        self.owner = owner
    }

    @objc func tick() {
        owner?.handleDisplayLink()
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
