import SwiftUI

// MARK: - Universal search models (domain-agnostic)

struct TTSearchItem: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var categoryId: String?
    var categoryName: String?
    var meta: String?
    var tags: [String]
    var icon: SandowIcon
    var tint: Color

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        categoryId: String? = nil,
        categoryName: String? = nil,
        meta: String? = nil,
        tags: [String] = [],
        icon: SandowIcon = .magnifyingGlass,
        tint: Color = TTColor.actionOrange
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.meta = meta
        self.tags = tags
        self.icon = icon
        self.tint = tint
    }
}

struct TTSearchCategory: Identifiable, Hashable {
    var id: String
    var name: String
    var count: Int
    var icon: SandowIcon
    var tint: Color

    init(
        id: String,
        name: String,
        count: Int,
        icon: SandowIcon = .folder,
        tint: Color = TTColor.info
    ) {
        self.id = id
        self.name = name
        self.count = count
        self.icon = icon
        self.tint = tint
    }
}

struct TTSearchOffer: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var cta: String
    var icon: SandowIcon

    init(
        id: String = "offer",
        title: String,
        subtitle: String,
        cta: String = "View",
        icon: SandowIcon = .gift
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.cta = cta
        self.icon = icon
    }
}

struct TTSearchCopy: Hashable {
    var pillPlaceholder: String
    var whatPlaceholder: String
    var itemsTab: String
    var categoriesTab: String
    var popularTab: String
    var suggestedSection: String
    var categoriesSection: String
    var popularSection: String
    var recentSection: String
    var popularNowSection: String
    var emptyTitle: String
    var emptySubtitle: String
    var clearAll: String
    var searchButton: String
    var whatTitle: String
    var offerTitle: String
    var bestTitle: String
    var recommendTitle: String
    var itemNoun: String
    var categoryNoun: String

    static let plans = TTSearchCopy(
        pillPlaceholder: "Search plans…",
        whatPlaceholder: "Search workout plans",
        itemsTab: "Plans",
        categoriesTab: "Focus",
        popularTab: "Popular",
        suggestedSection: "Suggested for you",
        categoriesSection: "Training focus",
        popularSection: "Popular plans",
        recentSection: "Recent searches",
        popularNowSection: "Popular now",
        emptyTitle: "No plans found",
        emptySubtitle: "Try another name, focus, or level.",
        clearAll: "Clear all",
        searchButton: "Search",
        whatTitle: "What",
        offerTitle: "Featured",
        bestTitle: "Top plans",
        recommendTitle: "Recommended",
        itemNoun: "plans",
        categoryNoun: "focus areas"
    )

    static let trainees = TTSearchCopy(
        pillPlaceholder: "Search trainees…",
        whatPlaceholder: "Search athletes",
        itemsTab: "Athletes",
        categoriesTab: "Goals",
        popularTab: "Active",
        suggestedSection: "Suggested for you",
        categoriesSection: "Training goals",
        popularSection: "Active athletes",
        recentSection: "Recent searches",
        popularNowSection: "Recently active",
        emptyTitle: "No athletes found",
        emptySubtitle: "Try another name or goal.",
        clearAll: "Clear all",
        searchButton: "Search",
        whatTitle: "What",
        offerTitle: "Invite",
        bestTitle: "Active roster",
        recommendTitle: "Needs plan",
        itemNoun: "athletes",
        categoryNoun: "goals"
    )

    static let foods = TTSearchCopy(
        pillPlaceholder: "Search our food database…",
        whatPlaceholder: "Search foods",
        itemsTab: "Foods",
        categoriesTab: "Categories",
        popularTab: "Popular",
        suggestedSection: "Suggested for you",
        categoriesSection: "Menu categories",
        popularSection: "Popular foods",
        recentSection: "Recent searches",
        popularNowSection: "Popular now",
        emptyTitle: "No foods found",
        emptySubtitle: "Try another name or category.",
        clearAll: "Clear all",
        searchButton: "Search",
        whatTitle: "What",
        offerTitle: "Offer",
        bestTitle: "Best picks",
        recommendTitle: "Recommended",
        itemNoun: "foods",
        categoryNoun: "categories"
    )
}

struct TTSearchCatalog {
    var scopeId: String
    var items: [TTSearchItem]
    var categories: [TTSearchCategory]
    var suggestedItems: [TTSearchItem]
    var popularItems: [TTSearchItem]
    var offer: TTSearchOffer?
    var bestSell: [TTSearchItem]
    var recommendations: [TTSearchItem]
    var copy: TTSearchCopy

    var hasOffer: Bool { offer != nil }
    var hasBest: Bool { !bestSell.isEmpty }
    var hasRecommend: Bool { !recommendations.isEmpty }
}

enum TTSearchTopTab: String, CaseIterable, Identifiable {
    case items, categories, popular
    var id: String { rawValue }
}

enum TTSearchAccordionStep: String, CaseIterable, Identifiable {
    case what, offer, best, recommend
    var id: String { rawValue }
}

enum TTSearchOutcome: Equatable {
    case item(String)
    case category(String)
    case offer(String)
    case applyQuery(String)
    case dismissed
}

// MARK: - Filtering

enum TTSearchEngine {
    static func matches(item: TTSearchItem, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if item.title.localizedCaseInsensitiveContains(q) { return true }
        if item.categoryName?.localizedCaseInsensitiveContains(q) == true { return true }
        if item.subtitle?.localizedCaseInsensitiveContains(q) == true { return true }
        if item.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return true }
        return false
    }

    static func matches(category: TTSearchCategory, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return category.name.localizedCaseInsensitiveContains(q)
    }

    static func filteredItems(_ items: [TTSearchItem], query: String) -> [TTSearchItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { matches(item: $0, query: q) }
    }

    static func filteredCategories(_ categories: [TTSearchCategory], query: String) -> [TTSearchCategory] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return categories }
        return categories.filter { matches(category: $0, query: q) }
    }
}

// MARK: - Recents (per scopeId)

enum TTSearchRecentsStore {
    private static let prefix = "tt.search.recents."
    private static let cap = 10

    static func load(scopeId: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(scopeId)) ?? []
    }

    static func save(_ query: String, scopeId: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = load(scopeId: scopeId).filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > cap { list = Array(list.prefix(cap)) }
        UserDefaults.standard.set(list, forKey: key(scopeId))
    }

    static func clear(scopeId: String) {
        UserDefaults.standard.removeObject(forKey: key(scopeId))
    }

    private static func key(_ scopeId: String) -> String {
        prefix + scopeId
    }
}

// MARK: - Highlight (bold match only — no size change)

struct TTHighlightedText: View {
    let text: String
    let query: String
    var font: Font = TTFont.body(15)
    var weight: Font.Weight = .medium
    var color: Color = TTColor.ink

    var body: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return result }

        let lower = text.lowercased()
        let needle = q.lowercased()
        var searchStart = lower.startIndex
        while let found = lower.range(of: needle, range: searchStart..<lower.endIndex) {
            if let start = AttributedString.Index(found.lowerBound, within: result),
               let end = AttributedString.Index(found.upperBound, within: result) {
                result[start..<end].inlinePresentationIntent = .stronglyEmphasized
            }
            searchStart = found.upperBound
        }
        return result
    }
}

// MARK: - Press feedback

struct TTSearchPressStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: TTMotion.press), value: configuration.isPressed)
    }
}
