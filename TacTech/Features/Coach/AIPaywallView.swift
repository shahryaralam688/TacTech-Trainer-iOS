import StoreKit
import SwiftUI

/// AI Coach Pro paywall (trainee + trainer) — StoreKit 2 purchase + server verify.
struct AIPaywallView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var onUnlocked: (() -> Void)? = nil

    @State private var catalog: [BillingProduct] = []
    @State private var storeProducts: [Product] = []
    @State private var isLoading = true
    @State private var purchasingId: String?
    @State private var isRestoring = false
    @State private var toast: TTToastMessage?
    @State private var loadError: String?

    private let canvas = Color(white: 0.98)
    private let cardFill = Color(red: 243 / 255, green: 243 / 255, blue: 244 / 255)

    private var activeCatalog: [BillingProduct] {
        catalog.filter(\.active).sorted { lhs, rhs in
            periodRank(lhs.billingPeriod) < periodRank(rhs.billingPeriod)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TTModalSheetHeader(
                    title: "AI Coach Pro",
                    subtitle: "Unlimited coaching, form tips, and diet guidance",
                    background: .white
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError, activeCatalog.isEmpty {
                    errorState(loadError)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            heroCard

                            ForEach(activeCatalog) { item in
                                productRow(item)
                            }

                            TTButton(
                                title: "Restore Purchases",
                                style: .secondary,
                                isLoading: isRestoring
                            ) {
                                Task { await restore() }
                            }
                            .accessibilityLabel("Restore Purchases")

                            Text("Subscription renews automatically. Manage in Apple ID settings.")
                                .font(TTFont.caption(11))
                                .foregroundStyle(TTColor.inkSubtle)
                                .frame(maxWidth: .infinity)
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("AI Coach Pro paywall")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(TTColor.actionOrange)
                Text("Unlock AI Coach Pro")
                    .font(TTFont.heading(18))
            }
            Text("Get unlimited coaching replies, form tips, and diet guidance.")
                .font(TTFont.body(14))
                .foregroundStyle(TTColor.inkMuted)

            if let ai = store.aiEntitlement, ai.active, let ends = ai.endsAt {
                Text("Pro · renews \(ends.formatted(date: .abbreviated, time: .omitted))")
                    .font(TTFont.caption(12))
                    .foregroundStyle(Color(hex: 0x22C55E))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func productRow(_ item: BillingProduct) -> some View {
        let sk = storeProduct(for: item)
        let price = sk?.displayPrice
            ?? BillingMoney.format(amountMinor: item.amountMinor, currency: item.currency)
        let period = (item.billingPeriod ?? "month").capitalized
        let isYearly = (item.billingPeriod ?? "").lowercased().contains("year")
        let busy = purchasingId == item.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(TTFont.heading(16))
                        if isYearly {
                            Text("Best value")
                                .font(TTFont.caption(10))
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(TTColor.actionOrange)
                                .clipShape(Capsule())
                        }
                    }
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(TTFont.body(13))
                            .foregroundStyle(TTColor.inkMuted)
                    }
                    Text(period)
                        .font(TTFont.caption(12))
                        .foregroundStyle(TTColor.inkSubtle)
                }
                Spacer(minLength: 8)
                Text(price)
                    .font(TTFont.heading(18))
                    .foregroundStyle(TTColor.actionOrange)
            }

            TTButton(title: "Subscribe", isLoading: busy) {
                Task { await subscribe(item) }
            }
            .disabled(purchasingId != nil || isRestoring)
            .accessibilityLabel("Subscribe, \(item.name), \(price)")
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isYearly ? TTColor.actionOrange.opacity(0.45) : TTColor.line.opacity(0.7), lineWidth: 1)
        )
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text("Couldn’t load plans")
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

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let page = try await APIClient().billingProducts(type: "ai")
            catalog = page.items
            let ids = page.items.compactMap(\.appleProductId)
            storeProducts = try await AIStoreKitService.shared.loadStoreProducts(appleProductIds: ids)
        } catch {
            loadError = error.localizedDescription
            toast = TTToastMessage(
                text: "Couldn’t load plans",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
        isLoading = false
    }

    @MainActor
    private func subscribe(_ item: BillingProduct) async {
        guard purchasingId == nil else { return }
        purchasingId = item.id
        defer { purchasingProductCleared() }

        guard let appleId = item.appleProductId,
              let product = storeProducts.first(where: { $0.id == appleId }) else {
            toast = TTToastMessage(
                text: "Product unavailable",
                style: .error,
                subtitle: "This plan isn’t available in the App Store yet."
            )
            return
        }

        do {
            let outcome = try await AIStoreKitService.shared.purchase(product)
            switch outcome {
            case .userCancelled:
                break
            case .pending:
                toast = TTToastMessage(
                    text: "Purchase pending",
                    style: .error,
                    subtitle: "Ask to Buy requires approval."
                )
            case let .unlocked(me):
                store.aiEntitlement = me
                await store.refreshAIEntitlements()
                toast = TTToastMessage(text: "AI Coach Pro unlocked", style: .success)
                onUnlocked?()
                dismiss()
            }
        } catch let error as AppError where error.isConflict {
            toast = TTToastMessage(
                text: "Subscription linked elsewhere",
                style: .error,
                subtitle: error.localizedDescription
            )
        } catch {
            toast = TTToastMessage(
                text: "Purchase failed",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    @MainActor
    private func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let me = try await AIStoreKitService.shared.restorePurchases()
            store.aiEntitlement = me
            await store.refreshAIEntitlements()
            toast = TTToastMessage(text: "Purchases restored", style: .success)
            if me.active {
                onUnlocked?()
                dismiss()
            }
        } catch let error as AppError where error.isConflict {
            toast = TTToastMessage(
                text: "Subscription linked elsewhere",
                style: .error,
                subtitle: error.localizedDescription
            )
        } catch {
            toast = TTToastMessage(
                text: "Restore failed",
                style: .error,
                subtitle: error.localizedDescription
            )
        }
    }

    private func purchasingProductCleared() {
        purchasingId = nil
    }

    private func storeProduct(for item: BillingProduct) -> Product? {
        guard let id = item.appleProductId else { return nil }
        return storeProducts.first { $0.id == id }
    }

    private func periodRank(_ period: String?) -> Int {
        switch (period ?? "").lowercased() {
        case "month", "monthly": return 0
        case "year", "yearly", "annual": return 1
        default: return 2
        }
    }
}

#Preview("AI Paywall") {
    AIPaywallView()
        .ttPreviewTrainee()
}
