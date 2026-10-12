import SwiftUI

/// Trainer manage packages — create / edit / archive (display-only pricing, no checkout).
struct TrainerCoachPackagesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CoachPackage] = []
    @State private var isLoading = true
    @State private var missingProfile = false
    @State private var loadError: String?
    @State private var toast: TTToastMessage?
    @State private var editorPackage: CoachPackage?
    @State private var showCreate = false
    @State private var showProfileEditor = false
    @State private var archiveTarget: CoachPackage?
    @State private var isArchiving = false

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var isTrainer: Bool {
        store.session?.role == .trainer
    }

    private var sortedItems: [CoachPackage] {
        items.sorted { lhs, rhs in
            let lRank = statusRank(lhs.status)
            let rRank = statusRank(rhs.status)
            if lRank != rRank { return lRank < rRank }
            if lhs.isFeatured != rhs.isFeatured { return lhs.isFeatured && !rhs.isFeatured }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(
                    title: "Packages",
                    subtitle: "Listings trainees can inquire about",
                    background: .white
                ) {
                    if isTrainer, !missingProfile {
                        Button {
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(TTColor.actionOrange)
                                .frame(width: TTModalSheetChrome.controlSize, height: TTModalSheetChrome.controlSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add package")
                    }
                }

                if !isTrainer {
                    forbiddenState
                } else if isLoading && items.isEmpty && !missingProfile {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if missingProfile {
                    missingProfileState
                } else if let loadError, items.isEmpty {
                    errorState(loadError)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Prices are set by you. Inquire opens chat — TacTech does not charge for packages.")
                                .font(TTFont.caption(12))
                                .foregroundStyle(TTColor.inkMuted)

                            if sortedItems.isEmpty {
                                emptyState
                            } else {
                                ForEach(sortedItems) { pkg in
                                    packageRow(pkg)
                                }
                            }
                        }
                        .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                        .padding(.top, TTModalSheetChrome.contentTopPadding)
                        .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
                    }
                    .refreshable { await load() }
                }
            }
            .background(canvas.ignoresSafeArea())
            .ttHideSystemNavigationBar()
            .ttToast($toast, bottomInset: 28)
            .task { await load() }
            .sheet(isPresented: $showCreate) {
                CoachPackageEditorSheet(existing: nil) { saved in
                    showCreate = false
                    if let saved {
                        upsert(saved)
                        toast = TTToastMessage(text: "Package saved", style: .success)
                        Task { await load() }
                    }
                }
                .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(item: $editorPackage) { pkg in
                CoachPackageEditorSheet(existing: pkg) { saved in
                    editorPackage = nil
                    if let saved {
                        upsert(saved)
                        toast = TTToastMessage(text: "Package updated", style: .success)
                        Task { await load() }
                    }
                }
                .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .sheet(isPresented: $showProfileEditor) {
                CoachPublicProfileEditorView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .confirmationDialog(
                "Archive this package?",
                isPresented: Binding(
                    get: { archiveTarget != nil },
                    set: { if !$0 { archiveTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Archive", role: .destructive) {
                    if let pkg = archiveTarget {
                        Task { await archive(pkg) }
                    }
                }
                Button("Cancel", role: .cancel) { archiveTarget = nil }
            } message: {
                Text("Archived packages are hidden from trainees.")
            }
        }
    }

    private func packageRow(_ pkg: CoachPackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pkg.title)
                    .font(TTFont.heading(15))
                Spacer(minLength: 8)
                statusChip(pkg.status)
                if pkg.isFeatured {
                    Text("Featured")
                        .font(TTFont.caption(10))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(TTColor.actionOrange)
                        .clipShape(Capsule())
                }
            }

            Text(pkg.priceLabel)
                .font(TTFont.heading(16))
                .foregroundStyle(TTColor.actionOrange)
                .accessibilityLabel(pkg.priceLabel)

            Text(deliveryLabel(pkg.delivery))
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)

            if !pkg.includes.isEmpty {
                Text(pkg.includes.prefix(3).joined(separator: " · "))
                    .font(TTFont.caption(12))
                    .foregroundStyle(TTColor.inkMuted)
                    .lineLimit(2)
            }

            HStack(spacing: 16) {
                Button("Edit") {
                    editorPackage = pkg
                }
                .font(TTFont.heading(13))
                .foregroundStyle(TTColor.actionOrange)
                .accessibilityLabel("Edit package")

                if (pkg.status ?? "").lowercased() != "archived" {
                    Button("Archive", role: .destructive) {
                        archiveTarget = pkg
                    }
                    .font(TTFont.heading(13))
                    .disabled(isArchiving)
                    .accessibilityLabel("Archive package")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statusChip(_ status: String?) -> some View {
        let key = (status ?? "active").lowercased()
        let label: String
        let color: Color
        switch key {
        case "draft":
            label = "Draft"
            color = TTColor.inkMuted
        case "archived":
            label = "Archived"
            color = Color(hex: 0x6B7280)
        default:
            label = "Active"
            color = Color(hex: 0x22C55E)
        }
        return Text(label)
            .font(TTFont.caption(10))
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }

    private func deliveryLabel(_ delivery: String) -> String {
        switch delivery.lowercased() {
        case "online": return "Online"
        case "in_person": return "In person"
        case "hybrid": return "Hybrid"
        default: return delivery.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func statusRank(_ status: String?) -> Int {
        switch (status ?? "active").lowercased() {
        case "active": return 0
        case "draft": return 1
        case "archived": return 2
        default: return 3
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(TTColor.inkMuted)
            Text("Add a package so trainees can inquire")
                .font(TTFont.heading(16))
                .multilineTextAlignment(.center)
            TTButton(title: "Create package") {
                showCreate = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var missingProfileState: some View {
        VStack(spacing: 16) {
            Text("Create your public coach profile first")
                .font(TTFont.heading(18))
                .multilineTextAlignment(.center)
            TTButton(title: "Set up public profile") {
                showProfileEditor = true
            }
            .padding(.horizontal, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var forbiddenState: some View {
        VStack(spacing: 12) {
            Text("Trainer only")
                .font(TTFont.heading(18))
            TTButton(title: "Close", style: .secondary) { dismiss() }
                .padding(.horizontal, 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { dismiss() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn’t load packages")
                .font(TTFont.heading(18))
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            TTButton(title: "Retry") {
                Task { await load() }
            }
            .padding(.horizontal, 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func upsert(_ pkg: CoachPackage) {
        if let idx = items.firstIndex(where: { $0.id == pkg.id }) {
            items[idx] = pkg
        } else {
            items.insert(pkg, at: 0)
        }
    }

    @MainActor
    private func load() async {
        guard isTrainer else {
            isLoading = false
            return
        }
        isLoading = items.isEmpty
        loadError = nil
        missingProfile = false
        do {
            let page = try await APIClient().myCoachPackages()
            items = page.items
        } catch let error as AppError where error == .unauthorized {
            toast = TTToastMessage(text: error.localizedDescription, style: .error)
            dismiss()
        } catch let error as AppError where error.isNotFound {
            items = []
            missingProfile = true
        } catch {
            loadError = error.localizedDescription
            toast = TTToastMessage(
                text: "Couldn’t load packages",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
        isLoading = false
    }

    @MainActor
    private func archive(_ pkg: CoachPackage) async {
        isArchiving = true
        defer {
            isArchiving = false
            archiveTarget = nil
        }
        do {
            let updated = try await APIClient().archiveCoachPackage(id: pkg.id)
            upsert(updated)
            toast = TTToastMessage(text: "Package archived", style: .success)
            await load()
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t archive",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }
}

// MARK: - Create / Edit

private struct CoachPackageEditorSheet: View {
    let existing: CoachPackage?
    var onFinished: (CoachPackage?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var amountMajorText = ""
    @State private var currency = "pkr"
    @State private var billingPeriod = "month"
    @State private var durationText = ""
    @State private var delivery = "hybrid"
    @State private var status = "active"
    @State private var isFeatured = false
    @State private var sortOrderText = "0"
    @State private var includes: [String] = []
    @State private var includeDraft = ""
    @State private var isSaving = false
    @State private var toast: TTToastMessage?
    @State private var validationHint: String?

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)
    private let periods = ["one_time", "week", "month", "year", "custom"]
    private let deliveries = ["online", "in_person", "hybrid"]
    private let statuses = ["active", "draft"]
    private let currencies = ["pkr", "usd"]
    private let maxIncludes = 20

    var body: some View {
        VStack(spacing: 0) {
            TTModalSheetHeader(
                title: existing == nil ? "New package" : "Edit package",
                subtitle: "Display price only — no checkout",
                background: .white
            ) {
                Button("Close") {
                    onFinished(nil)
                    dismiss()
                }
                .font(TTFont.heading(14))
                .foregroundStyle(TTColor.inkMuted)
                .frame(width: TTModalSheetChrome.controlSize, height: TTModalSheetChrome.controlSize)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TTTextField(title: "Title", icon: "textformat", text: $title)
                    TTTextField(title: "Description", icon: "text.alignleft", axis: .vertical, text: $description)

                    TTTextField(title: "Price (major units)", icon: "banknote", text: $amountMajorText)
                    Text(currency.uppercased() == "PKR" ? "e.g. 15000 → PKR 15,000" : "e.g. 99 → $99.00")
                        .font(TTFont.caption(11))
                        .foregroundStyle(TTColor.inkSubtle)

                    pickerRow(title: "Currency", selection: $currency, options: currencies) { $0.uppercased() }
                    pickerRow(title: "Billing period", selection: $billingPeriod, options: periods, label: periodLabel)
                    pickerRow(title: "Delivery", selection: $delivery, options: deliveries, label: deliveryLabel)
                    pickerRow(title: "Status", selection: $status, options: statuses) { $0.capitalized }

                    TTTextField(title: "Duration days (optional)", icon: "calendar", text: $durationText)
                    TTTextField(title: "Sort order", icon: "list.number", text: $sortOrderText)

                    Toggle(isOn: $isFeatured) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Featured package")
                                .font(TTFont.heading(14))
                            Text("Only one featured package. Saving this will clear any previous featured.")
                                .font(TTFont.caption(11))
                                .foregroundStyle(TTColor.inkMuted)
                        }
                    }
                    .tint(TTColor.actionOrange)
                    .padding(14)
                    .background(cardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    includesEditor

                    if let validationHint {
                        Text(validationHint)
                            .font(TTFont.caption(12))
                            .foregroundStyle(Color(hex: 0xEF4444))
                    }

                    TTButton(title: "Save package", isLoading: isSaving) {
                        Task { await save() }
                    }
                }
                .padding(.horizontal, TTModalSheetChrome.horizontalPadding)
                .padding(.top, TTModalSheetChrome.contentTopPadding)
                .padding(.bottom, TTModalSheetChrome.contentBottomPadding)
            }
        }
        .background(canvas.ignoresSafeArea())
        .ttHideSystemNavigationBar()
        .ttToast($toast, bottomInset: 28)
        .onAppear { hydrate() }
    }

    private var includesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Includes")
                .font(TTFont.heading(14))
            FlowLayout(spacing: 8) {
                ForEach(includes, id: \.self) { item in
                    Button {
                        includes.removeAll { $0 == item }
                    } label: {
                        HStack(spacing: 4) {
                            Text(item)
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
                TextField("Add include…", text: $includeDraft)
                    .font(TTFont.body(15))
                    .padding(.horizontal, 14)
                    .frame(height: TTSpace.fieldHeight)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(TTColor.line, lineWidth: 1)
                    )
                Button("Add") { addInclude() }
                    .font(TTFont.heading(14))
                    .foregroundStyle(TTColor.actionOrange)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TTColor.line.opacity(0.6), lineWidth: 1)
        )
    }

    private func pickerRow(
        title: String,
        selection: Binding<String>,
        options: [String],
        label: @escaping (String) -> String = { $0 }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func periodLabel(_ value: String) -> String {
        switch value {
        case "one_time": return "Once"
        case "week": return "Week"
        case "month": return "Month"
        case "year": return "Year"
        case "custom": return "Custom"
        default: return value
        }
    }

    private func deliveryLabel(_ value: String) -> String {
        switch value {
        case "online": return "Online"
        case "in_person": return "In person"
        case "hybrid": return "Hybrid"
        default: return value
        }
    }

    private func hydrate() {
        guard let existing else {
            currency = "pkr"
            billingPeriod = "month"
            delivery = "hybrid"
            status = "active"
            return
        }
        title = existing.title
        description = existing.description
        amountMajorText = String(format: "%g", Double(existing.amountMinor) / 100.0)
        currency = existing.currency.lowercased()
        billingPeriod = existing.billingPeriod.lowercased()
        durationText = existing.durationDays.map(String.init) ?? ""
        delivery = existing.delivery.lowercased()
        status = (existing.status ?? "active").lowercased()
        if status == "archived" { status = "draft" }
        isFeatured = existing.isFeatured
        sortOrderText = String(existing.sortOrder)
        includes = existing.includes
    }

    private func addInclude() {
        let value = includeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard value.count <= 80 else {
            toast = TTToastMessage(text: "Each include must be 80 characters or fewer", style: .error)
            return
        }
        guard includes.count < maxIncludes else {
            toast = TTToastMessage(text: "Maximum \(maxIncludes) includes", style: .error)
            return
        }
        guard !includes.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
            includeDraft = ""
            return
        }
        includes.append(value)
        includeDraft = ""
    }

    @MainActor
    private func save() async {
        validationHint = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationHint = "Title is required."
            return
        }
        guard trimmedTitle.count <= 80 else {
            validationHint = "Title must be 80 characters or fewer."
            return
        }
        let normalizedMajor = amountMajorText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let major = Double(normalizedMajor), major >= 0 else {
            validationHint = "Enter a valid price."
            return
        }
        let amountMinor = Int((major * 100).rounded())
        var duration: Int?
        let durationTrimmed = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !durationTrimmed.isEmpty {
            guard let parsed = Int(durationTrimmed), parsed >= 0 else {
                validationHint = "Duration days must be a number ≥ 0."
                return
            }
            duration = parsed
        }
        let sortOrder = Int(sortOrderText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        let body = CoachPackageBody(
            title: trimmedTitle,
            description: trimmedDesc,
            amountMinor: amountMinor,
            currency: currency.lowercased(),
            billingPeriod: billingPeriod.lowercased(),
            durationDays: duration,
            includes: Array(includes.prefix(maxIncludes)),
            delivery: delivery.lowercased(),
            status: status.lowercased(),
            isFeatured: isFeatured,
            sortOrder: sortOrder
        )

        isSaving = true
        defer { isSaving = false }
        do {
            let api = APIClient()
            let saved: CoachPackage
            if let existing {
                saved = try await api.updateCoachPackage(id: existing.id, body)
            } else {
                saved = try await api.createCoachPackage(body)
            }
            onFinished(saved)
            dismiss()
        } catch let error as AppError where error.isConflict {
            toast = TTToastMessage(text: error.localizedDescription, style: .error)
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t save package",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }
}

#Preview("Manage Packages") {
    TrainerCoachPackagesView()
        .ttPreviewTrainer()
}
