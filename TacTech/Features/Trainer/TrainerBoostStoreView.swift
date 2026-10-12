import SwiftUI

/// Trainer Boost store — Stripe (USD) + JazzCash / Easypaisa (PKR).
struct TrainerBoostStoreView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var products: [BillingProduct] = []
    @State private var boost: MeBoostDTO?
    @State private var isPublicProfile: Bool?
    @State private var isLoading = true
    @State private var purchasingKey: String?
    @State private var checkoutWarning: String?
    @State private var toast: TTToastMessage?
    @State private var loadError: String?
    @State private var showStatusActions = false
    @State private var showAnalytics = false

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var usdProducts: [BillingProduct] {
        products
            .filter { $0.active && $0.isUSD }
            .sorted { ($0.durationDays ?? 0) < ($1.durationDays ?? 0) }
    }

    private var pkrProducts: [BillingProduct] {
        products
            .filter { $0.active && $0.isPKR }
            .sorted { ($0.durationDays ?? 0) < ($1.durationDays ?? 0) }
    }

    private var isBoostActive: Bool {
        boost?.active == true || store.entitlements?.boost.active == true || store.myBoost?.active == true
    }

    private var isBusy: Bool { purchasingKey != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(
                    title: "Get Featured",
                    subtitle: "Boost your Find Coaches ranking",
                    background: .white
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError, products.isEmpty, boost == nil {
                    errorState(loadError)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            statusCard
                            insightsEntry
                            warningBanners

                            if usdProducts.isEmpty, pkrProducts.isEmpty {
                                emptyProducts
                            } else {
                                if !usdProducts.isEmpty {
                                    sectionHeader(
                                        title: "International (Card)",
                                        subtitle: "Pay with card (Stripe)"
                                    )
                                    ForEach(usdProducts) { product in
                                        productCard(product, providers: stripeProviders(for: product))
                                    }
                                }

                                if !pkrProducts.isEmpty {
                                    sectionHeader(
                                        title: "Pakistan (Mobile wallet)",
                                        subtitle: "Pay with JazzCash or Easypaisa"
                                    )
                                    ForEach(pkrProducts) { product in
                                        productCard(product, providers: walletProviders(for: product))
                                    }
                                }
                            }

                            if showStatusActions || store.pendingBoostCheckout?.hasIdentity == true {
                                pendingActions
                            }

                            historySection
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
            .sheet(isPresented: $showAnalytics) {
                TrainerCoachAnalyticsView()
                    .ttModalSheetPresentation(dragIndicator: .hidden)
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttBoostCheckoutSucceeded)) { _ in
                Task {
                    await load()
                    let ends = boost?.endsAt ?? store.myBoost?.endsAt
                    toast = TTToastMessage(
                        text: successToast(endsAt: ends),
                        style: .success
                    )
                    showStatusActions = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttBoostCheckoutCanceled)) { _ in
                toast = TTToastMessage(text: "Checkout canceled", style: .error)
                purchasingKey = nil
                showStatusActions = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .ttBoostCheckoutFailed)) { note in
                let detail = note.userInfo?["detail"] as? String
                toast = TTToastMessage(
                    text: "Couldn’t confirm Boost",
                    style: .error,
                    subtitle: detail
                )
                purchasingKey = nil
                showStatusActions = true
            }
        }
    }

    // MARK: - Sections

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isBoostActive ? "flame.fill" : "sparkles")
                    .foregroundStyle(TTColor.actionOrange)
                Text(isBoostActive ? "Boost active" : "Boost")
                    .font(TTFont.heading(15))
                if isBoostActive {
                    CoachBoostBadge()
                }
                Spacer(minLength: 0)
            }

            if isBoostActive, let ends = boost?.endsAt ?? store.myBoost?.endsAt {
                Text("Boosted until \(ends.formatted(date: .abbreviated, time: .shortened))")
                    .font(TTFont.heading(18))
                Text(relativeCountdown(until: ends))
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                Text("Get featured at the top of Find Coaches")
                    .font(TTFont.heading(18))
                Text("Trainees see boosted coaches first. Chat, plans, and AI stay free.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var insightsEntry: some View {
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
                    Text("See views, contacts, and Boost ROI")
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

    @ViewBuilder
    private var warningBanners: some View {
        if let checkoutWarning, !checkoutWarning.isEmpty {
            softBanner(text: checkoutWarning)
        } else if isPublicProfile == false {
            softBanner(text: "Publish your public profile so trainees can see your boost.")
        }
    }

    private func softBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TTColor.actionOrange)
            Text(text)
                .font(TTFont.body(13))
                .foregroundStyle(TTColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TTColor.actionOrange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(text)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TTFont.heading(16))
            Text(subtitle)
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
        }
        .padding(.top, 4)
    }

    private var emptyProducts: some View {
        Text("No Boost plans are available right now.")
            .font(TTFont.body(14))
            .foregroundStyle(TTColor.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pendingActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment still processing?")
                .font(TTFont.heading(15))
            Text("If you already paid, check status. Wallet confirmations can take a few seconds.")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkMuted)
            HStack(spacing: 10) {
                TTButton(title: "Check status", style: .secondary, isLoading: isBusy) {
                    Task { await checkPendingStatus() }
                }
                TTButton(title: "Retry", style: .primary, isLoading: isBusy) {
                    Task { await checkPendingStatus() }
                }
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func productCard(_ product: BillingProduct, providers: [BoostPaymentProvider]) -> some View {
        let price = BillingMoney.format(amountMinor: product.amountMinor, currency: product.currency)
        let ctaPrefix = isBoostActive ? "Extend" : "Get"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.name)
                    .font(TTFont.heading(16))
                Spacer()
                Text(price)
                    .font(TTFont.heading(18))
                    .foregroundStyle(TTColor.actionOrange)
            }

            if !product.description.isEmpty {
                Text(product.description)
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            }

            Text("\(product.durationDays ?? 0) days · \((product.tier ?? "featured").capitalized)")
                .font(TTFont.caption(12))
                .foregroundStyle(TTColor.inkSubtle)

            if providers.count == 1, let only = providers.first {
                let key = purchaseKey(product: product, provider: only)
                TTButton(
                    title: only == .stripe
                        ? (isBoostActive ? "Extend Boost" : "Get Boost")
                        : "\(ctaPrefix) · \(only.buttonTitle)",
                    isLoading: purchasingKey == key
                ) {
                    Task { await buy(product, provider: only) }
                }
                .disabled(isBusy)
                .accessibilityLabel("\(ctaPrefix) Boost with \(only.displayName), \(price)")
            } else {
                HStack(spacing: 10) {
                    ForEach(providers) { provider in
                        let key = purchaseKey(product: product, provider: provider)
                        Button {
                            Task { await buy(product, provider: provider) }
                        } label: {
                            HStack(spacing: 6) {
                                if purchasingKey == key {
                                    ProgressView().tint(.white)
                                }
                                Text(provider.buttonTitle)
                                    .font(TTFont.heading(14))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(.white)
                            .background(TTColor.brand)
                            .clipShape(RoundedRectangle(cornerRadius: TTRadius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        .accessibilityLabel("\(ctaPrefix) Boost with \(provider.displayName), \(price)")
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TTColor.line.opacity(0.7), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var historySection: some View {
        let history = boost?.history ?? store.myBoost?.history ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(TTFont.heading(16))

            if history.isEmpty {
                Text("No Boost purchases yet.")
                    .font(TTFont.body(13))
                    .foregroundStyle(TTColor.inkMuted)
            } else {
                ForEach(history) { item in
                    historyRow(item)
                }
            }
        }
    }

    private func historyRow(_ item: BoostHistoryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.productId ?? item.tier ?? "Boost")
                    .font(TTFont.heading(14))
                if let ends = item.endsAt {
                    Text("Until \(ends.formatted(date: .abbreviated, time: .omitted))")
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                } else {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                statusChip(item.status)
                if let minor = item.amountMinor, let currency = item.currency {
                    Text(BillingMoney.format(amountMinor: minor, currency: currency))
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkMuted)
                }
            }
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusChip(_ status: String) -> some View {
        let normalized = status.lowercased()
        let color: Color = {
            switch normalized {
            case "active": return Color(hex: 0x22C55E)
            case "pending": return TTColor.actionOrange
            case "expired": return TTColor.inkMuted
            case "canceled", "cancelled": return Color(hex: 0xEF4444)
            case "refunded": return Color(hex: 0x3B82F6)
            default: return TTColor.inkMuted
            }
        }()

        return Text(normalized.capitalized)
            .font(TTFont.caption(11))
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
            .accessibilityLabel("Status \(normalized)")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text("Couldn’t load Boost")
                .font(TTFont.heading(18))
            Text(message)
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)
                .multilineTextAlignment(.center)
            TTButton(title: "Retry", style: .secondary) {
                Task { await load() }
            }
            .padding(.horizontal, 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    @MainActor
    private func load() async {
        isLoading = products.isEmpty && boost == nil
        loadError = nil
        store.restorePendingBoostFromDisk()
        do {
            async let productsTask = APIClient().billingProducts(type: "boost")
            async let boostTask = APIClient().myBoost()
            async let profileTask = APIClient().getMyCoachProfile()

            let page = try await productsTask
            products = page.items

            do {
                boost = try await boostTask
                store.myBoost = boost
            } catch let error as AppError where error.isNotFound {
                loadError = error.localizedDescription
                toast = TTToastMessage(text: error.localizedDescription, style: .error)
                dismiss()
                return
            }

            if let profile = try? await profileTask {
                isPublicProfile = profile.isPublic ?? false
            }

            await store.refreshEntitlements()
            showStatusActions = store.pendingBoostCheckout?.hasIdentity == true && !(boost?.active == true)
        } catch let error as AppError where error.isNotFound {
            loadError = error.localizedDescription
            toast = TTToastMessage(text: error.localizedDescription, style: .error)
            dismiss()
        } catch {
            loadError = error.localizedDescription
            if products.isEmpty {
                toast = TTToastMessage(
                    text: "Couldn’t load Boost",
                    style: .error,
                    subtitle: error.localizedDescription
                )
            }
        }
        isLoading = false
    }

    @MainActor
    private func buy(_ product: BillingProduct, provider: BoostPaymentProvider) async {
        guard purchasingKey == nil else { return }
        let allowed = product.effectiveProviders
        guard allowed.contains(provider.rawValue) else {
            toast = TTToastMessage(
                text: "Provider not available",
                style: .error,
                subtitle: "\(provider.displayName) isn’t enabled for this plan."
            )
            return
        }

        let key = purchaseKey(product: product, provider: provider)
        purchasingKey = key
        defer { purchasingKey = nil }

        do {
            let checkout = try await APIClient().createBoostCheckout(
                productId: product.id,
                provider: provider.rawValue
            )
            let trimmed = checkout.warning?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                checkoutWarning = trimmed
            }
            store.rememberPendingBoost(from: checkout)
            // Ensure provider is set even if server omits it.
            if store.pendingBoostCheckout?.provider == nil {
                var pending = store.pendingBoostCheckout ?? PendingBoostCheckout()
                pending.provider = provider.rawValue
                store.pendingBoostCheckout = pending
            }

            guard let url = URL(string: checkout.url) else {
                throw AppError.api("Invalid checkout URL.")
            }

            do {
                let callback = try await BoostCheckoutPresenter.shared.present(checkoutURL: url)
                if let outcome = BoostBillingURL.parse(callback) {
                    switch outcome {
                    case .cancel:
                        store.clearPendingBoost()
                        toast = TTToastMessage(text: "Checkout canceled", style: .error)
                        showStatusActions = false
                    case .stripeSuccess(let sessionId):
                        await finishConfirm(
                            checkoutSessionId: sessionId,
                            attemptId: nil,
                            provider: provider.rawValue
                        )
                    case .localSuccess(let attemptId):
                        await finishConfirm(
                            checkoutSessionId: nil,
                            attemptId: attemptId,
                            provider: provider.rawValue
                        )
                    }
                } else if let pending = store.pendingBoostCheckout, pending.hasIdentity {
                    await finishConfirm(
                        checkoutSessionId: pending.checkoutSessionId,
                        attemptId: pending.attemptId,
                        provider: pending.provider ?? provider.rawValue
                    )
                }
            } catch let error as BoostCheckoutPresenter.PresentError where error == .canceled {
                store.clearPendingBoost()
                toast = TTToastMessage(text: "Checkout canceled", style: .error)
                showStatusActions = false
            }
        } catch let error as AppError {
            let title: String
            if case .providerError = error {
                title = "Payment provider error — try again"
            } else {
                title = "Checkout failed"
            }
            toast = TTToastMessage(
                text: title,
                style: .error,
                subtitle: error.localizedDescription
            )
        } catch {
            toast = TTToastMessage(
                text: "Checkout failed",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func finishConfirm(
        checkoutSessionId: String?,
        attemptId: String?,
        provider: String?
    ) async {
        do {
            let dto = try await store.confirmBoostCheckout(
                checkoutSessionId: checkoutSessionId,
                attemptId: attemptId,
                provider: provider,
                retryIfInactive: true
            )
            boost = dto
            if dto.active {
                toast = TTToastMessage(text: successToast(endsAt: dto.endsAt), style: .success)
                showStatusActions = false
            } else {
                toast = TTToastMessage(
                    text: "Payment received — confirming…",
                    style: .error,
                    subtitle: "Tap Check status in a moment."
                )
                showStatusActions = true
            }
        } catch {
            toast = TTToastMessage(
                text: "Couldn’t confirm Boost",
                style: .error,
                subtitle: error.localizedDescription
            )
            showStatusActions = true
        }
    }

    @MainActor
    private func checkPendingStatus() async {
        guard purchasingKey == nil else { return }
        purchasingKey = "status"
        defer { purchasingKey = nil }
        store.restorePendingBoostFromDisk()
        guard let pending = store.pendingBoostCheckout, pending.hasIdentity else {
            await load()
            if boost?.active == true {
                toast = TTToastMessage(text: successToast(endsAt: boost?.endsAt), style: .success)
                showStatusActions = false
            } else {
                toast = TTToastMessage(text: "No pending checkout found", style: .error)
            }
            return
        }
        await finishConfirm(
            checkoutSessionId: pending.checkoutSessionId,
            attemptId: pending.attemptId,
            provider: pending.provider
        )
        await load()
    }

    private func stripeProviders(for product: BillingProduct) -> [BoostPaymentProvider] {
        let list = product.effectiveProviders.compactMap(BoostPaymentProvider.from)
        let stripe = list.filter { $0 == .stripe }
        return stripe.isEmpty ? [.stripe] : stripe
    }

    private func walletProviders(for product: BillingProduct) -> [BoostPaymentProvider] {
        let list = product.effectiveProviders.compactMap(BoostPaymentProvider.from)
        let wallets = list.filter { $0 == .jazzcash || $0 == .easypaisa }
        return wallets.isEmpty ? [.jazzcash, .easypaisa] : wallets
    }

    private func purchaseKey(product: BillingProduct, provider: BoostPaymentProvider) -> String {
        "\(product.id)|\(provider.rawValue)"
    }

    private func successToast(endsAt: Date?) -> String {
        if let endsAt {
            return "Boost is active until \(endsAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "You’re boosted — trainees will see you first"
    }

    private func relativeCountdown(until ends: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        if ends > Date() {
            return "Ends \(formatter.localizedString(for: ends, relativeTo: Date()))"
        }
        return "Ended \(formatter.localizedString(for: ends, relativeTo: Date()))"
    }
}

#Preview("Trainer Boost Store") {
    TrainerBoostStoreView()
        .ttPreviewTrainer()
}
