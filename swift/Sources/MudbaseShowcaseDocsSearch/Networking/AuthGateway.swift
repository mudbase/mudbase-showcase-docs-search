import Foundation
import MudbaseSDK

/// This project ships Mudbase's single default starter application role — slug "customer",
/// confirmed live against `cloud.mudbase.dev` for this exact project (signup against `"user"`
/// 404s with "Role not found," signup against `"customer"` succeeds — same finding as the sibling
/// `mudbase-showcase-social` app).
private let appRoleSlug = "customer"

/// Thin wrapper over `AuthenticationAPI` + `MultiRoleFeatureAPI`'s async/await calls. Kept separate
/// from `SessionStore` (which owns observable app state) so the actual network calls stay
/// unit-testable independent of SwiftUI/Observation. Ported from the sibling
/// `mudbase-showcase-social` Swift port's `Networking/AuthGateway.swift` — this app has the exact
/// same "auth-gated writes, public reads via an anonymous guest session" shape, verified live: every
/// collection read here 401s with zero auth at all, even with the project's own `pk_` publishable
/// key (see this package's README "Known limitations").
struct AuthGateway {
    let projectId: String

    struct LoginResult {
        let accessToken: String
        let refreshToken: String
    }

    struct RegisterResult {
        /// True when the project requires email verification before a session is issued — in
        /// that case `session`/`user` are both `nil` and the caller shows a "check your email"
        /// message instead.
        let requiresVerification: Bool
        let session: LoginResult?
        let user: AppUser?
    }

    /// `POST /api/auth/anonymous` — establishes a guest session (role: viewer, customRole: nil,
    /// isAnonymous: true) so public reads resolve without forcing signup.
    func loginAnonymous() async throws(ErrorResponse) -> LoginResult {
        let response = try await AuthenticationAPI.createAnonymousSession(
            createAnonymousSessionRequest: CreateAnonymousSessionRequest(projectId: projectId)
        )
        guard let token = response.token, let refreshToken = response.refreshToken else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.missingTokenInResponse)
        }
        return LoginResult(accessToken: token, refreshToken: refreshToken)
    }

    /// `POST /api/auth/local/signup/{role}` — always `role: "customer"` (self-signup never exposes
    /// a role picker; this app has only the one role).
    func registerCustomer(email: String, password: String, firstName: String, lastName: String, agreedToTerms: Bool) async throws(ErrorResponse) -> RegisterResult {
        let response = try await MultiRoleFeatureAPI.registerWithRole(
            role: appRoleSlug,
            registerWithRoleRequest: RegisterWithRoleRequest(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                projectId: projectId,
                agreedToTerms: agreedToTerms
            )
        )
        if response.requireVerification == true {
            return RegisterResult(requiresVerification: true, session: nil, user: nil)
        }
        guard let token = response.token,
              let refreshToken = response.refreshToken,
              let responseUser = response.user,
              let user = AppUser(registered: responseUser)
        else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.missingTokenInResponse)
        }
        return RegisterResult(requiresVerification: false, session: LoginResult(accessToken: token, refreshToken: refreshToken), user: user)
    }

    /// `POST /api/auth/local/login`.
    func login(email: String, password: String) async throws(ErrorResponse) -> LoginResult {
        let response = try await AuthenticationAPI.loginLocalUser(
            loginLocalUserRequest: LoginLocalUserRequest(email: email, password: password, projectId: projectId)
        )
        guard let token = response.token, let refreshToken = response.refreshToken else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.missingTokenInResponse)
        }
        return LoginResult(accessToken: token, refreshToken: refreshToken)
    }

    /// `GET /api/auth/local/session` — the only call that returns this project's custom role
    /// (`customer`) and the anonymous-session flag together.
    func currentUser() async throws(ErrorResponse) -> AppUser {
        let response = try await AuthenticationAPI.getLocalSession(projectId: projectId)
        guard let userJSON = response.user, let user = AppUser(json: userJSON) else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.malformedSessionUser)
        }
        return user
    }

    /// `POST /api/auth/refresh` — rotates the refresh token on every use (platform-enforced,
    /// single-use); the caller is responsible for persisting the new pair.
    func refresh(refreshToken: String) async throws(ErrorResponse) -> LoginResult {
        let response = try await AuthenticationAPI.refreshToken(refreshTokenRequest: RefreshTokenRequest(refreshToken: refreshToken))
        guard let token = response.token, let newRefreshToken = response.refreshToken else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.missingTokenInResponse)
        }
        return LoginResult(accessToken: token, refreshToken: newRefreshToken)
    }

    /// `POST /api/auth/local/logout` — best-effort; callers clear local state regardless of outcome.
    func logout() async throws(ErrorResponse) {
        _ = try await AuthenticationAPI.logoutLocalUser()
    }
}
