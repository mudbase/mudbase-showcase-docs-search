import Foundation
import MudbaseSDK

/// Project end-user, as returned by `GET /api/auth/local/session` — decoded by hand because that
/// endpoint types its `user` field as a raw `JSONValue` rather than a fixed struct: unlike org/
/// platform users, project end-users carry whatever custom roles the project's Multi-Role feature
/// defines, so the generated SDK can't model that shape ahead of time. Ported verbatim from the
/// sibling `mudbase-showcase-social` Swift port's `Models/AppUser.swift` — this app has the same
/// single-role-plus-anonymous-guest shape (role slug `"customer"`, see `AuthGateway`).
struct AppUser: Sendable, Equatable, Identifiable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    /// `nil` for the anonymous guest session; `"customer"` for a real signed-in account (this
    /// app's Multi-Role project has only the one role — see `AuthGateway`'s `appRoleSlug`).
    let customRole: String?
    let emailVerified: Bool
    let isAnonymous: Bool

    var displayName: String {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Guest" : name
    }

    /// Mirrors `../web/src/hooks/useAuth.ts`'s `isAuthenticated`: a "real" signed-in user is one
    /// with an actual application role, not the always-present anonymous guest identity
    /// (`isAnonymous: true`, `customRole: nil`).
    var isGuest: Bool { isAnonymous || customRole == nil }

    init?(json: JSONValue) {
        guard let dict = json.dictionaryValue,
              let id = dict["_id"]?.stringValue ?? dict["id"]?.stringValue
        else {
            return nil
        }
        self.id = id
        self.email = dict["email"]?.stringValue ?? ""
        self.firstName = dict["firstName"]?.stringValue ?? ""
        self.lastName = dict["lastName"]?.stringValue ?? ""
        self.emailVerified = dict["emailVerified"]?.boolValue ?? false
        self.customRole = dict["customRole"]?.stringValue
        self.isAnonymous = dict["isAnonymous"]?.boolValue ?? false
    }

    /// From `RegisterWithRole201Response.user` — used by `SessionStore.register` to build the
    /// signed-in user directly from the register response instead of a follow-up
    /// `getLocalSession` call.
    init?(registered: RegisterWithRole201ResponseUser) {
        guard let id = registered.id else { return nil }
        self.id = id
        self.email = registered.email ?? ""
        self.firstName = registered.firstName ?? ""
        self.lastName = registered.lastName ?? ""
        self.emailVerified = registered.emailVerified ?? false
        self.customRole = registered.customRole
        self.isAnonymous = false
    }
}
