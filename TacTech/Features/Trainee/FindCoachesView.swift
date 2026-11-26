import SwiftUI

/// Trainee discovery — `GET /coaches` with search, filters, and cursor pagination.
struct FindCoachesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CoachListItem] = []
    @State private var nextCursor: String?
    @State private var searchText = ""
    @State private var cityFilter = ""
    @State private var specialtyFilter = ""
    @State private var showFilters = false
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var didLoad = false
    @State private var loadFailed = false
    @State private var toast: TTToastMessage?
    @State private var searchTask: Task<Void, Never>?

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(
                    title: "Find Coaches",
                    subtitle: "Discover public trainers",
                    background: .white
                ) {
                    Button {
                        showFilters.toggle()
                    } label: {
                        Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TTColor.actionOrange)
                            .frame(width: TTModalSheetChrome.controlSize, height: TTModalSheetChrome.controlSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filters")
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        TTTextField(title: "Search", icon: "magnifyingglass", text: $searchText)
                            .onChange(of: searchText) { _, _ in
                                scheduleSearch()
                            }

                        if showFilters {
                            filterFields
                        }

                        TTLoadGate(
                            isLoading: !didLoad || isLoading,
                            hasData: !items.isEmpty,
                            loadingLabel: "Loading coaches"
                        ) {
                            coachSkeleton
                        } content: {
                            if loadFailed && items.isEmpty {
                                TTLoadError(title: "Couldn’t load coaches") {
                                    Task { await reload(reset: true) }
                                }
                                .padding(.vertical, 24)
                            } else if items.isEmpty {
                                emptyState
                            } else {
                            VStack(spacing: 12) {
                            if loadFailed {
                                TTStaleNotice { Task { await reload(reset: true) } }
                            }
                            LazyVStack(spacing: 12) {
                                ForEach(items) { coach in
                                    NavigationLink {
                                        CoachDetailView(coachProfileId: coach.id)
                                    } label: {
                                        CoachDiscoveryRow(coach: coach)
                                    }
                                    .buttonStyle(.plain)
                                    .onAppear {
                                        noteImpression(for: coach)
                                        if coach.id == items.last?.id {
                                            Task { await loadMoreIfNeeded() }
                                        }
                                    }
                                }

                                if isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                            }
                            }
                            }
                        }

                        #if DEBUG
                        if let entitlements = store.entitlements {
                            Text("DEBUG · AI \(entitlements.ai.active ? "on" : "off") · Boost \(entitlements.boost.active ? "on" : "off")")
                                .font(TTFont.caption(11))
                                .foregroundStyle(TTColor.inkSubtle)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)
                        }
                        #endif
                    }
                    .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                    .padding(.top, TTModalSheetChrome.contentTopPadding)
                    .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
                }
                .refreshable { await reload(reset: true) }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .ttToast($toast, bottomInset: 28)
            .task {
                guard !didLoad else { return }
                await reload(reset: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttOpenHumanChat)) { _ in
                // Contact succeeded from detail — close discovery so chat can present.
                dismiss()
            }
        }
    }

    /// The real card with placeholder data, so layout matches the content exactly.
    private var coachSkeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<TTLoadTiming.placeholderRows(rowHeight: 150), id: \.self) { _ in
                CoachDiscoveryRow(coach: .placeholder)
            }
        }
        .ttSkeleton()
    }

    private var filterFields: some View {
        VStack(spacing: 12) {
            TTTextField(title: "City", icon: "mappin", text: $cityFilter)
                .onChange(of: cityFilter) { _, _ in scheduleSearch() }
            TTTextField(title: "Specialty", icon: "tag", text: $specialtyFilter)
                .onChange(of: specialtyFilter) { _, _ in scheduleSearch() }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
            Text("No coaches found")
                .font(TTFont.heading(18))
            Text("Try a different search or clear filters.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reload(reset: true)
        }
    }

    private func noteImpression(for coach: CoachListItem) {
        if let me = store.currentUser?.id, !me.isEmpty, me == coach.userId { return }
        CoachImpressionTracker.noteVisible(coachProfileIds: [coach.id])
    }

    @MainActor
    private func reload(reset: Bool) async {
        if reset {
            isLoading = items.isEmpty
            nextCursor = nil
        }
        do {
            let page = try await APIClient.shared.listCoaches(
                q: searchText,
                city: cityFilter,
                specialty: specialtyFilter,
                cursor: reset ? nil : nextCursor,
                limit: 20
            )
            if reset {
                items = page.items
            } else {
                let existing = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            }
            nextCursor = page.nextCursor
            didLoad = true
            if reset { loadFailed = false }
        } catch let error as AppError where error == .unauthorized {
            toast = TTToastMessage(text: error.localizedDescription, style: .error)
        } catch {
            // Shown as the error state (nothing loaded yet) or a quiet notice above the stale list.
            if reset { loadFailed = true }
            didLoad = true
        }
        isLoading = false
        isLoadingMore = false
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard let cursor = nextCursor, !cursor.isEmpty, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        do {
            let page = try await APIClient.shared.listCoaches(
                q: searchText,
                city: cityFilter,
                specialty: specialtyFilter,
                cursor: cursor,
                limit: 20
            )
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t load more",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
        isLoadingMore = false
    }
}

// MARK: - Row

struct CoachDiscoveryRow: View {
    let coach: CoachListItem

    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TTAvatarImage(
                assetName: coach.avatarSymbol.flatMap { TTAvatarCatalog.isAssetName($0) ? $0 : nil },
                systemName: coach.avatarSymbol.flatMap { TTAvatarCatalog.isAssetName($0) ? nil : $0 },
                initials: Self.initials(for: coach.name),
                size: 54
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(coach.name)
                        .font(TTFont.heading(16))
                        .foregroundStyle(TTColor.ink)
                        .lineLimit(1)
                    if coach.isVerified {
                        CoachVerifiedBadge(title: coach.verifiedBadge)
                    }
                    if coach.boostActive {
                        CoachBoostBadge()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TTColor.inkSubtle)
                }

                CoachRatingBadge(ratingAvg: coach.ratingAvg, ratingCount: coach.ratingCount)

                if let featured = coach.featuredPackage {
                    Text("From \(featured.priceLabel)")
                        .font(TTFont.caption(12))
                        .fontWeight(.semibold)
                        .foregroundStyle(TTColor.actionOrange)
                        .accessibilityLabel("From \(featured.priceLabel)")
                } else if coach.packagesCount > 0 {
                    Text("\(coach.packagesCount) package\(coach.packagesCount == 1 ? "" : "s")")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }

                if !coach.headline.isEmpty {
                    Text(coach.headline)
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(2)
                }

                if !coach.city.isEmpty {
                    Label(coach.city, systemImage: "mappin")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }

                if !coach.specialties.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(coach.specialties.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(TTFont.caption(11))
                                .foregroundStyle(TTColor.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private static func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }
}

struct CoachBoostBadge: View {
    var title: String = "Boosted"

    var body: some View {
        Text(title)
            .font(TTFont.caption(10))
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(TTColor.actionOrange)
            .clipShape(Capsule())
            .accessibilityLabel(title == "Boosted" ? "Boosted" : title)
    }
}

/// Trust badge — only when `isVerified == true`.
struct CoachVerifiedBadge: View {
    var title: String? = nil
    var compact: Bool = false

    private var label: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return "Verified"
    }

    var body: some View {
        HStack(spacing: 3) {
            TTIcon(icon: .checkCircle, filled: true, size: compact ? 10 : 12)
            Text(label)
                .font(TTFont.caption(compact ? 9 : 10))
                .fontWeight(.bold)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(Color(hex: 0x2563EB))
        .clipShape(Capsule())
        .accessibilityLabel(label)
    }
}

/// Shared rating chip — `★ 4.7 (23)` or “No ratings”.
struct CoachRatingBadge: View {
    var ratingAvg: Double?
    var ratingCount: Int
    var compact: Bool = false

    private var hasRatings: Bool {
        ratingCount > 0 && ratingAvg != nil
    }

    var body: some View {
        HStack(spacing: 4) {
            TTIcon(icon: .starFull, filled: hasRatings, size: compact ? 11 : 13)
                .foregroundStyle(hasRatings ? TTColor.actionOrange : TTColor.inkSubtle)
            if hasRatings, let avg = ratingAvg {
                Text(String(format: "%.1f", avg))
                    .font(TTFont.caption(compact ? 11 : 12))
                    .fontWeight(.semibold)
                    .foregroundStyle(TTColor.ink)
                Text("(\(ratingCount))")
                    .font(TTFont.caption(compact ? 11 : 12))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Text("No ratings")
                    .font(TTFont.caption(compact ? 11 : 12))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if hasRatings, let avg = ratingAvg {
            let countLabel = ratingCount == 1 ? "1 review" : "\(ratingCount) reviews"
            return String(format: "%.1f out of 5, %@", avg, countLabel)
        }
        return "No ratings"
    }
}

#Preview("Find Coaches") {
    FindCoachesView()
        .ttPreviewTrainee()
}

private extension CoachListItem {
    /// Placeholder card data for the skeleton. Built field by field (no JSON decode, nothing that can fail).
    static let placeholder = CoachListItem(skeleton: ())

    init(skeleton: Void) {
        id = "placeholder"
        trainerId = ""
        userId = ""
        name = "Coach Name"
        headline = "A short headline about this coach that wraps onto two lines."
        city = "City"
        countryCode = ""
        specialties = ["Strength", "Mobility"]
        languages = []
        gymName = nil
        yearsExperience = nil
        coverImageUrl = nil
        avatarSymbol = nil
        boostActive = false
        ratingAvg = 4.8
        ratingCount = 12
        isVerified = false
        verifiedBadge = nil
        packagesCount = 2
        featuredPackage = nil
        updatedAt = .distantPast
    }
}
