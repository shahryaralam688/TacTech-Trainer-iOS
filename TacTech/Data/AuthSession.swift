import Foundation

/// Timing rules for the launch and sign-in network calls. Change them here only.
enum TTNetworkTiming {
    /// Per-request limit for launch and sign-in calls (a dead or unreachable server fails after this).
    static let launchRequestTimeout: TimeInterval = 15
    /// Total limit for one launch / sign-in call, including any waiting for a connection.
    static let launchResourceTimeout: TimeInterval = 25
    /// The splash shows a quiet "Still connecting…" after this long.
    static let stillConnectingAfter: Duration = .seconds(3)
    /// Splash → "TacTech isn't responding" when the restore is still pending after this long (it keeps running).
    static let serverWaitLimit: Duration = .seconds(8)
    /// Hard cap for the whole launch restore (many sequential calls): then it is cancelled and reported as unreachable.
    static let restoreOverallLimit: Duration = .seconds(30)
    /// Pauses before the automatic retries when the server is not responding; the last value repeats.
    static let serverRetryPauses: [Int] = [3, 6, 12, 30]

    /// A session that fails instead of waiting for connectivity (launch, token refresh, sign-in, sign-up).
    static func failFastConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = launchRequestTimeout
        configuration.timeoutIntervalForResource = launchResourceTimeout
        return configuration
    }
}

/// An HTTP 5xx answer on a launch / sign-in call.
struct LaunchServerError: Error, Equatable { let status: Int }

/// What went wrong on a launch / sign-in call, classified in one place.
enum LaunchFailure: Equatable {
    /// No internet (the device or the network path is offline).
    case offline
    /// The server can't be reached: refused, DNS failure or timeout.
    case unreachable
    /// The server answered with a 5xx (or something unusable).
    case serverError
    /// The server rejected the sign-in (after a failed refresh). The ONLY case that signs the user out.
    case unauthorized

    /// nil for a cancelled request (a superseded attempt).
    static func classify(_ error: Error) -> LaunchFailure? {
        if error is CancellationError { return nil }
        if let app = error as? AppError, app == .unauthorized { return .unauthorized }
        if error is LaunchServerError { return .serverError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return nil
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
                return .offline
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut:
                // No path at all says "offline" even when the system reports a timeout.
                return TTNetworkMonitor.isOnline ? .unreachable : .offline
            default:
                return TTNetworkMonitor.isOnline ? .unreachable : .offline
            }
        }
        return .serverError
    }
}

extension LaunchFailure {
    /// Inline message for sign-in / sign-up / password reset when the call failed on the network (nil otherwise).
    @MainActor
    static func networkMessage(for error: Error) -> String? {
        guard error is URLError || error is LaunchServerError else { return nil }
        let locale = LocalizationController.shared.locale
        switch classify(error) {
        case .offline: return String(localized: "No internet connection.", locale: locale)
        case .unreachable, .serverError: return String(localized: "Can’t reach TacTech right now. Try again.", locale: locale)
        case .unauthorized, nil: return nil
        }
    }
}

/// Process-wide auth refresh — single-flight lock so parallel 401s don't rotate the same refresh twice.
actor AuthTokenRefresher {
    static let shared = AuthTokenRefresher()

    /// Refresh access this many seconds before `expiresIn` / JWT `exp`.
    static let proactiveLeadSeconds: TimeInterval = 60

    private var inFlight: Task<Void, Error>?
    private var proactiveTask: Task<Void, Never>?
    private let decoder = JSONDecoder.tactech
    private let encoder = JSONEncoder.tactech
    // Fail fast: this is on the launch path, so an unreachable server must not hold the splash.
    private let session = URLSession(configuration: TTNetworkTiming.failFastConfiguration())

    /// Refresh only when access is missing expiry metadata or expires within `lead` seconds.
    func refreshIfExpiring(within lead: TimeInterval = AuthTokenRefresher.proactiveLeadSeconds) async throws {
        guard TokenStore.accessNeedsRefresh(within: lead) else { return }
        try await refresh()
    }

    /// Always hit `/auth/refresh` (via single-flight). Used after 401.
    func refresh() async throws {
        if let inFlight {
            try await inFlight.value
            return
        }
        let task = Task<Void, Error> {
            try await Self.performRefresh(
                session: session,
                decoder: decoder,
                encoder: encoder
            )
        }
        inFlight = task
        defer { if inFlight == task { inFlight = nil } }
        do {
            try await task.value
            scheduleProactiveRefresh()
        } catch {
            cancelProactiveRefresh()
            throw error
        }
    }

    func scheduleProactiveRefresh() {
        proactiveTask?.cancel()
        guard TokenStore.refreshToken() != nil else { return }
        guard let expiry = TokenStore.accessExpiresAt() else {
            proactiveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                try? await self?.refreshIfExpiring()
            }
            return
        }
        let fireDelay = expiry.addingTimeInterval(-Self.proactiveLeadSeconds).timeIntervalSinceNow
        if fireDelay <= 0 {
            proactiveTask = Task { [weak self] in
                try? await self?.refreshIfExpiring(within: Self.proactiveLeadSeconds + 30)
            }
            return
        }
        proactiveTask = Task { [weak self] in
            let ns = UInt64(fireDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            try? await self?.refreshIfExpiring(within: Self.proactiveLeadSeconds + 30)
        }
    }

    /// Launch Retry: drop a refresh that is stuck on an unreachable server so the retry sends a fresh request.
    /// Cancelling never touches the stored tokens.
    func cancelInFlightRefresh() {
        inFlight?.cancel()
        inFlight = nil
    }

    func cancelProactiveRefresh() {
        proactiveTask?.cancel()
        proactiveTask = nil
    }

    // MARK: - Network (static so Task body doesn't re-enter actor isolation)

    private static func performRefresh(
        session: URLSession,
        decoder: JSONDecoder,
        encoder: JSONEncoder
    ) async throws {
        guard let refresh = TokenStore.refreshToken(), !refresh.isEmpty else {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        guard let url = URL(string: "/auth/refresh", relativeTo: APIConfig.baseURL)?.absoluteURL else {
            throw AppError.api("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(APIConfig.skipBrowserWarningValue, forHTTPHeaderField: APIConfig.skipBrowserWarningHeader)
        request.httpBody = try encoder.encode(RefreshBody(refreshToken: refresh))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            TokenStore.clear()
            throw AppError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            // A server or gateway error says nothing about the refresh token: keep the tokens, report the error.
            if http.statusCode >= 500 { throw LaunchServerError(status: http.statusCode) }
            TokenStore.clear()
            throw Self.mapRefreshFailure(data: data)
        }

        // Backend returns full auth payload (login shape). Prefer that.
        if let auth = try? decoder.decode(AuthResponse.self, from: data) {
            guard !auth.refreshToken.isEmpty else {
                TokenStore.clear()
                throw AppError.unauthorized
            }
            TokenStore.save(
                accessToken: auth.accessToken,
                refreshToken: auth.refreshToken,
                expiresIn: auth.expiresIn
            )
            return
        }

        if let tokens = try? decoder.decode(TokenResponse.self, from: data) {
            // Rotation is mandatory — never keep the previous refresh.
            guard let newRefresh = tokens.refreshToken, !newRefresh.isEmpty else {
                TokenStore.clear()
                throw AppError.unauthorized
            }
            TokenStore.save(
                accessToken: tokens.accessToken,
                refreshToken: newRefresh,
                expiresIn: tokens.expiresIn
            )
            return
        }

        TokenStore.clear()
        throw AppError.unauthorized
    }

    private static func mapRefreshFailure(data: Data) -> AppError {
        let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { ($0["detail"] as? String) ?? ($0["message"] as? String) }
            ?? String(data: data, encoding: .utf8)
        let lowered = (detail ?? "").lowercased()
        if lowered.contains("revoked") {
            return .api("Please sign in again.")
        }
        if lowered.contains("expired") || lowered.contains("no longer exists") {
            return .api("Please sign in again.")
        }
        return .unauthorized
    }
}

extension TokenStore {
    private static let accessExpiresAtKey = "com.tactech.trainer.accessExpiresAt"

    static func save(accessToken: String, refreshToken: String, expiresIn: Int?) {
        save(accessToken: accessToken, refreshToken: refreshToken)
        let seconds: TimeInterval
        if let expiresIn, expiresIn > 0 {
            seconds = TimeInterval(expiresIn)
        } else if let jwt = jwtRemainingSeconds(from: accessToken) {
            seconds = jwt
        } else {
            seconds = 15 * 60 // backend default ACCESS_TOKEN_EXPIRE_MINUTES
        }
        UserDefaults.standard.set(Date().addingTimeInterval(seconds).timeIntervalSince1970, forKey: accessExpiresAtKey)
    }

    static func accessExpiresAt() -> Date? {
        let stored = UserDefaults.standard.double(forKey: accessExpiresAtKey)
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
        if let token = accessToken(), let remaining = jwtRemainingSeconds(from: token) {
            return Date().addingTimeInterval(remaining)
        }
        return nil
    }

    static func accessNeedsRefresh(within lead: TimeInterval) -> Bool {
        guard accessToken() != nil else { return true }
        guard let expiry = accessExpiresAt() else { return true }
        return expiry.timeIntervalSinceNow <= lead
    }

    static func clearExpiry() {
        UserDefaults.standard.removeObject(forKey: accessExpiresAtKey)
    }

    static func jwtRemainingSeconds(from token: String) -> TimeInterval? {
        guard let exp = jwtClaimExp(from: token) else { return nil }
        return exp.timeIntervalSinceNow
    }

    static func jwtClaimExp(from token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = 4 - payload.count % 4
        if pad < 4 { payload += String(repeating: "=", count: pad) }
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? TimeInterval ?? (obj["exp"] as? Int).map(TimeInterval.init)
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
