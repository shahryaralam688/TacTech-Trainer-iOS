import Foundation

/// Fire-and-forget discovery list impressions — debounce, dedupe, 15‑min cooldown.
enum CoachImpressionTracker {
    private static let lock = NSLock()
    private static var pendingIDs = Set<String>()
    private static var flushTask: Task<Void, Never>?
    private static let cooldown: TimeInterval = 15 * 60
    private static let defaultsKey = "tactech.coachImpressions.sentAt"

    static func noteVisible(coachProfileIds: [String], excludeCoachProfileId: String? = nil) {
        let exclude = excludeCoachProfileId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = coachProfileIds.compactMap { raw -> String? in
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            if let exclude, id == exclude { return nil }
            return id
        }
        guard !cleaned.isEmpty else { return }

        lock.lock()
        for id in cleaned {
            pendingIDs.insert(id)
        }
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            await flush()
        }
        lock.unlock()
    }

    private static func flush() async {
        let batch: [String] = {
            lock.lock()
            defer { lock.unlock() }
            let recent = loadRecentSent()
            let now = Date()
            let ids = pendingIDs.filter { id in
                if let last = recent[id], now.timeIntervalSince(last) < cooldown {
                    return false
                }
                return true
            }
            pendingIDs.removeAll()
            return Array(ids.prefix(50))
        }()

        guard !batch.isEmpty else { return }

        do {
            _ = try await APIClient().postCoachImpressions(coachProfileIds: batch, source: "discover_list")
            markSent(batch)
        } catch {
            // Soft-fail — never block discovery UX.
        }
    }

    private static func markSent(_ ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        var recent = loadRecentSent()
        let now = Date()
        for id in ids {
            recent[id] = now
        }
        recent = recent.filter { now.timeIntervalSince($0.value) < cooldown }
        let payload = recent.mapValues { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func loadRecentSent() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [:] }
        guard let payload = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return payload.mapValues { Date(timeIntervalSince1970: $0) }
    }
}
