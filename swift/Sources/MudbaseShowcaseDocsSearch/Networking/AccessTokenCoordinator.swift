import Foundation
import MudbaseSDK

/// Coordinates the "detect a 401, refresh the access token, retry the call once" policy across
/// every authenticated request in the app — including reads made under the anonymous guest
/// session, not just a signed-in customer's writes (see `SessionStore` doc comments: an anonymous
/// session's token pair carries the same refresh contract as a real one, confirmed in the SDK —
/// `CreateAnonymousSession200Response` has its own `refreshToken`). Every collection read/write in
/// `CollectionsGateway` routes through `perform(_:)` for exactly this reason.
///
/// This is an `actor`, not a plain struct, because the platform's refresh token is single-use (it
/// rotates on every `/api/auth/refresh` call — see `AuthGateway.refresh`). If two authenticated
/// calls each hit a 401 at nearly the same moment, they must not both redeem the same stored
/// refresh token — the second redeem would fail against an already-rotated token.
/// `inFlightRefresh` de-duplicates that race into a single refresh call that every concurrent 401
/// awaits together. Ported verbatim from the sibling `mudbase-showcase-ecommerce`/
/// `mudbase-showcase-social` Swift ports' `Networking/AccessTokenCoordinator.swift`.
actor AccessTokenCoordinator {
    static let shared = AccessTokenCoordinator()

    private var authGateway: AuthGateway?
    private var tokenStore: KeychainTokenStore?
    // Untyped `Error` because the stdlib's typed-throws `Task` initializer only exists for
    // `Failure == any Error` on this toolchain — `asErrorResponse` below narrows back to
    // `ErrorResponse` at every read site so `perform`'s typed-throws signature is unaffected.
    private var inFlightRefresh: Task<String, Error>?

    private init() {}

    /// Called once by `SessionStore.bootstrap()` at launch — see that call site for why it is
    /// guaranteed to run before any other authenticated call in the app can happen.
    func configure(authGateway: AuthGateway, tokenStore: KeychainTokenStore) {
        self.authGateway = authGateway
        self.tokenStore = tokenStore
    }

    /// Runs `operation`. On a 401, refreshes the token pair (de-duplicated across concurrent
    /// callers via `inFlightRefresh`) and retries `operation` exactly once with the new access
    /// token. Any other error is rethrown unchanged. If the refresh itself fails (the refresh
    /// token is also expired or was revoked), the locally stored session is cleared — so a dead
    /// access token never gets reused by a later call — and the *original* 401 is rethrown rather
    /// than whatever error the refresh endpoint produced, since that is the error the caller and
    /// `MudbaseAPIError.map` actually know how to present ("Your session has expired.").
    func perform<T: Sendable>(_ operation: @Sendable () async throws(ErrorResponse) -> T) async throws(ErrorResponse) -> T {
        do {
            return try await operation()
        } catch let firstError {
            guard case ErrorResponse.error(401, _, _, _) = firstError else { throw firstError }
            do {
                _ = try await refreshedAccessToken()
            } catch {
                tokenStore?.clear()
                MudbaseSDKBootstrap.clearAccessToken()
                throw firstError
            }
            return try await operation()
        }
    }

    private func refreshedAccessToken() async throws(ErrorResponse) -> String {
        if let inFlightRefresh {
            do {
                return try await inFlightRefresh.value
            } catch {
                throw Self.asErrorResponse(error)
            }
        }
        guard let authGateway, let tokenStore, let stored = tokenStore.load() else {
            throw ErrorResponse.error(401, nil, nil, MudbaseClientError.missingTokenInResponse)
        }
        let task = Task<String, Error> {
            let result = try await authGateway.refresh(refreshToken: stored.refreshToken)
            tokenStore.save(.init(accessToken: result.accessToken, refreshToken: result.refreshToken))
            MudbaseSDKBootstrap.setAccessToken(result.accessToken)
            return result.accessToken
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        do {
            return try await task.value
        } catch {
            throw Self.asErrorResponse(error)
        }
    }

    private static func asErrorResponse(_ error: Error) -> ErrorResponse {
        if let errorResponse = error as? ErrorResponse { return errorResponse }
        return ErrorResponse.error(-1, nil, nil, error)
    }
}
