import SwiftUI

/// Mirrors `../web/src/components/auth/RegisterForm.tsx`. Shows an inline "check your inbox"
/// message on success rather than dismissing the form — this project requires email verification,
/// so a successful register call rarely means "signed in immediately." See `RegisterViewModel`.
struct RegisterView: View {
    @StateObject private var viewModel: RegisterViewModel
    var onSwitchToLogin: (() -> Void)?

    init(sessionStore: SessionStore, onSwitchToLogin: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: RegisterViewModel(sessionStore: sessionStore))
        self.onSwitchToLogin = onSwitchToLogin
    }

    var body: some View {
        Form {
            if let errorMessage = viewModel.errorMessage {
                Section { InlineBanner(message: errorMessage) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if let infoMessage = viewModel.infoMessage {
                Section { InlineBanner(message: infoMessage, style: .info) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("First name", text: $viewModel.firstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $viewModel.lastName)
                    .textContentType(.familyName)
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .emailKeyboard()
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.newPassword)
            }

            Section {
                Toggle("I agree to the Terms of Service and Privacy Policy", isOn: $viewModel.agreedToTerms)
            }

            Section {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Create account")
                    }
                }
                .disabled(!viewModel.canSubmit)
            }

            if let onSwitchToLogin {
                Section {
                    Button("Already have an account? Sign in", action: onSwitchToLogin)
                }
            }
        }
        .navigationTitle("Create account")
    }
}
