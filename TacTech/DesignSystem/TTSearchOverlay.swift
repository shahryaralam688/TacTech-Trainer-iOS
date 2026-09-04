import SwiftUI

// MARK: - Entry pill (morph source)

struct TTSearchEntryPill: View {
    let placeholder: String
    var query: String = ""
    var style: Style = .light
    var namespace: Namespace.ID
    var matchedID: String = "ttSearchMorph"
    var onTap: () -> Void

    enum Style {
        case light, onDark
    }

    var body: some View {
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool

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

    var body: some View {
        ZStack {
            backdrop
                .opacity(showBackdrop ? 1 : 0)
                .allowsHitTesting(false)

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
            .safeAreaPadding(.top, 8)

            if !isFocusedPhase {
                footer
                    .opacity(showContent ? 1 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(showBackdrop ? 0.35 : 0).ignoresSafeArea())
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

    // MARK: Present / dismiss motion

    private func present() {
        recents = Array(TTSearchRecentsStore.load(scopeId: catalog.scopeId).prefix(5))
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

    private func dismiss(_ outcome: TTSearchOutcome) {
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
            Color.black.opacity(0.22)
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
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
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : TTMotion.searchChrome) {
                topTab = tab
                if isFocusedPhase == false { step = .what }
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    TTIcon(icon: icon, filled: on, size: 13)
                    Text(title)
                        .font(TTFont.textSM(.semibold))
                }
                .foregroundStyle(on ? TTColor.actionOrange : TTColor.inkMuted)
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
            Text(stepTitle(target))
                .font(TTFont.workSans(18, weight: .bold))
                .foregroundStyle(TTColor.ink)

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
                .font(TTFont.body(16))
                .focused($fieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { performSearch() }

            if !query.isEmpty {
                Button {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        query = ""
                        debouncedQuery = ""
                    }
                } label: {
                    TTIcon(icon: .closeXCircle, filled: true, size: 18)
                        .foregroundStyle(TTColor.inkSubtle)
                }
                .buttonStyle(TTSearchPressStyle())
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(canvas)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    fieldFocused ? TTColor.actionOrange.opacity(0.55) : Color.black.opacity(0.06),
                    lineWidth: fieldFocused ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .matchedGeometryEffect(id: matchedID, in: namespace)
        .onTapGesture { enterFocusedPhase(focusField: true) }
    }

    @ViewBuilder
    private var browseBody: some View {
        switch topTab {
        case .items:
            if !recents.isEmpty {
                sectionLabel(catalog.copy.recentSection)
                ForEach(Array(recents.prefix(3).enumerated()), id: \.offset) { index, recent in
                    recentRow(recent)
                        .opacity(rowOpacity(index))
                }
            }
            sectionLabel(catalog.copy.suggestedSection)
            ForEach(Array(catalog.suggestedItems.prefix(5).enumerated()), id: \.element.id) { index, item in
                itemRow(item, query: "")
                    .opacity(rowOpacity(index))
            }
        case .categories:
            sectionLabel(catalog.copy.categoriesSection)
            ForEach(Array(catalog.categories.enumerated()), id: \.element.id) { index, category in
                categoryRow(category, query: "")
                    .opacity(rowOpacity(index))
            }
        case .popular:
            sectionLabel(catalog.copy.popularSection)
            ForEach(Array(catalog.popularItems.prefix(8).enumerated()), id: \.element.id) { index, item in
                itemRow(item, query: "")
                    .opacity(rowOpacity(index))
            }
        }
    }

    @ViewBuilder
    private var focusedBody: some View {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            if !recents.isEmpty {
                sectionLabel(catalog.copy.recentSection)
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
                            .opacity(rowOpacity(index))
                    }
                }
            }
        }
    }

    private var emptyResults: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(catalog.copy.emptyTitle)
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
                        .opacity(rowOpacity(index))
                }
            }
        }
    }

    // MARK: Rows

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
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

    private func rowOpacity(_ index: Int) -> Double {
        // Light stagger cue for first rows only — static opacity ladder, no continuous springs.
        guard index < 8 else { return 1 }
        return showContent ? 1 : 0
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

// MARK: - Host helper

struct TTSearchHostModifier: ViewModifier {
    @Binding var isPresented: Bool
    let catalog: TTSearchCatalog
    var namespace: Namespace.ID
    var matchedID: String = "ttSearchMorph"
    var onOutcome: (TTSearchOutcome) -> Void

    func body(content: Content) -> some View {
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

extension View {
    func ttSearchOverlay(
        isPresented: Binding<Bool>,
        catalog: TTSearchCatalog,
        namespace: Namespace.ID,
        matchedID: String = "ttSearchMorph",
        onOutcome: @escaping (TTSearchOutcome) -> Void
    ) -> some View {
        modifier(
            TTSearchHostModifier(
                isPresented: isPresented,
                catalog: catalog,
                namespace: namespace,
                matchedID: matchedID,
                onOutcome: onOutcome
            )
        )
    }
}
