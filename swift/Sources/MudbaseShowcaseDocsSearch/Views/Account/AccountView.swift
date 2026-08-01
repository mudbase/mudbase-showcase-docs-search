import SwiftUI

/// Shown in the Account tab for a real signed-in user. The reference web app has no dedicated
/// account page of its own (`Header.tsx` puts a bare "Sign out" button next to the nav links) —
/// this screen is the natural native-app home for that same action plus the account identity a
/// `TabView` needs somewhere to live, following the same "the tab that gates sign-in also shows
/// account state once signed in" convention the sibling `mudbase-showcase-social` Swift port uses
/// for its Profile tab.
struct AccountView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let user: AppUser
    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Signed in as") {
                LabeledContent("Name", value: user.displayName)
                LabeledContent("Email", value: user.email)
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        isSigningOut = true
                        await sessionStore.logout()
                        isSigningOut = false
                    }
                } label: {
                    if isSigningOut {
                        ProgressView()
                    } else {
                        Text("Sign out")
                    }
                }
                .disabled(isSigningOut)
            }

            Section {
                Text("Signing out returns you to guest browsing — the library and Ask AI stay usable without an account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Account")
    }
}
