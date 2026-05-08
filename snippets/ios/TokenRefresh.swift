import Foundation

/// Sketch of an access-token refresh helper that:
///   • Refreshes only when the access token is within 60 s of expiry.
///   • Coalesces concurrent callers so a burst of API requests triggers
///     a single in-flight refresh (others await the same `Task`).
///   • Falls back to "use as-is" when no refresh token is available
///     (legacy session) instead of forcing a sign-out — the server will
///     reject the stale token and the user is naturally re-authenticated.
///
/// Trimmed-down extract from the project's `AuthManager`. The real
/// implementation also persists the refreshed session to Keychain and
/// publishes state changes to observing views.
@MainActor
final class TokenRefreshCoordinator {

    struct Session {
        var accessToken: String
        var refreshToken: String?
        /// Unix epoch milliseconds when the access token expires.
        var expiresAtMs: Int64

        /// True if the access token is within 60 seconds of expiry.
        var isAccessTokenNearExpiry: Bool {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            return nowMs >= expiresAtMs - 60_000
        }
    }

    private(set) var session: Session?
    private var refreshTask: Task<Session?, Never>?
    private let refreshEndpoint: (_ refreshToken: String) async -> Session?

    init(refreshEndpoint: @escaping (String) async -> Session?) {
        self.refreshEndpoint = refreshEndpoint
    }

    /// Returns a session whose access token is current. Concurrent callers
    /// share the in-flight refresh `Task`.
    func currentValidSession() async -> Session? {
        guard let current = session else { return nil }
        if !current.isAccessTokenNearExpiry { return current }
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            // Legacy session without a refresh token — return the existing
            // session and let the server decide whether to honour it.
            return current
        }
        if let existing = refreshTask {
            return await existing.value
        }
        let task = Task { [weak self] () -> Session? in
            guard let self else { return nil }
            return await self.performRefresh(refreshToken: refreshToken)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh(refreshToken: String) async -> Session? {
        let updated = await refreshEndpoint(refreshToken)
        if let updated {
            session = updated
        }
        return updated
    }
}
