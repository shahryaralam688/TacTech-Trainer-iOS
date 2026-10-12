import SwiftUI

/// Coach profile detail — `GET /coaches/{id}` + trainee Contact → human chat + Phase 5 reviews.
struct CoachDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let coachProfileId: String

    @State private var profile: CoachProfileDTO?
    @State private var isLoading = true
    @State private var isContacting = false
    @State private var showMessageSheet = false
    @State private var contactMessage = ""
    @State private var toast: TTToastMessage?

    // Reviews
    @State private var ratingAvg: Double?
    @State private var ratingCount: Int = 0
    @State private var reviews: [CoachReview] = []
    @State private var reviewsCursor: String?
    @State private var isLoadingReviews = false
    @State private var isLoadingMoreReviews = false
    @State private var myReview: CoachReview?
    @State private var showReviewEditor = false
    @State private var showDeleteConfirm = false
    @State private var reportTarget: CoachReview?
    @State private var reportReason = ""
    @State private var reportPreset = "Spam or fake"
    @State private var isReporting = false
    @State private var isSavingReview = false
    @State private var isDeletingReview = false

    // Packages (Phase 8)
    @State private var packages: [CoachPackage] = []
    @State private var isLoadingPackages = false
    @State private var inquirePackage: CoachPackage?
    @State private var inquireMessage = ""
    @State private var isInquiring = false
    @State private var expandedPackageIDs: Set<String> = []

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let reportPresets = ["Spam or fake", "Offensive language", "Irrelevant", "Other"]

    private var isTrainee: Bool {
        store.session?.role == .trainee
    }

    private var canContact: Bool {
        guard isTrainee, let profile else { return false }
        if let me = store.currentUser?.id, me == profile.userId { return false }
        return true
    }

    private var canWriteReview: Bool {
        guard isTrainee, let profile else { return false }
        if let me = store.currentUser?.id, me == profile.userId { return false }
        return true
    }

    private var canInquire: Bool {
        canContact
    }

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: profile?.name ?? "Coach",
                subtitle: profile?.headline.nilIfBlank,
                background: .white
            )

            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let profile {
                    detailContent(profile)
                } else {
                    VStack(spacing: 12) {
                        Text("Coach not available")
                            .font(TTFont.heading(18))
                        Text("This profile may be private or no longer listed.")
                            .font(TTFont.body(14))
                            .foregroundStyle(TTColor.inkMuted)
                            .multilineTextAlignment(.center)
                        TTButton(title: "Go back", style: .secondary) { dismiss() }
                            .padding(.horizontal, 40)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .ttToast($toast, bottomInset: 28)
        .task {
            await load()
            await loadReviews(reset: true)
            await loadPackages()
            if canWriteReview {
                await loadMyReview()
            }
        }
        .sheet(isPresented: $showMessageSheet) {
            contactMessageSheet
                .ttModalSheetPresentation(detents: [.medium], dragIndicator: .visible)
        }
        .sheet(item: $inquirePackage) { pkg in
            inquireSheet(for: pkg)
                .ttModalSheetPresentation(detents: [.medium], dragIndicator: .visible)
        }
        .sheet(isPresented: $showReviewEditor) {
            CoachReviewEditorSheet(
                existing: myReview,
                isSaving: $isSavingReview,
                onSave: { stars, body in
                    Task { await saveReview(stars: stars, body: body) }
                }
            )
            .ttModalSheetPresentation(detents: [.medium, .large], dragIndicator: .visible)
        }
        .sheet(item: $reportTarget) { review in
            reportSheet(for: review)
                .ttModalSheetPresentation(detents: [.medium], dragIndicator: .visible)
        }
        .confirmationDialog(
            "Delete your review?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteMyReview() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
    }

    @ViewBuilder
    private func detailContent(_ profile: CoachProfileDTO) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    TTAvatarImage(
                        assetName: profile.avatarSymbol.flatMap { TTAvatarCatalog.isAssetName($0) ? $0 : nil },
                        systemName: profile.avatarSymbol.flatMap { TTAvatarCatalog.isAssetName($0) ? nil : $0 },
                        initials: Self.initials(for: profile.name),
                        size: 72
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(profile.name)
                                .font(TTFont.heading(22))
                            if profile.isVerified {
                                CoachVerifiedBadge(title: profile.verifiedBadge)
                            }
                            if profile.boostActive {
                                CoachBoostBadge()
                            }
                        }
                        if !profile.headline.isEmpty {
                            Text(profile.headline)
                                .font(TTFont.body(14))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        CoachRatingBadge(
                            ratingAvg: ratingAvg ?? profile.ratingAvg,
                            ratingCount: ratingCount > 0 ? ratingCount : profile.ratingCount
                        )
                        if let featured = profile.featuredPackage {
                            Text("From \(featured.priceLabel)")
                                .font(TTFont.caption(12))
                                .fontWeight(.semibold)
                                .foregroundStyle(TTColor.actionOrange)
                        } else if profile.packagesCount > 0 {
                            Text("\(profile.packagesCount) package\(profile.packagesCount == 1 ? "" : "s")")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                        locationLine(profile)
                    }
                }

                if let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    sectionCard(title: "About") {
                        Text(bio)
                            .font(TTFont.body(15))
                            .foregroundStyle(TTColor.ink)
                    }
                }

                if !profile.specialties.isEmpty {
                    sectionCard(title: "Specialties") {
                        chipRow(profile.specialties)
                    }
                }

                if !profile.languages.isEmpty {
                    sectionCard(title: "Languages") {
                        chipRow(profile.languages)
                    }
                }

                metaRows(profile)

                packagesSection

                reviewsSection

                if canContact {
                    TTButton(title: "Contact", icon: "bubble.left.and.bubble.right.fill", isLoading: isContacting) {
                        showMessageSheet = true
                    }
                }
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, TTModalSheetChrome.contentTopPadding)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
        }
    }

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Packages")
                .font(TTFont.heading(15))

            if isLoadingPackages && packages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else if packages.isEmpty {
                Text("No packages listed yet.")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(packages) { pkg in
                    packageCard(pkg)
                }
                Text("Prices are set by the coach. Inquire to chat — payment is arranged with your coach.")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func packageCard(_ pkg: CoachPackage) -> some View {
        let expanded = expandedPackageIDs.contains(pkg.id)
        let desc = pkg.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsExpand = desc.count > 140
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pkg.title)
                    .font(TTFont.heading(15))
                    .foregroundStyle(TTColor.ink)
                if pkg.isFeatured {
                    Text("Featured")
                        .font(TTFont.caption(10))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(TTColor.actionOrange)
                        .clipShape(Capsule())
                        .accessibilityLabel("Featured")
                }
                Spacer(minLength: 0)
            }

            Text(pkg.priceLabel)
                .font(TTFont.heading(16))
                .foregroundStyle(TTColor.actionOrange)
                .accessibilityLabel(pkg.priceLabel)

            Text(deliveryLabel(pkg.delivery))
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)

            if !desc.isEmpty {
                Text(expanded || !needsExpand ? desc : String(desc.prefix(140)) + "…")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
                if needsExpand {
                    Button(expanded ? "Show less" : "Show more") {
                        if expanded {
                            expandedPackageIDs.remove(pkg.id)
                        } else {
                            expandedPackageIDs.insert(pkg.id)
                        }
                    }
                    .font(TTFont.heading(12))
                    .foregroundStyle(TTColor.actionOrange)
                    .buttonStyle(.plain)
                }
            }

            if !pkg.includes.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(pkg.includes, id: \.self) { item in
                        Text(item)
                            .font(TTFont.caption(11))
                            .foregroundStyle(TTColor.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(cardFill)
                            .clipShape(Capsule())
                    }
                }
            }

            if canInquire {
                TTButton(title: "Inquire", style: .secondary, isLoading: isInquiring && inquirePackage?.id == pkg.id) {
                    inquireMessage = ""
                    inquirePackage = pkg
                }
                .accessibilityLabel("Inquire about \(pkg.title)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func deliveryLabel(_ delivery: String) -> String {
        switch delivery.lowercased() {
        case "online": return "Online"
        case "in_person": return "In person"
        case "hybrid": return "Hybrid"
        default: return delivery.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func inquireSheet(for pkg: CoachPackage) -> some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: "Inquire",
                subtitle: pkg.title,
                background: .white
            )

            VStack(alignment: .leading, spacing: 16) {
                Text(pkg.priceLabel)
                    .font(TTFont.heading(16))
                    .foregroundStyle(TTColor.actionOrange)

                TTTextField(
                    title: "Message (optional)",
                    icon: "text.bubble",
                    axis: .vertical,
                    text: $inquireMessage
                )

                Text("We’ll open chat with this package context. Payment is arranged with your coach.")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)

                TTButton(title: "Send & open chat", isLoading: isInquiring) {
                    Task { await inquire(package: pkg, message: inquireMessage) }
                }

                TTButton(title: "Open chat without message", style: .secondary, isLoading: isInquiring) {
                    Task { await inquire(package: pkg, message: nil) }
                }
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, TTModalSheetChrome.contentTopPadding)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reviews")
                    .font(TTFont.heading(15))
                Spacer()
                CoachRatingBadge(
                    ratingAvg: ratingAvg,
                    ratingCount: ratingCount,
                    compact: true
                )
            }

            if canWriteReview {
                TTButton(
                    title: myReview == nil ? "Write a review" : "Edit your review",
                    style: .secondary,
                    isLoading: isSavingReview || isDeletingReview
                ) {
                    showReviewEditor = true
                }
            }

            if isLoadingReviews && reviews.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if reviews.isEmpty {
                Text("No reviews yet")
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(reviews) { review in
                        reviewRow(review)
                            .onAppear {
                                if review.id == reviews.last?.id {
                                    Task { await loadMoreReviewsIfNeeded() }
                                }
                            }
                    }
                    if isLoadingMoreReviews {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func reviewRow(_ review: CoachReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                starRow(filled: review.stars, size: 12)
                Spacer(minLength: 8)
                Text(review.createdAt.formatted(.relative(presentation: .named)))
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)
            }

            Text(review.authorName)
                .font(TTFont.heading(13))
                .foregroundStyle(TTColor.ink)

            if let body = review.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
                Text(body)
                    .font(TTFont.body(14))
                    .foregroundStyle(TTColor.inkMuted)
            }

            if review.isMine {
                HStack(spacing: 16) {
                    Button("Edit") {
                        showReviewEditor = true
                    }
                    .font(TTFont.heading(13))
                    .foregroundStyle(TTColor.actionOrange)
                    .accessibilityLabel("Edit")

                    Button("Delete", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .font(TTFont.heading(13))
                    .accessibilityLabel("Delete")
                }
            } else {
                Button {
                    reportPreset = reportPresets[0]
                    reportReason = ""
                    reportTarget = review
                } label: {
                    Label("Report", systemImage: "ellipsis.circle")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Report")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func starRow(filled: Int, size: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { n in
                TTIcon(icon: .starFull, filled: n <= filled, size: size)
                    .foregroundStyle(n <= filled ? TTColor.actionOrange : TTColor.inkSubtle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) out of 5 stars")
    }

    private var contactMessageSheet: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: "Contact coach",
                subtitle: "Optional intro message",
                background: .white
            )

            VStack(alignment: .leading, spacing: 16) {
                TTTextField(
                    title: "Message",
                    icon: "text.bubble",
                    axis: .vertical,
                    text: $contactMessage
                )

                Text("Leave blank to open chat without a message.")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)

                TTButton(title: "Send & open chat", isLoading: isContacting) {
                    Task { await contact(withMessage: contactMessage) }
                }

                TTButton(title: "Open chat without message", style: .secondary, isLoading: isContacting) {
                    Task { await contact(withMessage: nil) }
                }
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, TTModalSheetChrome.contentTopPadding)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    private func reportSheet(for review: CoachReview) -> some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: "Report review",
                subtitle: "Help us keep TacTech trustworthy",
                background: .white
            )

            VStack(alignment: .leading, spacing: 14) {
                ForEach(reportPresets, id: \.self) { preset in
                    Button {
                        reportPreset = preset
                    } label: {
                        HStack {
                            Text(preset)
                                .font(TTFont.body(15))
                                .foregroundStyle(TTColor.ink)
                            Spacer()
                            if reportPreset == preset {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(TTColor.actionOrange)
                            }
                        }
                        .padding(12)
                        .background(cardFill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if reportPreset == "Other" {
                    TTTextField(
                        title: "Reason",
                        icon: "text.alignleft",
                        axis: .vertical,
                        text: $reportReason
                    )
                }

                TTButton(title: "Submit report", isLoading: isReporting) {
                    Task { await submitReport(reviewId: review.id) }
                }
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, TTModalSheetChrome.contentTopPadding)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)

            Spacer(minLength: 0)
        }
        .background(Color.white)
    }

    private func locationLine(_ profile: CoachProfileDTO) -> some View {
        let parts = [profile.city.nilIfBlank, profile.countryCode.nilIfBlank].compactMap { $0 }
        return Group {
            if !parts.isEmpty {
                Label(parts.joined(separator: ", "), systemImage: "mappin")
                    .font(TTFont.caption(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
    }

    private func metaRows(_ profile: CoachProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let gym = profile.gymName?.nilIfBlank {
                metaRow(icon: "building.2", title: "Gym", value: gym)
            }
            if let years = profile.yearsExperience {
                metaRow(icon: "calendar", title: "Experience", value: "\(years) year\(years == 1 ? "" : "s")")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metaRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(TTColor.actionOrange)
                .frame(width: 22)
            Text(title)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            Spacer()
            Text(value)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.ink)
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(TTFont.heading(15))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func chipRow(_ tags: [String]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
    }

    @MainActor
    private func loadPackages() async {
        isLoadingPackages = true
        defer { isLoadingPackages = false }
        do {
            let page = try await APIClient().listCoachPackages(coachProfileId: coachProfileId)
            packages = page.items
        } catch {
            // Soft-fail — header teaser may still show count/featured.
            packages = []
        }
    }

    @MainActor
    private func inquire(package: CoachPackage, message: String?) async {
        guard canInquire else { return }
        isInquiring = true
        defer { isInquiring = false }
        do {
            _ = try await store.inquireCoachPackage(
                coachProfileId: coachProfileId,
                packageId: package.id,
                message: message
            )
            inquirePackage = nil
            dismiss()
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t inquire",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            let dto = try await APIClient().coachDetail(id: coachProfileId)
            profile = dto
            ratingAvg = dto.ratingAvg
            ratingCount = dto.ratingCount
        } catch let error as AppError where error.isNotFound {
            profile = nil
            toast = TTToastMessage(
                text: "Coach not available",
                style: .error,
                subtitle: error.localizedDescription
            )
        } catch {
            profile = nil
            toast = TTToastMessage(
                text: "Couldn’t load coach",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
        isLoading = false
    }

    @MainActor
    private func loadMyReview() async {
        do {
            let response = try await APIClient().myCoachReview(coachProfileId: coachProfileId)
            myReview = response.review
        } catch {
            // Soft-fail — write CTA still available.
        }
    }

    @MainActor
    private func loadReviews(reset: Bool) async {
        if reset {
            isLoadingReviews = reviews.isEmpty
            reviewsCursor = nil
        }
        do {
            let page = try await APIClient().listCoachReviews(
                coachProfileId: coachProfileId,
                cursor: reset ? nil : reviewsCursor,
                limit: 20
            )
            applyReviewPage(page, reset: reset)
        } catch {
            if reset {
                toast = TTToastMessage(
                    text: "Couldn’t load reviews",
                    style: .error,
                    subtitle: error.localizedDescription
                )
            }
        }
        isLoadingReviews = false
        isLoadingMoreReviews = false
    }

    @MainActor
    private func loadMoreReviewsIfNeeded() async {
        guard let cursor = reviewsCursor, !cursor.isEmpty, !isLoadingMoreReviews, !isLoadingReviews else { return }
        isLoadingMoreReviews = true
        do {
            let page = try await APIClient().listCoachReviews(
                coachProfileId: coachProfileId,
                cursor: cursor,
                limit: 20
            )
            applyReviewPage(page, reset: false)
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t load more reviews",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
        isLoadingMoreReviews = false
    }

    private func applyReviewPage(_ page: CoachReviewPage, reset: Bool) {
        ratingAvg = page.ratingAvg
        ratingCount = page.ratingCount
        if reset {
            reviews = page.items
        } else {
            let existing = Set(reviews.map(\.id))
            reviews.append(contentsOf: page.items.filter { !existing.contains($0.id) })
        }
        reviewsCursor = page.nextCursor
        if let mine = page.items.first(where: \.isMine) {
            myReview = mine
        }
    }

    @MainActor
    private func saveReview(stars: Int, body: String?) async {
        isSavingReview = true
        defer { isSavingReview = false }
        let api = APIClient()
        do {
            let saved: CoachReview
            if myReview != nil {
                saved = try await api.updateMyCoachReview(
                    coachProfileId: coachProfileId,
                    stars: stars,
                    body: body
                )
            } else {
                do {
                    saved = try await api.createCoachReview(
                        coachProfileId: coachProfileId,
                        stars: stars,
                        body: body
                    )
                } catch let error as AppError where error.isConflict {
                    saved = try await api.updateMyCoachReview(
                        coachProfileId: coachProfileId,
                        stars: stars,
                        body: body
                    )
                }
            }
            myReview = saved
            showReviewEditor = false
            toast = TTToastMessage(text: "Review saved", style: .success)
            await loadReviews(reset: true)
            if let refreshed = try? await api.coachDetail(id: coachProfileId) {
                profile = refreshed
                ratingAvg = refreshed.ratingAvg
                ratingCount = refreshed.ratingCount
            }
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t save review",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func deleteMyReview() async {
        isDeletingReview = true
        defer { isDeletingReview = false }
        do {
            try await APIClient().deleteMyCoachReview(coachProfileId: coachProfileId)
            myReview = nil
            toast = TTToastMessage(text: "Review deleted", style: .success)
            await loadReviews(reset: true)
            if let refreshed = try? await APIClient().coachDetail(id: coachProfileId) {
                profile = refreshed
                ratingAvg = refreshed.ratingAvg
                ratingCount = refreshed.ratingCount
            }
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t delete review",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func submitReport(reviewId: String) async {
        let reason: String
        if reportPreset == "Other" {
            let trimmed = reportReason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                toast = TTToastMessage(text: "Enter a reason", style: .error)
                return
            }
            reason = trimmed
        } else {
            reason = reportPreset
        }
        isReporting = true
        defer { isReporting = false }
        do {
            _ = try await APIClient().reportCoachReview(reviewId: reviewId, reason: reason)
            reportTarget = nil
            toast = TTToastMessage(text: "Report submitted", style: .success)
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t report",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func contact(withMessage message: String?) async {
        guard canContact else { return }
        isContacting = true
        defer { isContacting = false }
        do {
            _ = try await store.contactCoach(profileId: coachProfileId, message: message)
            showMessageSheet = false
            dismiss()
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t contact coach",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    private static func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }
}

// MARK: - Write / edit sheet

private struct CoachReviewEditorSheet: View {
    let existing: CoachReview?
    @Binding var isSaving: Bool
    var onSave: (Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stars: Int = 5
    @State private var bodyText = ""

    private let maxBody = 1000

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: existing == nil ? "Write a review" : "Edit your review",
                subtitle: "Stars required · comment optional",
                background: .white
            ) {
                Button("Cancel") { dismiss() }
                    .font(TTFont.heading(14))
                    .foregroundStyle(TTColor.inkMuted)
                    .frame(width: TTModalSheetChrome.controlSize, height: TTModalSheetChrome.controlSize)
            }

            VStack(alignment: .leading, spacing: 18) {
                Text("Rating")
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)

                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { n in
                        Button {
                            stars = n
                        } label: {
                            TTIcon(icon: .starFull, filled: n <= stars, size: 32)
                                .foregroundStyle(n <= stars ? TTColor.actionOrange : TTColor.inkSubtle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
                        .accessibilityAddTraits(n <= stars ? .isSelected : [])
                    }
                }

                TTTextField(
                    title: "Comment (optional)",
                    icon: "text.alignleft",
                    axis: .vertical,
                    text: $bodyText
                )

                Text("\(min(bodyText.count, maxBody))/\(maxBody)")
                    .font(TTFont.caption(11))
                    .foregroundStyle(TTColor.inkSubtle)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                TTButton(title: "Save review", isLoading: isSaving) {
                    guard (1...5).contains(stars) else { return }
                    let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let limited = String(trimmed.prefix(maxBody))
                    onSave(stars, limited.isEmpty ? nil : limited)
                }
                .disabled(!(1...5).contains(stars) || isSaving)
            }
            .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
            .padding(.top, TTModalSheetChrome.contentTopPadding)
            .padding(.bottom, TTModalSheetChrome.contentBottomPadding)

            Spacer(minLength: 0)
        }
        .background(Color.white)
        .onAppear {
            if let existing {
                stars = max(1, min(5, existing.stars))
                bodyText = existing.body ?? ""
            } else {
                stars = 5
                bodyText = ""
            }
        }
        .onChange(of: bodyText) { _, newValue in
            if newValue.count > maxBody {
                bodyText = String(newValue.prefix(maxBody))
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview("Coach Detail") {
    NavigationStack {
        CoachDetailView(coachProfileId: "cp1")
    }
    .ttPreviewTrainee()
}
