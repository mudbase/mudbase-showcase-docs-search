import Foundation

/// The SwiftUI equivalent of the web app's `router.push("/login")` redirect — `DocumentForm`'s
/// "New document" entry point and any owner-only action guard the user against a guest session by
/// switching to the Account tab (which renders the sign-in screen whenever `sessionStore.user` is
/// the anonymous guest — see `AccountTabView`) rather than pushing a URL, since a native `TabView`
/// has no URL to push. Injected as an `@EnvironmentObject` from the app root so any view several
/// levels deep in the Library or Ask tab can request the switch without threading a callback
/// through every intermediate view.
@MainActor
final class TabRouter: ObservableObject {
    enum Tab: Hashable {
        case library
        case ask
        case account
    }

    @Published var selection: Tab = .library

    func routeToSignIn() {
        selection = .account
    }
}
