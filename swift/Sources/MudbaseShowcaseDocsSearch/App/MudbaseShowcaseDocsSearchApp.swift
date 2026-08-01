import SwiftUI

/// App entry point. Configures the shared `MudbaseSDKAPIConfiguration` once at launch (see
/// `MudbaseSDKBootstrap`) and owns the app-wide observable stores (`SessionStore`, `TabRouter`) as
/// `@StateObject`s so they survive view identity churn across the whole app lifetime.
@main
struct MudbaseShowcaseDocsSearchApp: App {
    private let configResult: Result<AppConfig, ConfigurationError>
    @StateObject private var sessionStore: SessionStore
    @StateObject private var tabRouter = TabRouter()

    init() {
        let result = AppConfig.load()
        configResult = result
        switch result {
        case .success(let config):
            MudbaseSDKBootstrap.configure(baseURL: config.baseURL)
            _sessionStore = StateObject(wrappedValue: SessionStore(config: config))
        case .failure:
            // Placeholder config — never used, since `body` renders `ConfigurationRequiredView`
            // instead of `RootView` in this case. A concrete (if inert) value keeps the
            // `@StateObject` property non-optional, which keeps every downstream view's
            // `@EnvironmentObject` usage non-optional too.
            let placeholder = AppConfig(
                projectId: "",
                baseURL: URL(string: "https://cloud.mudbase.dev") ?? URL(fileURLWithPath: "/"),
                documentsCollectionId: "",
                searchLogCollectionId: ""
            )
            _sessionStore = StateObject(wrappedValue: SessionStore(config: placeholder))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch configResult {
            case .success(let config):
                RootView(config: config)
                    .environmentObject(sessionStore)
                    .environmentObject(tabRouter)
                    .environment(\.appConfig, config)
            case .failure(let error):
                ConfigurationRequiredView(error: error)
            }
        }
    }
}
