import SwiftUI

/// Shown in the Account tab whenever there is no real signed-in user — i.e. `sessionStore.user` is
/// still the anonymous guest session established at launch (see `SessionStore` doc comments). Only
/// gates the Account tab (and, indirectly, document creation/editing) — the Library and Ask AI
/// tabs are always browsable, matching this app's public-read requirement.
struct AuthGateView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var mode: Mode = .login

    private enum Mode { case register, login }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Docs Search")
                    .font(.title2.bold())
                Text("Every document, search log, and Ask AI ranking on this screen is served by a real Mudbase project.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            Group {
                switch mode {
                case .register:
                    RegisterView(sessionStore: sessionStore, onSwitchToLogin: { mode = .login })
                case .login:
                    LoginView(sessionStore: sessionStore, onSwitchToRegister: { mode = .register })
                }
            }
        }
    }
}
