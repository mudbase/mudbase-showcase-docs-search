import SwiftUI

/// The Swift equivalent of `../web/src/lib/mudbase-provider.tsx`'s bootstrap effect: restore a
/// session from Keychain (real or anonymous), falling back to a fresh anonymous session — see
/// `SessionStore` doc comments for why `user` is effectively always non-nil once bootstrap
/// completes. `user == nil` here means bootstrap couldn't establish *any* session at all (e.g. no
/// network), which is a real error state, not "browsing as guest."
struct RootView: View {
    let config: AppConfig
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        Group {
            if sessionStore.isBootstrapping {
                LoadingView()
            } else if let user = sessionStore.user {
                MainTabView(config: config, user: user)
            } else {
                InlineErrorView(message: "Couldn't connect to Mudbase. Please check your connection and try again.") {
                    Task { await sessionStore.bootstrap() }
                }
            }
        }
        .task { await sessionStore.bootstrap() }
    }
}
