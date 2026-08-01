import SwiftUI

/// Mirrors `../web/src/components/auth/LoginForm.tsx`.
struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel
    var onSwitchToRegister: (() -> Void)?

    init(sessionStore: SessionStore, onSwitchToRegister: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(sessionStore: sessionStore))
        self.onSwitchToRegister = onSwitchToRegister
    }

    var body: some View {
        Form {
            if let errorMessage = viewModel.errorMessage {
                Section { InlineBanner(message: errorMessage) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.username)
                    .emailKeyboard()
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
            }

            Section {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Sign in")
                    }
                }
                .disabled(!viewModel.canSubmit)
            }

            if let onSwitchToRegister {
                Section {
                    Button("New here? Create an account", action: onSwitchToRegister)
                }
            }
        }
        .navigationTitle("Sign in")
    }
}
