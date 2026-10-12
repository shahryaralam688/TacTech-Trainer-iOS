import Foundation

// MARK: - Entitlements (Phase 1: cache only — do not gate AI)

struct EntitlementsDTO: Codable, Equatable {
    var ai: EntitlementSlice
    var boost: EntitlementSlice

    static let inactive = EntitlementsDTO(
        ai: .inactive,
        boost: .inactive
    )
}

struct EntitlementSlice: Codable, Equatable {
    var active: Bool
    var plan: String?
    var tier: String?
    var startsAt: Date?
    var endsAt: Date?
    var source: String?

    static let inactive = EntitlementSlice(
        active: false,
        plan: nil,
        tier: nil,
        startsAt: nil,
        endsAt: nil,
        source: nil
    )

    enum CodingKeys: String, CodingKey {
        case active, plan, tier, startsAt, endsAt, source
    }

    init(
        active: Bool,
        plan: String? = nil,
        tier: String? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        source: String? = nil
    ) {
        self.active = active
        self.plan = plan
        self.tier = tier
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? false
        plan = try? c.decodeIfPresent(String.self, forKey: .plan)
        tier = try? c.decodeIfPresent(String.self, forKey: .tier)
        startsAt = try? c.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try? c.decodeIfPresent(Date.self, forKey: .endsAt)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
    }
}

// MARK: - Coach discovery

/// List row — bio / isPublic usually absent.
struct CoachListItem: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var trainerId: String
    var userId: String
    var name: String
    var headline: String
    var city: String
    var countryCode: String
    var specialties: [String]
    var languages: [String]
    var gymName: String?
    var yearsExperience: Int?
    var coverImageUrl: String?
    var avatarSymbol: String?
    var boostActive: Bool
    var ratingAvg: Double?
    var ratingCount: Int
    var isVerified: Bool
    var verifiedBadge: String?
    var packagesCount: Int
    var featuredPackage: FeaturedPackageSummary?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, trainerId, userId, name, headline, city, countryCode
        case specialties, languages, gymName, yearsExperience
        case coverImageUrl, avatarSymbol, boostActive, ratingAvg, ratingCount
        case isVerified, verifiedBadge, packagesCount, featuredPackage, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        trainerId = (try? c.decodeIfPresent(String.self, forKey: .trainerId)) ?? ""
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        headline = (try? c.decodeIfPresent(String.self, forKey: .headline)) ?? ""
        city = (try? c.decodeIfPresent(String.self, forKey: .city)) ?? ""
        countryCode = (try? c.decodeIfPresent(String.self, forKey: .countryCode)) ?? ""
        specialties = (try? c.decodeIfPresent([String].self, forKey: .specialties)) ?? []
        languages = (try? c.decodeIfPresent([String].self, forKey: .languages)) ?? []
        gymName = try? c.decodeIfPresent(String.self, forKey: .gymName)
        yearsExperience = try? c.decodeIfPresent(Int.self, forKey: .yearsExperience)
        coverImageUrl = try? c.decodeIfPresent(String.self, forKey: .coverImageUrl)
        avatarSymbol = try? c.decodeIfPresent(String.self, forKey: .avatarSymbol)
        boostActive = (try? c.decodeIfPresent(Bool.self, forKey: .boostActive)) ?? false
        ratingAvg = try? c.decodeIfPresent(Double.self, forKey: .ratingAvg)
        ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
        isVerified = (try? c.decodeIfPresent(Bool.self, forKey: .isVerified)) ?? false
        verifiedBadge = try? c.decodeIfPresent(String.self, forKey: .verifiedBadge)
        packagesCount = (try? c.decodeIfPresent(Int.self, forKey: .packagesCount)) ?? 0
        featuredPackage = try? c.decodeIfPresent(FeaturedPackageSummary.self, forKey: .featuredPackage)
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
    }
}

/// Detail / my coach profile (includes bio / isPublic).
struct CoachProfileDTO: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var trainerId: String
    var userId: String
    var name: String
    var headline: String
    var bio: String?
    var city: String
    var countryCode: String
    var specialties: [String]
    var languages: [String]
    var gymName: String?
    var yearsExperience: Int?
    var isPublic: Bool?
    var coverImageUrl: String?
    var avatarSymbol: String?
    var boostActive: Bool
    var ratingAvg: Double?
    var ratingCount: Int
    var isVerified: Bool
    var verifiedBadge: String?
    var packagesCount: Int
    var featuredPackage: FeaturedPackageSummary?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, trainerId, userId, name, headline, bio, city, countryCode
        case specialties, languages, gymName, yearsExperience, isPublic
        case coverImageUrl, avatarSymbol, boostActive, ratingAvg, ratingCount
        case isVerified, verifiedBadge, packagesCount, featuredPackage, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        trainerId = (try? c.decodeIfPresent(String.self, forKey: .trainerId)) ?? ""
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        headline = (try? c.decodeIfPresent(String.self, forKey: .headline)) ?? ""
        bio = try? c.decodeIfPresent(String.self, forKey: .bio)
        city = (try? c.decodeIfPresent(String.self, forKey: .city)) ?? ""
        countryCode = (try? c.decodeIfPresent(String.self, forKey: .countryCode)) ?? "PK"
        specialties = (try? c.decodeIfPresent([String].self, forKey: .specialties)) ?? []
        languages = (try? c.decodeIfPresent([String].self, forKey: .languages)) ?? []
        gymName = try? c.decodeIfPresent(String.self, forKey: .gymName)
        yearsExperience = try? c.decodeIfPresent(Int.self, forKey: .yearsExperience)
        isPublic = try? c.decodeIfPresent(Bool.self, forKey: .isPublic)
        coverImageUrl = try? c.decodeIfPresent(String.self, forKey: .coverImageUrl)
        avatarSymbol = try? c.decodeIfPresent(String.self, forKey: .avatarSymbol)
        boostActive = (try? c.decodeIfPresent(Bool.self, forKey: .boostActive)) ?? false
        ratingAvg = try? c.decodeIfPresent(Double.self, forKey: .ratingAvg)
        ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
        isVerified = (try? c.decodeIfPresent(Bool.self, forKey: .isVerified)) ?? false
        verifiedBadge = try? c.decodeIfPresent(String.self, forKey: .verifiedBadge)
        packagesCount = (try? c.decodeIfPresent(Int.self, forKey: .packagesCount)) ?? 0
        featuredPackage = try? c.decodeIfPresent(FeaturedPackageSummary.self, forKey: .featuredPackage)
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
    }
}

struct CoachListPage: Codable, Equatable {
    var items: [CoachListItem]
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items, nextCursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([CoachListItem].self, forKey: .items)) ?? []
        nextCursor = try? c.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

struct CoachProfileUpdateBody: Encodable {
    var headline: String
    var bio: String
    var city: String
    var countryCode: String
    var specialties: [String]
    var languages: [String]
    var gymName: String?
    var yearsExperience: Int?
    var isPublic: Bool
    var coverImageUrl: String?
}

struct CoachContactBody: Encodable {
    var message: String?
}

struct CoachContactResponse: Codable, Equatable {
    var threadId: String
    var peerUserId: String
    var created: Bool

    enum CodingKeys: String, CodingKey {
        case threadId, peerUserId, created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try c.decode(String.self, forKey: .threadId)
        peerUserId = (try? c.decodeIfPresent(String.self, forKey: .peerUserId)) ?? ""
        created = (try? c.decodeIfPresent(Bool.self, forKey: .created)) ?? false
    }
}

// MARK: - Coach reviews (Phase 5)

struct CoachReview: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var coachProfileId: String
    var stars: Int
    var body: String?
    var authorUserId: String
    var authorName: String
    var createdAt: Date
    var updatedAt: Date
    var isMine: Bool

    enum CodingKeys: String, CodingKey {
        case id, coachProfileId, stars, body, authorUserId, authorName
        case createdAt, updatedAt, isMine
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        coachProfileId = (try? c.decodeIfPresent(String.self, forKey: .coachProfileId)) ?? ""
        stars = (try? c.decodeIfPresent(Int.self, forKey: .stars)) ?? 0
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        authorUserId = (try? c.decodeIfPresent(String.self, forKey: .authorUserId)) ?? ""
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? "Trainee"
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
        isMine = (try? c.decodeIfPresent(Bool.self, forKey: .isMine)) ?? false
    }
}

struct CoachReviewPage: Codable, Equatable {
    var ratingAvg: Double?
    var ratingCount: Int
    var items: [CoachReview]
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case ratingAvg, ratingCount, items, nextCursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingAvg = try? c.decodeIfPresent(Double.self, forKey: .ratingAvg)
        ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
        items = (try? c.decodeIfPresent([CoachReview].self, forKey: .items)) ?? []
        nextCursor = try? c.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

struct CoachReviewBody: Encodable {
    var stars: Int
    var body: String?
}

struct MyCoachReviewResponse: Codable, Equatable {
    var review: CoachReview?

    enum CodingKeys: String, CodingKey {
        case review
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        review = try? c.decodeIfPresent(CoachReview.self, forKey: .review)
    }
}

struct ReviewReportBody: Encodable {
    var reason: String
}

struct ReviewReportResponse: Codable, Equatable {
    var reported: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reported = (try? c.decodeIfPresent(Bool.self, forKey: .reported)) ?? true
    }

    private enum CodingKeys: String, CodingKey { case reported }
}

struct ReviewDeletedResponse: Codable, Equatable {
    var deleted: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deleted = (try? c.decodeIfPresent(Bool.self, forKey: .deleted)) ?? true
    }

    private enum CodingKeys: String, CodingKey { case deleted }
}

// MARK: - Discovery analytics (Phase 6)

enum AnalyticsPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }
}

struct CoachAnalyticsResponse: Codable, Equatable {
    var coachProfileId: String
    var periodDays: Int
    var from: Date
    var to: Date
    var totals: CoachAnalyticsTotals
    var series: [CoachAnalyticsDay]?
    var boost: CoachAnalyticsBoost

    enum CodingKeys: String, CodingKey {
        case coachProfileId, periodDays, from, to, totals, series, boost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coachProfileId = (try? c.decodeIfPresent(String.self, forKey: .coachProfileId)) ?? ""
        periodDays = (try? c.decodeIfPresent(Int.self, forKey: .periodDays)) ?? 30
        from = (try? c.decodeIfPresent(Date.self, forKey: .from)) ?? .distantPast
        to = (try? c.decodeIfPresent(Date.self, forKey: .to)) ?? Date()
        totals = (try? c.decodeIfPresent(CoachAnalyticsTotals.self, forKey: .totals)) ?? .zero
        series = try? c.decodeIfPresent([CoachAnalyticsDay].self, forKey: .series)
        boost = (try? c.decodeIfPresent(CoachAnalyticsBoost.self, forKey: .boost)) ?? .inactive
    }
}

struct CoachAnalyticsTotals: Codable, Equatable {
    var views: Int
    var uniqueViewers: Int
    var impressions: Int
    var contacts: Int
    var contactsCreated: Int
    var ratingAvg: Double?
    var ratingCount: Int
    var boostActiveDays: Int

    static let zero = CoachAnalyticsTotals(
        views: 0,
        uniqueViewers: 0,
        impressions: 0,
        contacts: 0,
        contactsCreated: 0,
        ratingAvg: nil,
        ratingCount: 0,
        boostActiveDays: 0
    )

    enum CodingKeys: String, CodingKey {
        case views, uniqueViewers, impressions, contacts, contactsCreated
        case ratingAvg, ratingCount, boostActiveDays
    }

    init(
        views: Int,
        uniqueViewers: Int,
        impressions: Int,
        contacts: Int,
        contactsCreated: Int,
        ratingAvg: Double?,
        ratingCount: Int,
        boostActiveDays: Int
    ) {
        self.views = views
        self.uniqueViewers = uniqueViewers
        self.impressions = impressions
        self.contacts = contacts
        self.contactsCreated = contactsCreated
        self.ratingAvg = ratingAvg
        self.ratingCount = ratingCount
        self.boostActiveDays = boostActiveDays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        views = (try? c.decodeIfPresent(Int.self, forKey: .views)) ?? 0
        uniqueViewers = (try? c.decodeIfPresent(Int.self, forKey: .uniqueViewers)) ?? 0
        impressions = (try? c.decodeIfPresent(Int.self, forKey: .impressions)) ?? 0
        contacts = (try? c.decodeIfPresent(Int.self, forKey: .contacts)) ?? 0
        contactsCreated = (try? c.decodeIfPresent(Int.self, forKey: .contactsCreated)) ?? 0
        ratingAvg = try? c.decodeIfPresent(Double.self, forKey: .ratingAvg)
        ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
        boostActiveDays = (try? c.decodeIfPresent(Int.self, forKey: .boostActiveDays)) ?? 0
    }
}

struct CoachAnalyticsDay: Codable, Identifiable, Equatable {
    var id: String { date }
    var date: String
    var views: Int
    var uniqueViewers: Int
    var impressions: Int
    var contacts: Int

    enum CodingKeys: String, CodingKey {
        case date, views, uniqueViewers, impressions, contacts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? ""
        views = (try? c.decodeIfPresent(Int.self, forKey: .views)) ?? 0
        uniqueViewers = (try? c.decodeIfPresent(Int.self, forKey: .uniqueViewers)) ?? 0
        impressions = (try? c.decodeIfPresent(Int.self, forKey: .impressions)) ?? 0
        contacts = (try? c.decodeIfPresent(Int.self, forKey: .contacts)) ?? 0
    }

    /// Parsed UTC calendar day for Charts X axis.
    var chartDate: Date? {
        CoachAnalyticsDay.dayFormatter.date(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct CoachAnalyticsBoost: Codable, Equatable {
    var activeNow: Bool
    var endsAt: Date?

    static let inactive = CoachAnalyticsBoost(activeNow: false, endsAt: nil)

    enum CodingKeys: String, CodingKey {
        case activeNow, endsAt
    }

    init(activeNow: Bool, endsAt: Date?) {
        self.activeNow = activeNow
        self.endsAt = endsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeNow = (try? c.decodeIfPresent(Bool.self, forKey: .activeNow)) ?? false
        endsAt = try? c.decodeIfPresent(Date.self, forKey: .endsAt)
    }
}

struct ImpressionsBody: Encodable {
    var coachProfileIds: [String]
    var source: String
}

struct ImpressionsResponse: Codable, Equatable {
    var recorded: Int

    init(recorded: Int) {
        self.recorded = recorded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recorded = (try? c.decodeIfPresent(Int.self, forKey: .recorded)) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case recorded }
}

// MARK: - Coach verification (Phase 7)

struct MeCoachVerification: Codable, Equatable {
    var isVerified: Bool
    var verificationStatus: String
    var verifiedAt: Date?
    var application: VerificationApplication?

    enum CodingKeys: String, CodingKey {
        case isVerified, verificationStatus, verifiedAt, application
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isVerified = (try? c.decodeIfPresent(Bool.self, forKey: .isVerified)) ?? false
        verificationStatus = (try? c.decodeIfPresent(String.self, forKey: .verificationStatus)) ?? "none"
        verifiedAt = try? c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        application = try? c.decodeIfPresent(VerificationApplication.self, forKey: .application)
    }
}

struct VerificationApplication: Codable, Equatable {
    var id: String
    var status: String
    var legalFullName: String
    var countryCode: String
    var attestationAccepted: Bool
    var rejectionReason: String?
    var submittedAt: Date?
    var documents: [VerificationDocument]

    enum CodingKeys: String, CodingKey {
        case id, status, legalFullName, countryCode, attestationAccepted
        case rejectionReason, submittedAt, documents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        legalFullName = (try? c.decodeIfPresent(String.self, forKey: .legalFullName)) ?? ""
        countryCode = (try? c.decodeIfPresent(String.self, forKey: .countryCode)) ?? "PK"
        attestationAccepted = (try? c.decodeIfPresent(Bool.self, forKey: .attestationAccepted)) ?? false
        rejectionReason = try? c.decodeIfPresent(String.self, forKey: .rejectionReason)
        submittedAt = try? c.decodeIfPresent(Date.self, forKey: .submittedAt)
        documents = (try? c.decodeIfPresent([VerificationDocument].self, forKey: .documents)) ?? []
    }
}

struct VerificationDocument: Codable, Identifiable, Equatable {
    var id: String
    var docType: String
    var contentType: String
    var originalFileName: String?
    var createdAt: Date
    var downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, docType, contentType, originalFileName, createdAt, downloadUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        docType = (try? c.decodeIfPresent(String.self, forKey: .docType)) ?? ""
        contentType = (try? c.decodeIfPresent(String.self, forKey: .contentType)) ?? ""
        originalFileName = try? c.decodeIfPresent(String.self, forKey: .originalFileName)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        downloadUrl = try? c.decodeIfPresent(String.self, forKey: .downloadUrl)
    }
}

struct VerifyUploadSlotRequest: Encodable {
    var docType: String
    var contentType: String
    var fileName: String
}

struct VerifyUploadSlot: Codable, Equatable {
    var uploadId: String
    var docType: String
    var uploadUrl: String
    var fileKey: String
    var fileUrl: String
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case uploadId, docType, uploadUrl, fileKey, fileUrl, expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uploadId = try c.decode(String.self, forKey: .uploadId)
        docType = (try? c.decodeIfPresent(String.self, forKey: .docType)) ?? ""
        uploadUrl = try c.decode(String.self, forKey: .uploadUrl)
        fileKey = (try? c.decodeIfPresent(String.self, forKey: .fileKey)) ?? ""
        fileUrl = (try? c.decodeIfPresent(String.self, forKey: .fileUrl)) ?? ""
        expiresAt = (try? c.decodeIfPresent(Date.self, forKey: .expiresAt)) ?? .distantFuture
    }
}

struct VerifyUploadPutResponse: Codable, Equatable {
    var ok: Bool
    var fileKey: String?
    var fileUrl: String?

    enum CodingKeys: String, CodingKey {
        case ok, fileKey, fileUrl
    }

    init(ok: Bool = true, fileKey: String? = nil, fileUrl: String? = nil) {
        self.ok = ok
        self.fileKey = fileKey
        self.fileUrl = fileUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = (try? c.decodeIfPresent(Bool.self, forKey: .ok)) ?? true
        fileKey = try? c.decodeIfPresent(String.self, forKey: .fileKey)
        fileUrl = try? c.decodeIfPresent(String.self, forKey: .fileUrl)
    }
}

struct VerificationDocRef: Encodable {
    var docType: String
    var fileKey: String
    var contentType: String
    var originalFileName: String?
}

struct VerificationSubmitBody: Encodable {
    var legalFullName: String
    var countryCode: String
    var attestationAccepted: Bool
    var documents: [VerificationDocRef]
}

struct VerificationCancelResponse: Codable, Equatable {
    var canceled: Bool
    var verificationStatus: String?

    enum CodingKeys: String, CodingKey {
        case canceled, verificationStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canceled = (try? c.decodeIfPresent(Bool.self, forKey: .canceled)) ?? true
        verificationStatus = try? c.decodeIfPresent(String.self, forKey: .verificationStatus)
    }
}

// MARK: - Coach packages (Phase 8)

struct FeaturedPackageSummary: Codable, Equatable, Hashable {
    var id: String
    var title: String
    var amountMinor: Int
    var currency: String
    var billingPeriod: String

    enum CodingKeys: String, CodingKey {
        case id, title, amountMinor, currency, billingPeriod
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "pkr"
        billingPeriod = (try? c.decodeIfPresent(String.self, forKey: .billingPeriod)) ?? "month"
    }

    var priceLabel: String {
        formatPackagePrice(amountMinor: amountMinor, currency: currency, billingPeriod: billingPeriod)
    }
}

struct CoachPackage: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var coachProfileId: String
    var title: String
    var description: String
    var amountMinor: Int
    var currency: String
    var billingPeriod: String
    var durationDays: Int?
    var includes: [String]
    var delivery: String
    var status: String?
    var isFeatured: Bool
    var sortOrder: Int
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, coachProfileId, title, description, amountMinor, currency, billingPeriod
        case durationDays, includes, delivery, status, isFeatured, sortOrder, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        coachProfileId = (try? c.decodeIfPresent(String.self, forKey: .coachProfileId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        amountMinor = (try? c.decodeIfPresent(Int.self, forKey: .amountMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "pkr"
        billingPeriod = (try? c.decodeIfPresent(String.self, forKey: .billingPeriod)) ?? "month"
        durationDays = try? c.decodeIfPresent(Int.self, forKey: .durationDays)
        includes = (try? c.decodeIfPresent([String].self, forKey: .includes)) ?? []
        delivery = (try? c.decodeIfPresent(String.self, forKey: .delivery)) ?? "hybrid"
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        isFeatured = (try? c.decodeIfPresent(Bool.self, forKey: .isFeatured)) ?? false
        sortOrder = (try? c.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
    }

    var priceLabel: String {
        formatPackagePrice(amountMinor: amountMinor, currency: currency, billingPeriod: billingPeriod)
    }
}

struct CoachPackagePage: Codable, Equatable {
    var items: [CoachPackage]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([CoachPackage].self, forKey: .items)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case items }
}

struct CoachPackageBody: Encodable {
    var title: String
    var description: String
    var amountMinor: Int
    var currency: String
    var billingPeriod: String
    var durationDays: Int?
    var includes: [String]
    var delivery: String
    var status: String
    var isFeatured: Bool
    var sortOrder: Int
}

struct PackageInquireBody: Encodable {
    var message: String?
}

struct PackageInquireResponse: Codable, Equatable {
    var threadId: String
    var peerUserId: String
    var packageId: String
    var created: Bool

    enum CodingKeys: String, CodingKey {
        case threadId, peerUserId, packageId, created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try c.decode(String.self, forKey: .threadId)
        peerUserId = (try? c.decodeIfPresent(String.self, forKey: .peerUserId)) ?? ""
        packageId = (try? c.decodeIfPresent(String.self, forKey: .packageId)) ?? ""
        created = (try? c.decodeIfPresent(Bool.self, forKey: .created)) ?? false
    }
}

/// Display-only package price (PKR paisa / USD cents) + billing period label.
func formatPackagePrice(amountMinor: Int, currency: String, billingPeriod: String) -> String {
    let money = BillingMoney.format(amountMinor: amountMinor, currency: currency)
    switch billingPeriod.lowercased() {
    case "one_time", "onetime", "once":
        return "\(money) one-time"
    case "week", "weekly":
        return "\(money) / week"
    case "month", "monthly":
        return "\(money) / month"
    case "year", "yearly", "annual":
        return "\(money) / year"
    case "custom", "":
        return money
    default:
        return "\(money) / \(billingPeriod.replacingOccurrences(of: "_", with: " "))"
    }
}
