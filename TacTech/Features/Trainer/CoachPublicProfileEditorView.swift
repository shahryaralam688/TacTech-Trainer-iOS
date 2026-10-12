import SwiftUI

/// Trainer public discovery profile — `GET/PUT /me/coach-profile`.
struct CoachPublicProfileEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var headline = ""
    @State private var bio = ""
    @State private var city = ""
    @State private var countryCode = "PK"
    @State private var gymName = ""
    @State private var yearsText = ""
    @State private var coverImageUrl = ""
    @State private var isPublic = false
    @State private var specialties: [String] = []
    @State private var languages: [String] = []
    @State private var specialtyDraft = ""
    @State private var languageDraft = ""
    @State private var loadedName = ""
    @State private var boostActive = false
    @State private var isVerified = false
    @State private var verifiedBadge: String?
    @State private var ratingAvg: Double?
    @State private var ratingCount = 0

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showBoostStore = false
    @State private var showAnalytics = false
    @State private var showVerification = false
    @State private var showPackages = false
    @State private var toast: TTToastMessage?
    @State private var validationHint: String?

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let maxSpecialties = 20
    private let maxLanguages = 20

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(
                    title: "Public profile",
                    subtitle: "Get discovered by trainees",
                    background: .white
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            previewCard

                            if !isPublic {
                                unpublishedBoostBanner
                            }

                            getFeaturedRow
                            packagesRow
                            insightsRow
                            verificationRow

                            Toggle(isOn: $isPublic) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Visible in Find Coaches")
                                        .font(TTFont.heading(15))
                                    Text(isPublic ? "Trainees can find and contact you." : "Draft only — not listed publicly.")
                                        .font(TTFont.caption(12))
                                        .foregroundStyle(TTColor.inkMuted)
                                }
                            }
                            .tint(TTColor.actionOrange)
                            .padding(14)
                            .background(cardFill)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            TTTextField(title: "Headline", icon: "textformat", text: $headline)
                            TTTextField(title: "Bio", icon: "text.alignleft", axis: .vertical, text: $bio)
                            TTTextField(title: "City", icon: "mappin", text: $city)
                            TTTextField(title: "Country code", icon: "globe", text: $countryCode)
                            TTTextField(title: "Gym name", icon: "building.2", text: $gymName)
                            TTTextField(title: "Years experience", icon: "calendar", text: $yearsText)
                            TTTextField(title: "Cover image URL", icon: "photo", text: $coverImageUrl)

                            chipEditor(
                                title: "Specialties",
                                hint: "Add at least one to go public",
                                tags: $specialties,
                                draft: $specialtyDraft,
                                maxCount: maxSpecialties
                            )

                            chipEditor(
                                title: "Languages",
                                hint: "e.g. en, ur",
                                tags: $languages,
                                draft: $languageDraft,
                                maxCount: maxLanguages
                            )

                            if let validationHint {
                                Text(validationHint)
                                    .font(TTFont.caption(12))
                                    .foregroundStyle(Color(hex: 0xEF4444))
                            }

                            TTButton(title: "Save profile", isLoading: isSaving) {
                                Task { await save() }
                            }

                            #if DEBUG
                            if let entitlements = store.entitlements {
                                Text("DEBUG · AI \(entitlements.ai.active ? "active" : "inactive") · Boost \(entitlements.boost.active ? "active" : "inactive")")
                                    .font(TTFont.caption(11))
                                    .foregroundStyle(TTColor.inkSubtle)
                                    .frame(maxWidth: .infinity)
                            }
                            #endif
                        }
                        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                        .padding(.top, TTModalSheetChrome.contentTopPadding)
                        .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
                    }
                }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .ttToast($toast, bottomInset: 28)
            .task { await load() }
            .sheet(isPresented: $showBoostStore) {
                TrainerBoostStoreView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showAnalytics) {
                TrainerCoachAnalyticsView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showVerification) {
                TrainerCoachVerificationView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showPackages) {
                TrainerCoachPackagesView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
        }
    }

    private var unpublishedBoostBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TTColor.actionOrange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Publish your public profile so trainees can see your boost.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.ink)
                Button("Turn on visibility") {
                    isPublic = true
                }
                .font(TTFont.heading(13))
                .foregroundStyle(TTColor.actionOrange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.actionOrange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var getFeaturedRow: some View {
        Button {
            showBoostStore = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 36, height: 36)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Get Featured")
                            .font(TTFont.heading(15))
                            .foregroundStyle(TTColor.ink)
                        if boostActive || store.myBoost?.active == true || store.entitlements?.boost.active == true {
                            CoachBoostBadge()
                        }
                    }
                    Text("Boost ranking in Find Coaches")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(14)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get Featured Boost")
    }

    private var packagesRow: some View {
        Button {
            showPackages = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 36, height: 36)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Packages")
                        .font(TTFont.heading(15))
                        .foregroundStyle(TTColor.ink)
                    Text("Manage listings trainees can inquire about")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(14)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage Packages")
    }

    private var insightsRow: some View {
        Button {
            showAnalytics = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TTColor.actionOrange)
                    .frame(width: 36, height: 36)
                    .background(TTColor.actionOrange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Insights")
                        .font(TTFont.heading(15))
                        .foregroundStyle(TTColor.ink)
                    Text("Views, contacts, and Boost performance")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(14)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discovery Insights")
    }

    private var verificationRow: some View {
        Button {
            showVerification = true
        } label: {
            HStack(spacing: 12) {
                TTIcon(icon: .checkCircle, filled: true, size: 16)
                    .foregroundStyle(Color(hex: 0x2563EB))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0x2563EB).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Verification")
                            .font(TTFont.heading(15))
                            .foregroundStyle(TTColor.ink)
                        if isVerified {
                            CoachVerifiedBadge(title: verifiedBadge, compact: true)
                        }
                    }
                    Text(isVerified ? "You’re a verified coach" : "Get verified — free trust badge")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TTColor.inkSubtle)
            }
            .padding(14)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coach Verification")
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovery preview")
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
                .tracking(0.6)

            HStack(alignment: .top, spacing: 12) {
                TTAvatar(name: loadedName.isEmpty ? (store.currentUser?.name ?? "Coach") : loadedName, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(loadedName.isEmpty ? (store.currentUser?.name ?? "Your name") : loadedName)
                            .font(TTFont.heading(16))
                        if isVerified {
                            CoachVerifiedBadge(title: verifiedBadge, compact: true)
                        }
                        if boostActive {
                            CoachBoostBadge()
                        }
                    }
                    CoachRatingBadge(ratingAvg: ratingAvg, ratingCount: ratingCount, compact: true)
                    Text(headline.nilIfBlank ?? "Your headline")
                        .font(TTFont.body(13))
                        .foregroundStyle(TTColor.inkMuted)
                        .lineLimit(2)
                    Text(city.nilIfBlank ?? "City")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                    if !specialties.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(specialties.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(TTFont.caption(11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
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
            .opacity(isPublic ? 1 : 0.55)
        }
    }

    private func chipEditor(
        title: String,
        hint: String,
        tags: Binding<[String]>,
        draft: Binding<String>,
        maxCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(TTFont.caption(11))
                .foregroundStyle(TTColor.inkMuted)
                .tracking(0.6)
            Text(hint)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkSubtle)

            FlowLayout(spacing: 8) {
                ForEach(tags.wrappedValue, id: \.self) { tag in
                    Button {
                        tags.wrappedValue.removeAll { $0 == tag }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tag)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(cardFill)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Add…", text: draft)
                    .font(TTFont.body(15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: TTSpace.fieldHeight)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(TTColor.line, lineWidth: 1)
                    )

                Button("Add") {
                    addChip(draft: draft, into: tags, max: maxCount)
                }
                .font(TTFont.heading(14))
                .foregroundStyle(TTColor.actionOrange)
                .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TTColor.line.opacity(0.6), lineWidth: 1)
        )
    }

    private func addChip(draft: Binding<String>, into tags: Binding<[String]>, max: Int) {
        let value = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard tags.wrappedValue.count < max else {
            toast = TTToastMessage(text: "Maximum \(max) items", style: .error)
            return
        }
        let lower = value.lowercased()
        guard !tags.wrappedValue.contains(where: { $0.lowercased() == lower }) else {
            draft.wrappedValue = ""
            return
        }
        tags.wrappedValue.append(value)
        draft.wrappedValue = ""
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            let profile = try await APIClient().getMyCoachProfile()
            apply(profile)
        } catch let error as AppError where error.isNotFound {
            toast = TTToastMessage(
                text: "Not available",
                style: .error,
                subtitle: error.localizedDescription
            )
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t load profile",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
        isLoading = false
    }

    private func apply(_ profile: CoachProfileDTO) {
        loadedName = profile.name
        headline = profile.headline
        bio = profile.bio ?? ""
        city = profile.city
        countryCode = profile.countryCode.isEmpty ? "PK" : profile.countryCode
        gymName = profile.gymName ?? ""
        yearsText = profile.yearsExperience.map(String.init) ?? ""
        coverImageUrl = profile.coverImageUrl ?? ""
        isPublic = profile.isPublic ?? false
        specialties = profile.specialties
        languages = profile.languages
        boostActive = profile.boostActive
        isVerified = profile.isVerified
        verifiedBadge = profile.verifiedBadge
        ratingAvg = profile.ratingAvg
        ratingCount = profile.ratingCount
    }

    @MainActor
    private func save() async {
        validationHint = nil
        let trimmedHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedGym = gymName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCover = coverImageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSpecialties = specialties
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanedLanguages = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if trimmedHeadline.count > 80 {
            validationHint = "Headline must be 80 characters or fewer."
            return
        }
        if trimmedBio.count > 2000 {
            validationHint = "Bio must be 2000 characters or fewer."
            return
        }
        if trimmedCountry.count != 2 {
            validationHint = "Country code must be 2 letters (e.g. PK)."
            return
        }

        var years: Int?
        let yearsTrimmed = yearsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !yearsTrimmed.isEmpty {
            guard let parsed = Int(yearsTrimmed), parsed >= 0 else {
                validationHint = "Years experience must be a number ≥ 0."
                return
            }
            years = parsed
        }

        if isPublic {
            if trimmedHeadline.isEmpty {
                validationHint = "Headline is required when public."
                return
            }
            if trimmedCity.isEmpty {
                validationHint = "City is required when public."
                return
            }
            if cleanedSpecialties.isEmpty {
                validationHint = "Add at least one specialty when public."
                return
            }
        }

        let body = CoachProfileUpdateBody(
            headline: trimmedHeadline,
            bio: trimmedBio,
            city: trimmedCity,
            countryCode: trimmedCountry,
            specialties: Array(cleanedSpecialties.prefix(maxSpecialties)),
            languages: Array(cleanedLanguages.prefix(maxLanguages)),
            gymName: trimmedGym.isEmpty ? nil : trimmedGym,
            yearsExperience: years,
            isPublic: isPublic,
            coverImageUrl: trimmedCover.isEmpty ? nil : trimmedCover
        )

        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await APIClient().updateMyCoachProfile(body)
            apply(updated)
            toast = TTToastMessage(text: "Profile saved", style: .success)
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t save",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#Preview("Coach Public Profile Editor") {
    CoachPublicProfileEditorView()
        .ttPreviewTrainer()
}
