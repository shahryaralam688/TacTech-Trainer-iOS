import Foundation

// MARK: - Billing products (Boost)

struct BillingProduct: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var type: String
    var name: String
    var description: String
    /// Boost products use days; AI subscriptions often omit this.
    var durationDays: Int?
    var tier: String?
    var appleProductId: String?
    var billingPeriod: String?
    var amountMinor: Int
    var currency: String
    var active: Bool
    /// Boost Phase 4: `stripe` | `jazzcash` | `easypaisa`. Default `[]` if omitted.
    var providers: [String]

    enum CodingKeys: String, CodingKey {
        case id, type, name, description, durationDays, tier
        case appleProductId, billingPeriod, amountMinor, currency, active, providers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "boost"
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? id
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        durationDays = try? c.decodeIfPresent(Int.self, forKey: .durationDays)
        tier = try? c.decodeIfPresent(String.self, forKey: .tier)
        appleProductId = try? c.decodeIfPresent(String.self, forKey: .appleProductId)
        billingPeriod = try? c.decodeIfPresent(String.self, forKey: .billingPeriod)
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "usd"
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? false
        providers = (try? c.decodeIfPresent([String].self, forKey: .providers)) ?? []
    }

    var normalizedCurrency: String { currency.lowercased() }

    var isPKR: Bool { normalizedCurrency == "pkr" }
    var isUSD: Bool { normalizedCurrency == "usd" }

    /// Effective providers — infer stripe for USD when server omits the field.
    var effectiveProviders: [String] {
        if !providers.isEmpty { return providers.map { $0.lowercased() } }
        if isUSD { return ["stripe"] }
        if isPKR { return ["jazzcash", "easypaisa"] }
        return []
    }
}

struct BillingProductPage: Codable, Equatable {
    var items: [BillingProduct]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([BillingProduct].self, forKey: .items)) ?? []
    }
}

// MARK: - Boost checkout

struct BoostCheckoutBody: Encodable {
    var productId: String
    var provider: String?
    var successUrl: String?
    var cancelUrl: String?

    enum CodingKeys: String, CodingKey {
        case productId, provider, successUrl, cancelUrl
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(productId, forKey: .productId)
        try c.encodeIfPresent(provider, forKey: .provider)
        try c.encodeIfPresent(successUrl, forKey: .successUrl)
        try c.encodeIfPresent(cancelUrl, forKey: .cancelUrl)
    }
}

struct BoostCheckoutResponse: Codable, Equatable {
    var checkoutSessionId: String?
    var attemptId: String?
    var provider: String?
    var url: String
    var publishableKey: String?
    var warning: String?

    enum CodingKeys: String, CodingKey {
        case checkoutSessionId, attemptId, provider, url, publishableKey, warning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkoutSessionId = try? c.decodeIfPresent(String.self, forKey: .checkoutSessionId)
        attemptId = try? c.decodeIfPresent(String.self, forKey: .attemptId)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        url = try c.decode(String.self, forKey: .url)
        publishableKey = try? c.decodeIfPresent(String.self, forKey: .publishableKey)
        warning = try? c.decodeIfPresent(String.self, forKey: .warning)
    }
}

struct BoostConfirmBody: Encodable {
    var checkoutSessionId: String?
    var attemptId: String?
    var provider: String?

    enum CodingKeys: String, CodingKey {
        case checkoutSessionId, attemptId, provider
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(checkoutSessionId, forKey: .checkoutSessionId)
        try c.encodeIfPresent(attemptId, forKey: .attemptId)
        try c.encodeIfPresent(provider, forKey: .provider)
    }
}

/// In-memory / UserDefaults pending Boost checkout (Stripe session or local wallet attempt).
struct PendingBoostCheckout: Codable, Equatable {
    var checkoutSessionId: String?
    var attemptId: String?
    var provider: String?

    var hasIdentity: Bool {
        !(checkoutSessionId ?? "").isEmpty || !(attemptId ?? "").isEmpty
    }
}

// MARK: - Me boost

struct MeBoostDTO: Codable, Equatable {
    var active: Bool
    var tier: String?
    var startsAt: Date?
    var endsAt: Date?
    var source: String?
    var productId: String?
    var history: [BoostHistoryItem]

    enum CodingKeys: String, CodingKey {
        case active, tier, startsAt, endsAt, source, productId, history
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? false
        tier = try? c.decodeIfPresent(String.self, forKey: .tier)
        startsAt = try? c.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try? c.decodeIfPresent(Date.self, forKey: .endsAt)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        productId = try? c.decodeIfPresent(String.self, forKey: .productId)
        history = (try? c.decodeIfPresent([BoostHistoryItem].self, forKey: .history)) ?? []
    }
}

struct BoostHistoryItem: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var productId: String?
    var tier: String?
    var status: String
    var startsAt: Date?
    var endsAt: Date?
    var amountMinor: Int?
    var currency: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, productId, tier, status, startsAt, endsAt, amountMinor, currency, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        productId = try? c.decodeIfPresent(String.self, forKey: .productId)
        tier = try? c.decodeIfPresent(String.self, forKey: .tier)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        startsAt = try? c.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try? c.decodeIfPresent(Date.self, forKey: .endsAt)
        amountMinor = try? c.decodeIfPresent(Int.self, forKey: .amountMinor)
        currency = try? c.decodeIfPresent(String.self, forKey: .currency)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
    }
}

// MARK: - AI entitlement (Phase 3)

struct MeAIResponse: Codable, Equatable {
    var active: Bool
    var plan: String?
    var startsAt: Date?
    var endsAt: Date?
    var source: String?
    var freeTeaseRemaining: Int
    var freeTeaseLimit: Int
    /// Optional server badge copy (e.g. "Pro").
    var badgeLabel: String?
    /// Optional full label (e.g. "AI Coach Pro").
    var badgeFullLabel: String?
    /// Optional plan display (e.g. "Monthly").
    var planDisplayName: String?
    /// Optional status string from server.
    var status: String?
    var willRenew: Bool?
    var renewsAt: Date?

    enum CodingKeys: String, CodingKey {
        case active, plan, startsAt, endsAt, source, freeTeaseRemaining, freeTeaseLimit
        case badgeLabel, badgeFullLabel, planDisplayName, status, willRenew, renewsAt
    }

    static let inactive = MeAIResponse(
        active: false,
        plan: nil,
        startsAt: nil,
        endsAt: nil,
        source: nil,
        freeTeaseRemaining: 0,
        freeTeaseLimit: 0
    )

    init(
        active: Bool,
        plan: String? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        source: String? = nil,
        freeTeaseRemaining: Int = 0,
        freeTeaseLimit: Int = 0,
        badgeLabel: String? = nil,
        badgeFullLabel: String? = nil,
        planDisplayName: String? = nil,
        status: String? = nil,
        willRenew: Bool? = nil,
        renewsAt: Date? = nil
    ) {
        self.active = active
        self.plan = plan
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.source = source
        self.freeTeaseRemaining = freeTeaseRemaining
        self.freeTeaseLimit = freeTeaseLimit
        self.badgeLabel = badgeLabel
        self.badgeFullLabel = badgeFullLabel
        self.planDisplayName = planDisplayName
        self.status = status
        self.willRenew = willRenew
        self.renewsAt = renewsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? false
        plan = try? c.decodeIfPresent(String.self, forKey: .plan)
        startsAt = try? c.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try? c.decodeIfPresent(Date.self, forKey: .endsAt)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        freeTeaseRemaining = (try? c.decodeIfPresent(Int.self, forKey: .freeTeaseRemaining)) ?? 0
        freeTeaseLimit = (try? c.decodeIfPresent(Int.self, forKey: .freeTeaseLimit)) ?? 0
        badgeLabel = try? c.decodeIfPresent(String.self, forKey: .badgeLabel)
        badgeFullLabel = try? c.decodeIfPresent(String.self, forKey: .badgeFullLabel)
        planDisplayName = try? c.decodeIfPresent(String.self, forKey: .planDisplayName)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        willRenew = try? c.decodeIfPresent(Bool.self, forKey: .willRenew)
        renewsAt = try? c.decodeIfPresent(Date.self, forKey: .renewsAt)
    }

    /// Compact chip text — never invent Pro when inactive.
    var resolvedBadgeLabel: String {
        let trimmed = badgeLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return "Pro"
    }

    var resolvedFullLabel: String {
        let trimmed = badgeFullLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return "AI Coach Pro"
    }

    var resolvedPlanDisplayName: String {
        let trimmed = planDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        let p = (plan ?? "").lowercased()
        if p.contains("year") { return "Yearly" }
        if p.contains("month") { return "Monthly" }
        if p.contains("week") { return "Weekly" }
        if let plan, !plan.isEmpty { return plan }
        return "Pro"
    }

    /// Settings / profile subtitle when active.
    var activeStatusLine: String {
        var parts = [resolvedFullLabel, resolvedPlanDisplayName]
        if let date = renewsAt ?? endsAt {
            let verb: String
            if willRenew == true {
                verb = "Renews"
            } else if willRenew == false {
                verb = "Ends"
            } else {
                verb = "Ends"
            }
            parts.append("\(verb) \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }
}

struct AppleVerifyBody: Encodable {
    var signedTransaction: String?
    var signedRenewalInfo: String?
    var transactionId: String?
    var originalTransactionId: String?

    enum CodingKeys: String, CodingKey {
        case signedTransaction, signedRenewalInfo, transactionId, originalTransactionId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(signedTransaction, forKey: .signedTransaction)
        try c.encodeIfPresent(signedRenewalInfo, forKey: .signedRenewalInfo)
        try c.encodeIfPresent(transactionId, forKey: .transactionId)
        try c.encodeIfPresent(originalTransactionId, forKey: .originalTransactionId)
    }
}

struct AppleRestoreBody: Encodable {
    var transactions: [AppleVerifyBody]
}

// MARK: - Money

enum BillingMoney {
    static func format(amountMinor: Int, currency: String) -> String {
        let code = currency.uppercased()
        let value = Decimal(amountMinor) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        if code == "PKR" {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
            formatter.currencySymbol = "PKR "
        }
        return formatter.string(from: value as NSDecimalNumber) ?? "\(code) \(value)"
    }
}

// MARK: - Deep links

enum BoostBillingURL {
    static let scheme = "tactech"
    static let successHostPath = "billing/boost/success"
    static let cancelHostPath = "billing/boost/cancel"

    enum Outcome: Equatable {
        /// Stripe Checkout return.
        case stripeSuccess(sessionId: String)
        /// JazzCash / Easypaisa return.
        case localSuccess(attemptId: String)
        case cancel
    }

    /// Parses success (`session_id` / `attempt_id`) or cancel deep links.
    static func parse(_ url: URL) -> Outcome? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let combined = host.isEmpty ? path : (path.isEmpty ? host : "\(host)/\(path)")

        if combined == cancelHostPath || (combined.hasSuffix("/cancel") && combined.contains("billing/boost")) {
            return .cancel
        }
        if combined == successHostPath || (combined.contains("billing/boost") && combined.hasSuffix("success")) {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let attempt = items.first(where: { $0.name == "attempt_id" || $0.name == "attemptId" })?.value,
               !attempt.isEmpty {
                return .localSuccess(attemptId: attempt)
            }
            if let session = items.first(where: {
                $0.name == "session_id" || $0.name == "checkoutSessionId"
            })?.value, !session.isEmpty {
                return .stripeSuccess(sessionId: session)
            }
            return nil
        }
        return nil
    }
}

enum BoostPaymentProvider: String, CaseIterable, Identifiable {
    case stripe
    case jazzcash
    case easypaisa

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stripe: "Card (Stripe)"
        case .jazzcash: "JazzCash"
        case .easypaisa: "Easypaisa"
        }
    }

    var buttonTitle: String {
        switch self {
        case .stripe: "Pay with card"
        case .jazzcash: "JazzCash"
        case .easypaisa: "Easypaisa"
        }
    }

    static func from(_ raw: String) -> BoostPaymentProvider? {
        BoostPaymentProvider(rawValue: raw.lowercased())
    }
}
