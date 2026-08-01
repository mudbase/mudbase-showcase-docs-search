import Foundation
import MudbaseSDK

/// Owns the app's auth state end to end: bootstrap-from-Keychain at launch, falling back to a
/// fresh anonymous guest session, login, register, logout. The SwiftUI equivalent of
/// `../web/src/lib/mudbase-provider.tsx` + `../web/src/hooks/useAuth.ts` combined.
///
/// `user` is effectively always non-nil once bootstrap completes — either a real signed-in
/// `customer` or the anonymous guest — because this app's data model requires public (guest)
/// reads with auth-gated writes, matching the web app's own anonymous-session bootstrap
/// (`mudbase-provider.tsx`'s `establish()` effect, and the verified-live finding that every
/// collection read 401s with zero auth at all — see README "Known limitations"). `user` is only
/// nil if bootstrap couldn't establish *any* session at all (e.g. no network), which `RootView`
/// treats as a real error state rather than "browsing as guest."
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published private(set) var isBootstrapping = true

    private let authGateway: AuthGateway
    private let tokenStore: KeychainTokenStore

    init(config: AppConfig, tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.authGateway = AuthGateway(projectId: config.projectId)
        self.tokenStore = tokenStore
    }

    /// A real, verified, signed-in account — distinct from the always-present anonymous guest
    /// session. Mirrors `../web/src/hooks/useAuth.ts`'s `isAuthenticated`.
    var isSignedIn: Bool { user?.isGuest == false }

    /// Called once at app launch. Configures the shared `AccessTokenCoordinator` unconditionally
    /// (even before any session exists yet) — see that type's doc comment — since it must be
    /// ready before *any* authenticated call in the app, including the anonymous-session
    /// establishment this method itself may perform below. Restores a stored token pair (real or
    /// anonymous) if any, validating it against the session endpoint; a 401 (expired access token)
    /// is transparently refreshed and retried once by the coordinator. Falls back to a fresh
    /// anonymous session when there is nothing stored, or when the stored session turned out to be
    /// truly invalid.
    func bootstrap() async {
        defer { isBootstrapping = false }
        await AccessTokenCoordinator.shared.configure(authGateway: authGateway, tokenStore: tokenStore)

        if let stored = tokenStore.load() {
            MudbaseSDKBootstrap.setAccessToken(stored.accessToken)
            let gateway = authGateway
            do {
                user = try await AccessTokenCoordinator.shared.perform { () async throws(ErrorResponse) in
                    try await gateway.currentUser()
                }
                return
            } catch {
                // Only treat this as "the session is actually invalid" for a 401 that survived
                // the coordinator's own refresh attempt (it only refreshes 401s, and already
                // clears the stored session itself when that refresh fails) — anything else
                // (offline, a transient 5xx) falls through to a fresh anonymous session below
                // rather than being silently swallowed, so a real network problem still surfaces
                // as the "couldn't connect" state instead of quietly landing on a brand-new guest
                // identity that then also fails the same way.
                if case ErrorResponse.error(401, _, _, _) = error {
                    tokenStore.clear()
                    MudbaseSDKBootstrap.clearAccessToken()
                } else {
                    user = nil
                    return
                }
            }
        }

        await establishAnonymousSession()
    }

    private func establishAnonymousSession() async {
        do {
            let result = try await authGateway.loginAnonymous()
            tokenStore.save(.init(accessToken: result.accessToken, refreshToken: result.refreshToken))
            MudbaseSDKBootstrap.setAccessToken(result.accessToken)
            user = try await authGateway.currentUser()
        } catch {
            user = nil
        }
    }

    func login(email: String, password: String) async -> Result<Void, MudbaseAPIError.DisplayableError> {
        do {
            let result = try await authGateway.login(email: email, password: password)
            tokenStore.save(.init(accessToken: result.accessToken, refreshToken: result.refreshToken))
            MudbaseSDKBootstrap.setAccessToken(result.accessToken)
            user = try await authGateway.currentUser()
            return .success(())
        } catch {
            return .failure(MudbaseAPIError.map(error))
        }
    }

    enum RegisterOutcome: Equatable {
        case signedIn
        case verificationRequired(message: String)
        case failure(message: String)
    }

    /// Role is always `customer` — self-signup never exposes a role picker (this app has only the
    /// one role). See README "Known limitations" for why this app has no in-app way to complete
    /// the emailed verification link.
    func register(email: String, password: String, firstName: String, lastName: String, agreedToTerms: Bool) async -> RegisterOutcome {
        do {
            let result = try await authGateway.registerCustomer(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                agreedToTerms: agreedToTerms
            )
            if result.requiresVerification {
                return .verificationRequired(message: "Account created — check your email to verify it, then sign in.")
            }
            guard let session = result.session, let registeredUser = result.user else {
                return .failure(message: "Account created, but we couldn't sign you in automatically. Please sign in.")
            }
            tokenStore.save(.init(accessToken: session.accessToken, refreshToken: session.refreshToken))
            MudbaseSDKBootstrap.setAccessToken(session.accessToken)
            user = registeredUser
            return .signedIn
        } catch {
            let displayable = MudbaseAPIError.map(error)
            if displayable.code == "EMAIL_VERIFICATION_REQUIRED" {
                return .verificationRequired(message: "Account created — check your email to verify it, then sign in.")
            }
            return .failure(message: displayable.message)
        }
    }

    /// Signs out, then immediately re-establishes a fresh anonymous session so browsing keeps
    /// working post-logout — a native app has no "reload the page" moment to fall back on, so this
    /// closes the gap explicitly rather than leaving the app in a null session until the next
    /// launch.
    func logout() async {
        _ = try? await authGateway.logout()
        tokenStore.clear()
        MudbaseSDKBootstrap.clearAccessToken()
        user = nil
        await establishAnonymousSession()
    }
}
