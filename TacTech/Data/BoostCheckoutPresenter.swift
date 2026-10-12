import AuthenticationServices
import UIKit

/// Presents Stripe Checkout via `ASWebAuthenticationSession` and returns the callback URL.
final class BoostCheckoutPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = BoostCheckoutPresenter()

    private var session: ASWebAuthenticationSession?

    enum PresentError: LocalizedError, Equatable {
        case invalidURL
        case canceled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid checkout URL."
            case .canceled: "Checkout canceled"
            case .failed(let message): message
            }
        }
    }

    /// Opens Stripe Checkout; completes with `tactech://…` callback URL, or throws on cancel/error.
    @MainActor
    func present(checkoutURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let auth = ASWebAuthenticationSession(
                url: checkoutURL,
                callbackURLScheme: BoostBillingURL.scheme
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: PresentError.canceled)
                    } else {
                        continuation.resume(throwing: PresentError.failed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: PresentError.canceled)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            self.session = auth
            if !auth.start() {
                self.session = nil
                continuation.resume(throwing: PresentError.failed("Could not open checkout."))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? UIWindow()
    }
}
