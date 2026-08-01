import Foundation

/// Mirrors `../web/src/components/auth/LoginForm.tsx` + `useAuth.ts`'s `login`.
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    var canSubmit: Bool {
        !isSubmitting && !email.isEmpty && !password.isEmpty
    }

    /// Returns whether sign-in succeeded.
    @discardableResult
    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        switch await sessionStore.login(email: email, password: password) {
        case .success:
            return true
        case .failure(let displayable):
            errorMessage = displayable.code == "EMAIL_VERIFICATION_REQUIRED"
                ? "Please verify your email first — check your inbox for the verification link, then sign in."
                : displayable.message
            return false
        }
    }
}
