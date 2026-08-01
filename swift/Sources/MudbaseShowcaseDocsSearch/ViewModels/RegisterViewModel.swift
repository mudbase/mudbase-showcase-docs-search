import Foundation

/// Mirrors `../web/src/components/auth/RegisterForm.tsx`. Self-signup is real and complete — this
/// project requires email verification, so success surfaces a "check your inbox" message rather
/// than assuming a session (see README "Known limitations" for why there's no in-app way to
/// complete that link).
@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var agreedToTerms = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var infoMessage: String?

    private let sessionStore: SessionStore
    private static let minimumPasswordLength = 8

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    var canSubmit: Bool {
        !isSubmitting
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
            && password.count >= Self.minimumPasswordLength
            && agreedToTerms
    }

    /// Returns whether the account is signed in immediately (verification not required).
    @discardableResult
    func submit() async -> Bool {
        guard canSubmit else { return false }
        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        switch await sessionStore.register(
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName,
            agreedToTerms: agreedToTerms
        ) {
        case .signedIn:
            return true
        case .verificationRequired(let message):
            infoMessage = message
            return false
        case .failure(let message):
            errorMessage = message
            return false
        }
    }
}
