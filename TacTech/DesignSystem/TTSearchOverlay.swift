import SwiftUI

// MARK: - Morph state (refined search only)

private struct TTSearchMorphedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct TTSearchFrameBoxKey: EnvironmentKey {
    static let defaultValue: TTSearchFrameBox? = nil
}

private struct TTSearchRowFadedKey: EnvironmentKey {
    static let defaultValue = false
}

/// Timing of the refined search when it opens from the pinned controls row's search icon (all named, in one place).
enum TTSearchMotion {
    /// Open: the field grows out of the icon, the row fades, the panel rises, the dim fades in: one decelerating curve.
    static let openDuration: Double = 0.25
    /// Close: faster than open, back into the icon.
    static let closeDuration: Double = 0.18
    /// Reduce Motion: a short cross-fade only.
    static let reduceMotionDuration: Double = 0.15
    /// The row's other controls (Newest, levels, Select) fade out faster than the field grows, so they are gone
    /// before "Cancel" arrives at the same end of the row.
    static var rowFadeDuration: Double { openDuration * 0.6 }
    /// The suggestions panel rises this far into place.
    static let panelRise: CGFloat = 12
    /// The row's other controls slide this far while they fade.
    static let rowSlide: CGFloat = 8
    /// The width of the search icon the field grows out of.
    static let iconWidth: CGFloat = 44

    static var open: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: openDuration) } // decelerating, no bounce
    static var close: Animation { .timingCurve(0.4, 0, 0.2, 1, duration: closeDuration) }
    /// "Cancel" fades in a little after the field starts to grow.
    static var cancelIn: Animation { .easeOut(duration: 0.15).delay(0.08) }
}

extension EnvironmentValues {
    /// `true` while the refined search is open: the entry pill hides (the open bar sits exactly on it).
    fileprivate var ttSearchMorphed: Bool {
        get { self[TTSearchMorphedKey.self] }
        set { self[TTSearchMorphedKey.self] = newValue }
    }

    fileprivate var ttSearchFrameBox: TTSearchFrameBox? {
        get { self[TTSearchFrameBoxKey.self] }
        set { self[TTSearchFrameBoxKey.self] = newValue }
    }

    /// `true` while search is open from the row: the row's other controls (Newest, levels, Select) are faded out.
    fileprivate var ttSearchRowFaded: Bool {
        get { self[TTSearchRowFadedKey.self] }
        set { self[TTSearchRowFadedKey.self] = newValue }
    }
}

/// Reads the entry pill's on-screen frame once, on demand (no per-frame geometry tracking).
final class TTSearchFrameBox {
    fileprivate weak var view: UIView?
    /// The pinned controls row (set by `.ttSearchRowAnchor()`).
    fileprivate weak var rowView: UIView?
    /// Set by the row's search icon just before it opens search: the field then grows out of the icon, in the row,
    /// instead of out of the entry pill (so the list never has to scroll back to the pill first).
    fileprivate var opensFromRow = false

    func globalFrame() -> CGRect? {
        Self.frame(of: view)
    }

    fileprivate func rowFrame() -> CGRect? {
        Self.frame(of: rowView)
    }

    private static func frame(of view: UIView?) -> CGRect? {
        guard let view, view.window != nil else { return nil }
        let rect = view.convert(view.bounds, to: nil)
        return rect.isEmpty ? nil : rect
    }
}

private struct TTSearchFrameProbe: UIViewRepresentable {
    let box: TTSearchFrameBox

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        box.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        box.view = uiView
    }
}

private struct TTSearchRowProbe: UIViewRepresentable {
    let box: TTSearchFrameBox

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        box.rowView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        box.rowView = uiView
    }
}

// MARK: - Pinned controls row (morph source when the pill has scrolled away)

private struct TTSearchRowAnchorModifier: ViewModifier {
    @Environment(\.ttSearchFrameBox) private var frameBox

    func body(content: Content) -> some View {
        content.background {
            if let frameBox { TTSearchRowProbe(box: frameBox) }
        }
    }
}

private struct TTSearchRowFadeModifier: ViewModifier {
    @Environment(\.ttSearchRowFaded) private var faded
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        let slide = layoutDirection == .rightToLeft ? -TTSearchMotion.rowSlide : TTSearchMotion.rowSlide
        content
            // Animated by the host's withAnimation: opacity (and a slight slide) only, nothing is re-laid out.
            .opacity(faded ? 0 : 1)
            .offset(x: faded && !reduceMotion ? slide : 0)
            .allowsHitTesting(!faded)
            .accessibilityHidden(faded)
    }
}

extension View {
    /// Put on the pinned controls row (the row that holds the search icon): its frame is where the field grows from.
    func ttSearchRowAnchor() -> some View { modifier(TTSearchRowAnchorModifier()) }

    /// Put on each of the row's OTHER controls: they fade out (with a slight slide) while search is open.
    func ttSearchRowFade() -> some View { modifier(TTSearchRowFadeModifier()) }
}

/// The row's search icon (44 x 44). Opens search from the row: no scrolling, no header or list change.
struct TTSearchRowButton: View {
    let accessibilityLabel: LocalizedStringKey
    let onOpen: () -> Void

    @Environment(\.ttSearchFrameBox) private var frameBox
    @Environment(\.ttSearchMorphed) private var searchOpen
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        Button {
            frameBox?.opensFromRow = true
            onOpen()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TTColor.ink)
                .frame(width: TTSearchMotion.iconWidth, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityFocused($focused)
        // Search closed: VoiceOver focus returns to the icon.
        .onChange(of: searchOpen) { old, new in
            if old, !new, UIAccessibility.isVoiceOverRunning { focused = true }
        }
    }
}

// MARK: - Entry pill (morph source)

struct TTSearchEntryPill: View {
    let placeholder: String
    var query: String = ""
    var style: Style = .light
    var namespace: Namespace.ID
    var matchedID: String = "ttSearchMorph"
    var onTap: () -> Void

    @Environment(\.ttSearchMorphed) private var morphed
    @Environment(\.ttSearchFrameBox) private var frameBox

    enum Style {
        case light, onDark
    }

    var body: some View {
        // While the refined search is open, the open bar sits exactly on this pill, so it hides but
        // keeps its layout slot (and its frame, which the host reads once when opening).
        pillButton
            .background {
                if let frameBox { TTSearchFrameProbe(box: frameBox) }
            }
            .opacity(morphed ? 0 : 1)
            .allowsHitTesting(!morphed)
            .accessibilityHidden(morphed)
    }

    private var pillButton: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                TTIcon(icon: .magnifyingGlass, size: 16)
                    .foregroundStyle(iconColor)
                Text(query.isEmpty ? placeholder : query)
                    .font(TTFont.body(15))
                    .foregroundStyle(query.isEmpty ? placeholderColor : textColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .matchedGeometryEffect(id: matchedID, in: namespace)
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.99))
        .accessibilityLabel(placeholder)
        .accessibilityHint("Opens search")
    }

    private var background: Color {
        switch style {
        case .light: Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
        case .onDark: Color.white.opacity(0.12)
        }
    }

    private var iconColor: Color {
        switch style {
        case .light: TTColor.inkMuted
        case .onDark: Color.white.opacity(0.55)
        }
    }

    private var placeholderColor: Color {
        switch style {
        case .light: TTColor.inkMuted
        case .onDark: Color.white.opacity(0.45)
        }
    }

    private var textColor: Color {
        switch style {
        case .light: TTColor.ink
        case .onDark: .white
        }
    }
}

// MARK: - Full search overlay

struct TTSearchOverlay: View {
    let catalog: TTSearchCatalog
    var namespace: Namespace.ID
    var matchedID: String = "ttSearchMorph"
    var onOutcome: (TTSearchOutcome) -> Void
    /// Refined mode (Plans): the bar expands in place, the options panel unfolds below it.
    var refined: Bool = false
    /// Where the entry pill sits on screen (global coordinates) when the search opens.
    /// When `anchorIsRow` it is the pinned controls row instead.
    var barFrame: CGRect = .zero
    /// The field grows out of the row's search icon (see `TTSearchMotion`).
    var anchorIsRow: Bool = false
    /// Called when closing starts (the row's controls fade back in together with the field folding).
    var onWillClose: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @State private var isClosing = false
    @State private var barNarrow = false
    @State private var showCancel = false
    @State private var panelOpen = false
    @State private var keyboardTop: CGFloat?
    /// Reduce Motion + row: the field cross-fades instead of growing.
    @State private var barShown = false
    /// Row mode: the field itself is only visible while it is wider than the icon (fades in fast, out at the very end).
    @State private var barVisible = false
    @AccessibilityFocusState private var fieldA11yFocus: Bool

    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var topTab: TTSearchTopTab = .items
    @State private var step: TTSearchAccordionStep = .what
    @State private var isFocusedPhase = false
    @State private var selectedCategoryId: String?
    @State private var recents: [String] = []

    @State private var showBackdrop = false
    @State private var showContent = false
    @State private var showChrome = false

    private let cardRadius: CGFloat = 26
    private let cardFill = Color.white
    private let canvas = Color(white: 0.97)

    init(
        catalog: TTSearchCatalog,
        namespace: Namespace.ID,
        matchedID: String = "ttSearchMorph",
        refined: Bool = false,
        barFrame: CGRect = .zero,
        anchorIsRow: Bool = false,
        onWillClose: (() -> Void)? = nil,
        onOutcome: @escaping (TTSearchOutcome) -> Void
    ) {
        self.catalog = catalog
        self.namespace = namespace
        self.matchedID = matchedID
        self.refined = refined
        self.barFrame = barFrame
        self.anchorIsRow = anchorIsRow
        self.onWillClose = onWillClose
        self.onOutcome = onOutcome
    }

    @ViewBuilder
    var body: some View {
        if refined {
            refinedBody
        } else {
            classicBody
        }
    }

    private var classicBody: some View {
        GeometryReader { geo in
            let topInset = max(geo.safeAreaInsets.top, 54)

            ZStack(alignment: .top) {
                // Edge-to-edge scrim only — chrome stays below the status bar.
                backdrop
                    .opacity(showBackdrop ? 1 : 0)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    chrome
                        .opacity(showChrome ? 1 : 0)
                        .offset(y: showChrome ? 0 : -12)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            accordion
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, isFocusedPhase ? 24 : 100)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 18)
                    .scaleEffect(showContent ? 1 : 0.97, anchor: .top)
                }
                .padding(.top, topInset + 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if !isFocusedPhase {
                    footer
                        .opacity(showContent ? 1 : 0)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: present)
        .onDisappear { debounceTask?.cancel() }
        .onChange(of: query) { _, newValue in
            scheduleDebounce(newValue)
            if !newValue.isEmpty { enterFocusedPhase(focusField: false) }
        }
        .onChange(of: fieldFocused) { _, focused in
            if focused { enterFocusedPhase(focusField: false) }
        }
    }

    // MARK: Refined layout (Plans): bar expands in place, panel unfolds under it

    private static let cancelWidth: CGFloat = 76
    private static let barGap: CGFloat = 8

    private var refinedBody: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            // Standard bar height (same as the list's search pill). The measured frame only decides where
            // the bar sits; a collapsed measurement must never make the bar thin.
            let standardHeight: CGFloat = 48
            let bar = CGRect(
                x: barFrame.minX - origin.x,
                y: barFrame.midY - origin.y - standardHeight / 2,
                width: barFrame.width,
                height: standardHeight
            )
            // Panel ends just above the keyboard (estimated until the keyboard reports its frame).
            let kbTop = (keyboardTop ?? (UIScreen.main.bounds.height - 336)) - origin.y
            let panelTop = bar.maxY + Self.barGap
            let panelFull = max(140, kbTop - Self.barGap - panelTop)
            // From the row: the field starts as wide as the icon and grows to the Cancel position (leading edge fixed).
            let barWidth: CGFloat = anchorIsRow
                ? (reduceMotion ? bar.width : (barNarrow ? bar.width - Self.cancelWidth : TTSearchMotion.iconWidth))
                : ((barNarrow && !reduceMotion) ? bar.width - Self.cancelWidth : bar.width)

            ZStack(alignment: .topLeading) {
                if anchorIsRow {
                    // Flat dim from the row down (no blur). The header above stays visible and undimmed.
                    Color.black.opacity(0.35)
                        .opacity(showBackdrop ? 1 : 0)
                        .frame(height: max(0, geo.size.height - (barFrame.minY - origin.y)))
                        .offset(y: barFrame.minY - origin.y)
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss(.dismissed) }
                        .accessibilityHidden(true)
                } else {
                    backdrop
                        .opacity(showBackdrop ? 1 : 0)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss(.dismissed) }
                        .accessibilityHidden(true)
                }

                if anchorIsRow {
                    // From the row: the panel fades in and rises into place. Only opacity and position animate.
                    optionsPanel(width: bar.width, fullHeight: panelFull)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(cardFill)
                                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .opacity(panelOpen ? 1 : 0)
                        // The white panel arrives quickly (so the list text behind it is hidden early); its content
                        // fades in over it with the full open curve.
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: TTSearchMotion.reduceMotionDuration)
                                : (panelOpen ? .easeOut(duration: TTSearchMotion.openDuration * 0.4) : TTSearchMotion.close),
                            value: panelOpen
                        )
                        .offset(x: bar.minX, y: panelTop + ((panelOpen || reduceMotion) ? 0 : TTSearchMotion.panelRise))
                } else {
                    // Options panel: a top-to-bottom reveal (frame height), not a scale.
                    optionsPanel(width: bar.width, fullHeight: panelFull)
                        .frame(height: panelOpen ? panelFull : 0, alignment: .top)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(cardFill)
                                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .opacity(panelOpen ? 1 : 0)
                        .offset(x: bar.minX, y: panelTop)
                }

                openBar
                    .frame(width: barWidth, height: bar.height)
                    // From the row: the field is invisible while it is icon-sized, so the closing fold ends exactly on the
                    // real icon instead of leaving a gray pill behind it.
                    .opacity(anchorIsRow ? ((reduceMotion ? barShown : barVisible) ? 1 : 0) : 1)
                    .offset(x: bar.minX, y: bar.minY)

                if !reduceMotion {
                    Button { dismiss(.dismissed) } label: {
                        Text("Cancel")
                            .font(TTFont.workSans(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Self.cancelWidth - Self.barGap, height: max(bar.height, 44))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(showCancel ? 1 : 0)
                    .allowsHitTesting(showCancel)
                    .offset(x: bar.maxX - (Self.cancelWidth - Self.barGap), y: bar.minY - max(0, (44 - bar.height) / 2))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(.container)
        .perfTempScreen("Plans search") // PERF-TEMP
        .onAppear(perform: present)
        .onDisappear { debounceTask?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            // From the row the panel keeps its size while the keyboard leaves (it is fading out).
            guard !(anchorIsRow && isClosing) else { return }
            let top = frame.minY >= UIScreen.main.bounds.height ? UIScreen.main.bounds.height : frame.minY
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { keyboardTop = top }
        }
        .onChange(of: query) { _, newValue in scheduleDebounce(newValue) }
    }

    /// The bar itself: same look as the Plans list's search field, now editable.
    private var openBar: some View {
        HStack(spacing: 10) {
            TTIcon(icon: .magnifyingGlass, size: 16)
                .foregroundStyle(TTColor.inkMuted)
                .accessibilityHidden(true)

            TextField("", text: $query, prompt: Text(catalog.copy.pillPlaceholder))
                .font(TTFont.body(15))
                .focused($fieldFocused)
                .accessibilityFocused($fieldA11yFocus)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { performSearch() }
                .accessibilityLabel("Search plans")

            if !query.isEmpty {
                Button {
                    // Empty the text, keep focus, stay open; suggestions fade back in 150 ms.
                    fieldFocused = true
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.15)) {
                        query = ""
                        debouncedQuery = ""
                    }
                } label: {
                    TTIcon(icon: .closeXCircle, filled: true, size: 18)
                        .foregroundStyle(TTColor.inkSubtle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 2)
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
        .background(Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(fieldFocused ? TTColor.actionOrange : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func optionsPanel(width: CGFloat, fullHeight: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if reduceMotion {
                    HStack {
                        Spacer()
                        Button { dismiss(.dismissed) } label: {
                            Text("Cancel")
                                .font(TTFont.workSans(15, weight: .semibold))
                                .foregroundStyle(TTColor.actionOrange)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                optionChips

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showResultsButton
                }

                refinedList
            }
            .padding(16)
            .frame(width: width, alignment: .topLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(width: width, height: fullHeight, alignment: .top)
        .opacity(showContent ? 1 : 0)
    }

    /// Focus and Popular as small chips at the top of the panel (tap again to go back to "Your plans").
    private var optionChips: some View {
        HStack(spacing: 8) {
            optionChip(.categories, title: catalog.copy.categoriesTab, icon: .folder)
            optionChip(.popular, title: catalog.copy.popularTab, icon: .fire1)
            Spacer(minLength: 0)
        }
    }

    private func optionChip(_ tab: TTSearchTopTab, title: String, icon: SandowIcon) -> some View {
        let on = topTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { topTab = on ? .items : tab }
        } label: {
            HStack(spacing: 5) {
                TTIcon(icon: icon, filled: on, size: 13)
                Text(LocalizedStringKey(title))
                    .font(TTFont.textSM(.semibold))
            }
            .foregroundStyle(on ? Color.white : TTColor.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(on ? Color.black : canvas)
            .clipShape(Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Panel list: chip lists, recents, "Your plans", live results while typing.
    @ViewBuilder
    private var refinedList: some View {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            switch topTab {
            case .categories:
                sectionLabel(catalog.copy.categoriesSection)
                ForEach(Array(catalog.categories.enumerated()), id: \.element.id) { index, category in
                    categoryRow(category, query: "")
                        .modifier(TTSearchRowStagger(index: index, refined: true, reduceMotion: reduceMotion, shown: showContent))
                }
            case .popular:
                sectionLabel(catalog.copy.popularSection)
                ForEach(Array(catalog.popularItems.prefix(8).enumerated()), id: \.element.id) { index, item in
                    itemRow(item, query: "")
                        .modifier(TTSearchRowStagger(index: index, refined: true, reduceMotion: reduceMotion, shown: showContent))
                }
            case .items:
                if !recents.isEmpty {
                    recentHeader
                    ForEach(Array(recents.prefix(5).enumerated()), id: \.offset) { index, recent in
                        recentRow(recent)
                            .modifier(TTSearchRowStagger(index: index, refined: true, reduceMotion: reduceMotion, shown: showContent))
                    }
                }
                sectionLabel(catalog.copy.suggestedSection)
                ForEach(Array(catalog.suggestedItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                    itemRow(item, query: "")
                        .modifier(TTSearchRowStagger(index: index, refined: true, reduceMotion: reduceMotion, shown: showContent))
                }
                if catalog.hasOffer {
                    sectionLabel(catalog.copy.offerTitle)
                    offerContent
                }
            }
        } else {
            let cats = TTSearchEngine.filteredCategories(catalog.categories, query: q)
            let items = TTSearchEngine.filteredItems(catalog.items, query: q)
            if cats.isEmpty && items.isEmpty {
                emptyResults
            } else {
                if !cats.isEmpty {
                    sectionLabel(catalog.copy.categoriesSection)
                    ForEach(cats) { category in
                        categoryRow(category, query: q)
                    }
                }
                if !items.isEmpty {
                    sectionLabel(catalog.copy.suggestedSection)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item, query: q)
                            .modifier(TTSearchRowStagger(index: index, refined: true, reduceMotion: reduceMotion, shown: showContent))
                    }
                }
            }
        }
    }

    // MARK: Present / dismiss motion

    private func present() {
        recents = Array(TTSearchRecentsStore.load(scopeId: catalog.scopeId).prefix(5))
        if refined {
            presentRefined()
            return
        }
        let present = reduceMotion ? Animation.easeOut(duration: 0.12) : TTMotion.searchPresent
        let chrome = reduceMotion ? Animation.easeOut(duration: 0.1) : TTMotion.searchChrome
        withAnimation(present) { showBackdrop = true }
        let contentDelay = reduceMotion ? 0.0 : 0.12
        let chromeDelay = reduceMotion ? 0.04 : 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + contentDelay) {
            withAnimation(present) { showContent = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + chromeDelay) {
            withAnimation(chrome) { showChrome = true }
        }
    }

    // MARK: Refined motion (Plans)

    /// Open: everything starts together on tap.
    private static let barCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.32)
    private static let panelCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.36)
    private static let cancelIn = Animation.easeOut(duration: 0.18).delay(0.14)
    private static let dimIn = Animation.easeOut(duration: 0.26)
    /// Close: faster and accelerating, everything together.
    private static let foldCurve = Animation.timingCurve(0.5, 0, 1, 0.6, duration: 0.24)
    private static let rowsOut = Animation.easeOut(duration: 0.08)
    private static let dimOut = Animation.easeOut(duration: 0.22)

    /// Open from the row's search icon: everything starts together on the tap, and the field takes focus at the
    /// same moment so the keyboard rises with it. Only position, width and opacity animate.
    private func presentFromRow() {
        PerfTemp.interval("search.open", seconds: TTSearchMotion.openDuration) // PERF-TEMP
        isFocusedPhase = true
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Search opened"))
        if reduceMotion {
            withAnimation(.easeOut(duration: TTSearchMotion.reduceMotionDuration)) {
                barShown = true
                panelOpen = true
                showContent = true
                showBackdrop = true
            }
        } else {
            withAnimation(TTSearchMotion.open) {
                barNarrow = true
                panelOpen = true
                showContent = true
                showBackdrop = true
            }
            withAnimation(.easeOut(duration: TTSearchMotion.openDuration * 0.3)) { barVisible = true }
            withAnimation(TTSearchMotion.cancelIn) { showCancel = true }
        }
        // Next turn of the run loop = when the animation starts (not before, not after it ends).
        DispatchQueue.main.async {
            fieldFocused = true
            if UIAccessibility.isVoiceOverRunning { fieldA11yFocus = true }
        }
    }

    private func dismissToRow(_ outcome: TTSearchOutcome) {
        guard !isClosing else { return }
        isClosing = true
        PerfTemp.interval("search.close", seconds: TTSearchMotion.closeDuration) // PERF-TEMP
        // The keyboard leaves together with the field, not after it.
        fieldFocused = false
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Search closed"))
        onWillClose?()
        if reduceMotion {
            withAnimation(.easeOut(duration: TTSearchMotion.reduceMotionDuration)) {
                barShown = false
                panelOpen = false
                showContent = false
                showBackdrop = false
                showCancel = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + TTSearchMotion.reduceMotionDuration + 0.01) { onOutcome(outcome) }
            return
        }
        withAnimation(TTSearchMotion.close) {
            barNarrow = false
            panelOpen = false
            showContent = false
            showBackdrop = false
            showCancel = false
        }
        // The field stays solid while it folds and fades only when it is back at icon size.
        withAnimation(.easeIn(duration: TTSearchMotion.closeDuration * 0.4).delay(TTSearchMotion.closeDuration * 0.6)) {
            barVisible = false
        }
        // Removed only after the field is back inside the icon.
        DispatchQueue.main.asyncAfter(deadline: .now() + TTSearchMotion.closeDuration + 0.02) { onOutcome(outcome) }
    }

    private func presentRefined() {
        if anchorIsRow {
            presentFromRow()
            return
        }
        PerfTemp.interval("search.open", seconds: 0.5) // PERF-TEMP
        isFocusedPhase = true
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Search opened"))
        if reduceMotion {
            // 160 ms fade: no width change, no unfolding, no stagger.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { barNarrow = false; panelOpen = true }
            withAnimation(.easeOut(duration: 0.16)) {
                showBackdrop = true
                showContent = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { fieldFocused = true }
            return
        }
        withAnimation(Self.barCurve) { barNarrow = true }
        withAnimation(Self.cancelIn) { showCancel = true }
        withAnimation(Self.panelCurve) {
            panelOpen = true
            showContent = true
        }
        withAnimation(Self.dimIn) { showBackdrop = true }
        // Focus a moment after the animation starts so the keyboard doesn't cause a jump.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { fieldFocused = true }
    }

    private func dismissRefined(_ outcome: TTSearchOutcome) {
        if anchorIsRow {
            dismissToRow(outcome)
            return
        }
        guard !isClosing else { return }
        isClosing = true
        PerfTemp.interval("search.close", seconds: 0.35) // PERF-TEMP
        // The keyboard leaves together with the panel, not after it.
        fieldFocused = false
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Search closed"))
        if reduceMotion {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { panelOpen = false }
            withAnimation(.easeOut(duration: 0.12)) {
                showContent = false
                showBackdrop = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { onOutcome(outcome) }
            return
        }
        withAnimation(Self.rowsOut) { showContent = false }
        withAnimation(Self.foldCurve) {
            panelOpen = false
            barNarrow = false
        }
        withAnimation(.easeOut(duration: 0.12)) { showCancel = false }
        withAnimation(Self.dimOut) { showBackdrop = false }
        // The panel stays in the hierarchy until the fold has finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { onOutcome(outcome) }
    }

    private func dismiss(_ outcome: TTSearchOutcome) {
        if refined {
            dismissRefined(outcome)
            return
        }
        fieldFocused = false
        let anim = reduceMotion ? Animation.easeOut(duration: 0.12) : TTMotion.searchPresent
        withAnimation(anim) {
            showChrome = false
            showContent = false
            showBackdrop = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.08 : 0.28)) {
            onOutcome(outcome)
        }
    }

    private func scheduleDebounce(_ value: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: TTMotion.searchDebounceNs)
            guard !Task.isCancelled else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                debouncedQuery = value
            }
        }
    }

    private func enterFocusedPhase(focusField: Bool) {
        guard !isFocusedPhase else {
            if focusField { fieldFocused = true }
            return
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : TTMotion.searchMorph) {
            isFocusedPhase = true
            step = .what
        }
        if focusField {
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.02 : 0.12)) {
                fieldFocused = true
            }
        }
    }

    private func exitFocusedPhase() {
        fieldFocused = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : TTMotion.searchMorph) {
            isFocusedPhase = false
        }
    }

    // MARK: Backdrop

    private var backdrop: some View {
        ZStack {
            // Refined: a darker dim so white tab labels stay readable on it.
            Color.black.opacity(refined ? 0.35 : 0.22)
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(refined ? 0.5 : 0.55)
        }
        .ignoresSafeArea()
    }

    // MARK: Chrome / tabs

    private var chrome: some View {
        HStack(spacing: 6) {
            tabButton(.items, title: catalog.copy.itemsTab, icon: .listTwoBullet)
            tabButton(.categories, title: catalog.copy.categoriesTab, icon: .folder)
            tabButton(.popular, title: catalog.copy.popularTab, icon: .fire1)
            Spacer(minLength: 4)
            Button {
                dismiss(.dismissed)
            } label: {
                TTIcon(icon: .closeX, size: 16)
                    .foregroundStyle(TTColor.ink)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TTSearchPressStyle())
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func tabButton(_ tab: TTSearchTopTab, title: String, icon: SandowIcon) -> some View {
        let on = topTab == tab
        return Button {
            if refined { fieldFocused = false }
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : TTMotion.searchChrome) {
                topTab = tab
                if refined { isFocusedPhase = false }
                if isFocusedPhase == false { step = .what }
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    TTIcon(icon: icon, filled: on, size: 13)
                    Text(LocalizedStringKey(title))
                        .font(TTFont.textSM(.semibold))
                }
                .foregroundStyle(on ? TTColor.actionOrange : (refined ? Color.white.opacity(0.85) : TTColor.inkMuted))
                Capsule()
                    .fill(on ? TTColor.actionOrange : Color.clear)
                    .frame(width: on ? 28 : 0, height: 3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(on ? Color.white.opacity(0.95) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TTSearchPressStyle())
    }

    // MARK: Accordion

    private var accordion: some View {
        VStack(spacing: 10) {
            stepCard(.what)
            if catalog.hasOffer { stepCard(.offer) }
            if catalog.hasBest { stepCard(.best) }
            if catalog.hasRecommend { stepCard(.recommend) }
        }
    }

    @ViewBuilder
    private func stepCard(_ target: TTSearchAccordionStep) -> some View {
        let expanded = step == target
        if expanded {
            expandedCard(target)
                .transition(.opacity)
        } else {
            collapsedRow(target)
                .transition(.opacity)
        }
    }

    private func collapsedRow(_ target: TTSearchAccordionStep) -> some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : TTMotion.searchMorph) {
                step = target
                if target != .what {
                    fieldFocused = false
                    isFocusedPhase = false
                }
            }
        } label: {
            HStack {
                Text(stepTitle(target))
                    .font(TTFont.textMD(.medium))
                    .foregroundStyle(TTColor.inkMuted)
                Spacer()
                Text(stepSummary(target))
                    .font(TTFont.textMD(.semibold))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(cardFill.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(TTSearchPressStyle())
    }

    private func expandedCard(_ target: TTSearchAccordionStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Refined search drops the redundant "What" heading above the field.
            if !(refined && target == .what) {
                Text(stepTitle(target))
                    .font(TTFont.workSans(18, weight: .bold))
                    .foregroundStyle(TTColor.ink)
            }

            switch target {
            case .what:
                whatContent
            case .offer:
                offerContent
            case .best:
                curatedList(catalog.bestSell, empty: "No top picks yet")
            case .recommend:
                curatedList(catalog.recommendations, empty: "No recommendations yet")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: target == .what && isFocusedPhase ? 420 : nil, alignment: .top)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 16, y: 6)
    }

    private func stepTitle(_ target: TTSearchAccordionStep) -> String {
        switch target {
        case .what: catalog.copy.whatTitle
        case .offer: catalog.copy.offerTitle
        case .best: catalog.copy.bestTitle
        case .recommend: catalog.copy.recommendTitle
        }
    }

    private func stepSummary(_ target: TTSearchAccordionStep) -> String {
        switch target {
        case .what:
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return q.isEmpty ? catalog.copy.whatPlaceholder : q
        case .offer:
            return catalog.offer?.title ?? "No offer"
        case .best:
            return catalog.bestSell.isEmpty ? "See picks" : "\(catalog.bestSell.count) \(catalog.copy.itemNoun)"
        case .recommend:
            return catalog.recommendations.isEmpty ? "See picks" : "\(catalog.recommendations.count) \(catalog.copy.itemNoun)"
        }
    }

    // MARK: What

    private var whatContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField

            if isFocusedPhase {
                focusedBody
            } else {
                browseBody
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Button {
                if isFocusedPhase {
                    query = ""
                    debouncedQuery = ""
                    exitFocusedPhase()
                } else {
                    enterFocusedPhase(focusField: true)
                }
            } label: {
                TTIcon(icon: isFocusedPhase ? .arrowLeft : .magnifyingGlass, size: 18)
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(TTSearchPressStyle())

            TextField(catalog.copy.whatPlaceholder, text: $query)
                .accessibilityLabel(catalog.copy.whatPlaceholder)
                .font(TTFont.body(16))
                .focused($fieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { performSearch() }

            if !query.isEmpty {
                Button {
                    if refined {
                        // Empty the text, keep focus, stay open; suggestions fade back in 150 ms.
                        fieldFocused = true
                        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.15)) {
                            query = ""
                            debouncedQuery = ""
                        }
                    } else {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            query = ""
                            debouncedQuery = ""
                        }
                    }
                } label: {
                    TTIcon(icon: .closeXCircle, filled: true, size: 18)
                        .foregroundStyle(TTColor.inkSubtle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TTSearchPressStyle())
                .accessibilityLabel(refined ? "Clear text" : "Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(fieldFocused ? TTInputChrome.activeFill : canvas)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    fieldFocused ? TTColor.actionOrange : Color.black.opacity(0.06),
                    lineWidth: fieldFocused ? TTInputChrome.borderWidth : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: fieldFocused)
        .matchedGeometryEffect(id: matchedID, in: namespace)
        .onTapGesture { enterFocusedPhase(focusField: true) }
    }

    private var showResultsButton: some View {
        Button {
            performSearch()
        } label: {
            HStack {
                Text("Show results")
                    .font(TTFont.workSans(16, weight: .semibold))
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(TTSearchPressStyle(scale: 0.98))
        .transition(.opacity)
    }

    @ViewBuilder
    private var browseBody: some View {
        switch topTab {
        case .items:
            if !recents.isEmpty {
                recentHeader
                ForEach(Array(recents.prefix(3).enumerated()), id: \.offset) { index, recent in
                    recentRow(recent)
                        .modifier(TTSearchRowStagger(index: index, refined: refined, reduceMotion: reduceMotion, shown: showContent))
                }
            }
            sectionLabel(catalog.copy.suggestedSection)
            ForEach(Array(catalog.suggestedItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                itemRow(item, query: "")
                    .modifier(TTSearchRowStagger(index: index, refined: refined, reduceMotion: reduceMotion, shown: showContent))
            }
        case .categories:
            sectionLabel(catalog.copy.categoriesSection)
            ForEach(Array(catalog.categories.enumerated()), id: \.element.id) { index, category in
                categoryRow(category, query: "")
                    .modifier(TTSearchRowStagger(index: index, refined: refined, reduceMotion: reduceMotion, shown: showContent))
            }
        case .popular:
            sectionLabel(catalog.copy.popularSection)
            ForEach(Array(catalog.popularItems.prefix(8).enumerated()), id: \.element.id) { index, item in
                itemRow(item, query: "")
                    .modifier(TTSearchRowStagger(index: index, refined: refined, reduceMotion: reduceMotion, shown: showContent))
            }
        }
    }

    @ViewBuilder
    private var focusedBody: some View {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            if !recents.isEmpty {
                recentHeader
                ForEach(Array(recents.prefix(5).enumerated()), id: \.offset) { _, recent in
                    recentRow(recent)
                }
            }
            if !catalog.popularItems.isEmpty {
                sectionLabel(catalog.copy.popularNowSection)
                ForEach(catalog.popularItems.prefix(4)) { item in
                    itemRow(item, query: "")
                }
            }
            if !catalog.categories.isEmpty {
                sectionLabel(catalog.copy.categoriesSection)
                ForEach(catalog.categories.prefix(4)) { category in
                    categoryRow(category, query: "")
                }
            }
            sectionLabel(catalog.copy.suggestedSection)
            ForEach(catalog.suggestedItems.prefix(5)) { item in
                itemRow(item, query: "")
            }
        } else {
            let cats = TTSearchEngine.filteredCategories(catalog.categories, query: q)
            let items = TTSearchEngine.filteredItems(catalog.items, query: q)
            if cats.isEmpty && items.isEmpty {
                emptyResults
            } else {
                if !cats.isEmpty {
                    sectionLabel(catalog.copy.categoriesSection)
                    ForEach(cats) { category in
                        categoryRow(category, query: q)
                    }
                }
                if !items.isEmpty {
                    sectionLabel(catalog.copy.suggestedSection)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item, query: q)
                            .modifier(TTSearchRowStagger(index: index, refined: refined, reduceMotion: reduceMotion, shown: showContent))
                    }
                }
            }
        }
    }

    private var emptyResults: some View {
        let typed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 6) {
            Text(refined && catalog.scopeId.hasPrefix("plans.") ? String(localized: "No plans match “\(typed)”") : catalog.copy.emptyTitle)
                .font(TTFont.workSans(16, weight: .bold))
                .foregroundStyle(TTColor.ink)
            Text(catalog.copy.emptySubtitle)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(.vertical, 12)
    }

    // MARK: Offer / curated

    @ViewBuilder
    private var offerContent: some View {
        if let offer = catalog.offer {
            Button {
                TTSearchRecentsStore.save(offer.title, scopeId: catalog.scopeId)
                dismiss(.offer(offer.id))
            } label: {
                HStack(spacing: 14) {
                    iconTile(offer.icon, tint: TTColor.actionOrange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(offer.title)
                            .font(TTFont.workSans(16, weight: .bold))
                            .foregroundStyle(TTColor.ink)
                        Text(offer.subtitle)
                            .font(TTFont.body(13))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(offer.cta)
                        .font(TTFont.textSM(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(TTColor.actionOrange)
                        .clipShape(Capsule())
                }
                .padding(12)
                .background(canvas)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(TTSearchPressStyle())
        }
    }

    private func curatedList(_ items: [TTSearchItem], empty: String) -> some View {
        Group {
            if items.isEmpty {
                Text(empty)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(Array(items.prefix(8).enumerated()), id: \.element.id) { index, item in
                    itemRow(item, query: "")
                        .modifier(TTSearchRowStagger(index: index, refined: refined, reduceMotion: reduceMotion, shown: showContent))
                }
            }
        }
    }

    // MARK: Rows

    /// "Recent searches" with a small Clear in refined mode (replaces the footer's "Clear all").
    @ViewBuilder
    private var recentHeader: some View {
        if refined {
            HStack {
                sectionLabel(catalog.copy.recentSection)
                Spacer(minLength: 8)
                Button {
                    TTSearchRecentsStore.clear(scopeId: catalog.scopeId)
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.15)) { recents = [] }
                } label: {
                    Text("Clear")
                        .font(TTFont.textSM(.semibold))
                        .foregroundStyle(TTColor.actionOrange)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear recent searches"))
            }
        } else {
            sectionLabel(catalog.copy.recentSection)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(TTFont.textSM(.semibold))
            .foregroundStyle(TTColor.inkMuted)
            .padding(.top, 4)
    }

    private func recentRow(_ recent: String) -> some View {
        Button {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                query = recent
                debouncedQuery = recent
            }
            enterFocusedPhase(focusField: true)
        } label: {
            HStack(spacing: 12) {
                iconTile(.magnifyingGlass, tint: TTColor.inkMuted.opacity(0.85), soft: true)
                Text(recent)
                    .font(TTFont.body(15))
                    .foregroundStyle(TTColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(TTSearchPressStyle())
    }

    private func itemRow(_ item: TTSearchItem, query: String) -> some View {
        Button {
            selectItem(item)
        } label: {
            HStack(spacing: 12) {
                iconTile(item.icon, tint: item.tint)
                VStack(alignment: .leading, spacing: 3) {
                    TTHighlightedText(text: item.title, query: query, font: TTFont.workSans(15, weight: .semibold))
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(TTFont.caption(12))
                            .foregroundStyle(TTColor.inkMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let meta = item.meta, !meta.isEmpty {
                    Text(meta)
                        .font(TTFont.textSM(.semibold))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(TTSearchPressStyle())
    }

    private func categoryRow(_ category: TTSearchCategory, query: String) -> some View {
        Button {
            selectCategory(category)
        } label: {
            HStack(spacing: 12) {
                iconTile(category.icon, tint: category.tint)
                VStack(alignment: .leading, spacing: 3) {
                    TTHighlightedText(text: category.name, query: query, font: TTFont.workSans(15, weight: .semibold))
                    Text("\(category.count) \(catalog.copy.itemNoun)")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                TTIcon(icon: .chevronRight, size: 14)
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(TTSearchPressStyle())
    }

    private func iconTile(_ icon: SandowIcon, tint: Color, soft: Bool = false) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(soft ? 0.08 : 0.14))
            TTIcon(icon: icon, filled: !soft, size: 18)
                .foregroundStyle(tint)
        }
        .frame(width: 48, height: 48)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                Button {
                    clearAll()
                } label: {
                    Text(catalog.copy.clearAll)
                        .font(TTFont.workSans(15, weight: .semibold))
                        .foregroundStyle(canClear ? TTColor.ink : TTColor.inkSubtle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(TTSearchPressStyle())
                .disabled(!canClear)

                Button {
                    performSearch()
                } label: {
                    Text(catalog.copy.searchButton)
                        .font(TTFont.workSans(16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(TTColor.actionOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(TTSearchPressStyle(scale: 0.97))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var canClear: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedCategoryId != nil
            || !recents.isEmpty
    }

    private func clearAll() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            query = ""
            debouncedQuery = ""
            selectedCategoryId = nil
        }
        TTSearchRecentsStore.clear(scopeId: catalog.scopeId)
        recents = []
        exitFocusedPhase()
    }

    // MARK: Selection

    private func selectItem(_ item: TTSearchItem) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { TTSearchRecentsStore.save(q, scopeId: catalog.scopeId) }
        else { TTSearchRecentsStore.save(item.title, scopeId: catalog.scopeId) }
        dismiss(.item(item.id))
    }

    private func selectCategory(_ category: TTSearchCategory) {
        selectedCategoryId = category.id
        TTSearchRecentsStore.save(category.name, scopeId: catalog.scopeId)
        dismiss(.category(category.id))
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedCategoryId, q.isEmpty {
            dismiss(.category(selectedCategoryId))
            return
        }
        if q.isEmpty {
            enterFocusedPhase(focusField: true)
            return
        }
        TTSearchRecentsStore.save(q, scopeId: catalog.scopeId)
        let items = TTSearchEngine.filteredItems(catalog.items, query: q)
        if let first = items.first {
            dismiss(.item(first.id))
        } else {
            dismiss(.applyQuery(q))
        }
    }
}

// MARK: - Refined-mode helpers

/// First five rows fade in with a 30 ms stagger; classic mode keeps the old static ladder.
private struct TTSearchRowStagger: ViewModifier {
    let index: Int
    let refined: Bool
    let reduceMotion: Bool
    let shown: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if refined {
            if reduceMotion || index >= 5 {
                content
            } else {
                content
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.2).delay(Double(index) * 0.03), value: shown)
            }
        } else {
            content.opacity(index < 8 ? (shown ? 1 : 0) : 1)
        }
    }
}

// MARK: - Host helper

struct TTSearchHostModifier: ViewModifier {
    @Binding var isPresented: Bool
    let catalog: TTSearchCatalog
    var namespace: Namespace.ID
    var matchedID: String = "ttSearchMorph"
    /// Refined search renders in the view hierarchy (matched-geometry morph from the entry pill)
    /// instead of a full-screen cover, so open and close share one choreography.
    var refined: Bool = false
    var onOutcome: (TTSearchOutcome) -> Void

    @State private var visible = false
    @State private var barFrame: CGRect = .zero
    @State private var frameBox = TTSearchFrameBox()
    /// Opened from the pinned row's search icon (the field grows out of the icon) instead of the entry pill.
    @State private var anchorIsRow = false
    /// The row's other controls are faded out. Changed inside withAnimation, so they fade (and slide) with the field.
    @State private var rowFaded = false
    /// Row mode: the close has started, so the floating tab bar may come back together with the fold.
    @State private var rowClosing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if refined {
            content
                .environment(\.ttSearchMorphed, visible)
                .environment(\.ttSearchFrameBox, frameBox)
                .environment(\.ttSearchRowFaded, rowFaded)
                .overlay {
                    if visible {
                        TTSearchOverlay(
                            catalog: catalog,
                            namespace: namespace,
                            matchedID: matchedID,
                            refined: true,
                            barFrame: barFrame,
                            anchorIsRow: anchorIsRow,
                            onWillClose: {
                                guard anchorIsRow else { return }
                                rowClosing = true
                                // The row's controls come back late in the fold, when the field is nearly an icon again.
                                withAnimation(
                                    reduceMotion
                                        ? .easeOut(duration: TTSearchMotion.reduceMotionDuration)
                                        : .easeOut(duration: TTSearchMotion.closeDuration * 0.5).delay(TTSearchMotion.closeDuration * 0.5)
                                ) {
                                    rowFaded = false
                                }
                            }
                        ) { outcome in
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                visible = false
                                isPresented = false
                                rowFaded = false
                                rowClosing = false
                            }
                            DispatchQueue.main.async { onOutcome(outcome) }
                        }
                        .transition(.identity)
                    }
                }
                // The floating tab bar (and its + button) stays out of the way while search is open.
                .ttRootTabBarVisible(!(visible && !rowClosing))
                .onChange(of: isPresented, initial: true) { _, presented in
                    guard presented, !visible else { return }
                    // Read the bar's place once, right now; fall back to a plausible slot if it isn't on screen.
                    let screen = UIScreen.main.bounds
                    let fromRow = frameBox.opensFromRow
                    frameBox.opensFromRow = false
                    if fromRow, let row = frameBox.rowFrame() {
                        // The row is on screen exactly where it is: nothing scrolls, nothing is measured from the header.
                        barFrame = row
                        anchorIsRow = true
                    } else {
                        barFrame = frameBox.globalFrame()
                            ?? CGRect(x: 16, y: 150, width: screen.width - 32, height: 48)
                        anchorIsRow = false
                    }
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { visible = true }
                    if anchorIsRow {
                        withAnimation(
                            reduceMotion
                                ? .easeOut(duration: TTSearchMotion.reduceMotionDuration)
                                : .timingCurve(0.16, 1, 0.3, 1, duration: TTSearchMotion.rowFadeDuration)
                        ) {
                            rowFaded = true
                        }
                    }
                }
        } else {
            content
                .fullScreenCover(isPresented: $isPresented) {
                    TTSearchOverlay(
                        catalog: catalog,
                        namespace: namespace,
                        matchedID: matchedID
                    ) { outcome in
                        isPresented = false
                        DispatchQueue.main.async {
                            onOutcome(outcome)
                        }
                    }
                    .presentationBackground(.clear)
                }
                .transaction(value: isPresented) { transaction in
                    // Soft custom springs own the open/close — suppress the system slide.
                    if isPresented {
                        transaction.disablesAnimations = true
                    }
                }
        }
    }
}

extension View {
    func ttSearchOverlay(
        isPresented: Binding<Bool>,
        catalog: TTSearchCatalog,
        namespace: Namespace.ID,
        matchedID: String = "ttSearchMorph",
        refined: Bool = false,
        onOutcome: @escaping (TTSearchOutcome) -> Void
    ) -> some View {
        modifier(
            TTSearchHostModifier(
                isPresented: isPresented,
                catalog: catalog,
                namespace: namespace,
                matchedID: matchedID,
                refined: refined,
                onOutcome: onOutcome
            )
        )
    }
}
