import Foundation
import StoreKit

/// StoreKit 2 purchase + restore for AI Coach Pro. Always verifies with TacTech before finishing.
@MainActor
final class AIStoreKitService {
    static let shared = AIStoreKitService()

    private var updatesTask: Task<Void, Never>?
    private let api = APIClient()

    enum PurchaseOutcome: Equatable {
        case unlocked(MeAIResponse)
        case userCancelled
        case pending
    }

    func startListeningForUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                await self.handleUpdate(result)
            }
        }
    }

    func stopListeningForUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    /// Loads StoreKit products for the given Apple product IDs.
    func loadStoreProducts(appleProductIds: [String]) async throws -> [Product] {
        let ids = Set(appleProductIds.filter { !$0.isEmpty })
        guard !ids.isEmpty else { return [] }
        return try await Product.products(for: ids)
    }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        case let .success(verification):
            let unlocked = try await verifyAndFinish(verification)
            return .unlocked(unlocked)
        @unknown default:
            return .userCancelled
        }
    }

    /// Collects current entitlements / unfinished transactions and restores via server.
    func restorePurchases() async throws -> MeAIResponse {
        var payloads: [AppleVerifyBody] = []

        for await result in Transaction.currentEntitlements {
            if let body = try? verifyBody(from: result) {
                payloads.append(body)
            }
        }

        // Also sweep unfinished.
        for await result in Transaction.unfinished {
            if let body = try? verifyBody(from: result) {
                payloads.append(body)
            }
        }

        // Deduplicate by transactionId / signed payload.
        var seen = Set<String>()
        payloads = payloads.filter { body in
            let key = body.signedTransaction ?? body.transactionId ?? UUID().uuidString
            return seen.insert(key).inserted
        }

        guard !payloads.isEmpty else {
            throw AppError.validation("No Apple purchases found to restore.")
        }

        let me = try await api.restoreAppleAI(transactions: payloads)
        // Finish verified unfinished transactions.
        for await result in Transaction.unfinished {
            if case let .verified(transaction) = result {
                await transaction.finish()
            }
        }
        return me
    }

    private func handleUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            _ = try await verifyAndFinish(result)
            NotificationCenter.default.post(name: .ttAIEntitlementDidChange, object: nil)
        } catch {
            // Leave unfinished for next launch / restore.
        }
    }

    private func verifyAndFinish(_ verification: VerificationResult<Transaction>) async throws -> MeAIResponse {
        let transaction = try checkVerified(verification)
        let jws = verification.jwsRepresentation
        let me: MeAIResponse
        do {
            me = try await api.verifyAppleAI(signedTransaction: jws, signedRenewalInfo: nil)
        } catch {
            // Fallback IDs if JWS path fails after finish already happened elsewhere.
            me = try await api.verifyAppleAI(
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID)
            )
        }
        await transaction.finish()
        return me
    }

    private func verifyBody(from result: VerificationResult<Transaction>) throws -> AppleVerifyBody {
        _ = try checkVerified(result)
        return AppleVerifyBody(
            signedTransaction: result.jwsRepresentation,
            signedRenewalInfo: nil,
            transactionId: nil,
            originalTransactionId: nil
        )
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw AppError.api("Could not verify Apple purchase.")
        case let .verified(safe):
            return safe
        }
    }
}
