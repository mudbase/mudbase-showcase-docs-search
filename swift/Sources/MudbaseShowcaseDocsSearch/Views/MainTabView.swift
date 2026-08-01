import SwiftUI

/// Three tabs: Library (always browsable, real or guest), Ask AI (same), and Account (the
/// signed-in user's own account info, or the sign-in screen while still a guest — see
/// `AccountTabView`).
struct MainTabView: View {
    let config: AppConfig
    let user: AppUser
    @EnvironmentObject private var tabRouter: TabRouter

    var body: some View {
        TabView(selection: $tabRouter.selection) {
            NavigationStack {
                LibraryView(config: config)
            }
            .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            .tag(TabRouter.Tab.library)

            NavigationStack {
                AskAIView(config: config)
            }
            .tabItem { Label("Ask AI", systemImage: "sparkles") }
            .tag(TabRouter.Tab.ask)

            AccountTabView(config: config)
                .tabItem {
                    Label(
                        user.isGuest ? "Sign In" : "Account",
                        systemImage: user.isGuest ? "person.crop.circle.badge.plus" : "person.crop.circle.fill"
                    )
                }
                .tag(TabRouter.Tab.account)
        }
    }
}

/// The Account tab's root content: the signed-in user's own `AccountView` once real, or
/// `AuthGateView` while the session is still the anonymous guest.
private struct AccountTabView: View {
    let config: AppConfig
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        NavigationStack {
            Group {
                if let user = sessionStore.user, !user.isGuest {
                    AccountView(user: user)
                } else {
                    AuthGateView()
                }
            }
        }
    }
}
