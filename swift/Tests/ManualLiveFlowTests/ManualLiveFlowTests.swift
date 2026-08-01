import Foundation
import Testing
@testable import MudbaseShowcaseDocsSearch
import MudbaseSDK

/// Standalone, headless verification that exercises this app's own `Services`/`Networking` layer —
/// the exact `AuthGateway`, `DocumentsService`, `SearchLogService`, and `AccessTokenCoordinator`
/// types the SwiftUI views and view models call — directly against the real, live
/// `cloud.mudbase.dev` project. There is no iOS Simulator in this environment, so this stands in
/// for clicking through the actual UI — the same headless-verification approach the sibling
/// `mudbase-showcase-ecommerce`/`mudbase-showcase-social` Swift ports use.
///
/// Disabled unless `RUN_LIVE_FLOW_TEST=1` is set, since it makes real network calls against a live
/// project and writes real documents (a document and a search_log entry). A plain `swift test`
/// must never do that on its own — see `RetrievalTests.swift` for the always-on, offline coverage.
/// Run it explicitly with:
///
///   RUN_LIVE_FLOW_TEST=1 swift test --filter ManualLiveFlowTests
@Suite(.serialized)
struct ManualLiveFlowTests {
    static let isEnabled = ProcessInfo.processInfo.environment["RUN_LIVE_FLOW_TEST"] == "1"

    static let config = AppConfig(
        projectId: "6a6d3faad07caabbbdfc5698",
        baseURL: URL(string: "https://cloud.mudbase.dev")!,
        documentsCollectionId: "6a6d3fcdd07caabbbdfc5842",
        searchLogCollectionId: "6a6d3fcdd07caabbbdfc5857"
    )

    // The already-verified account supplied for this build (see README "Provisioning").
    static let demoEmail = "docs.member.demo@gmail.com"
    static let demoPassword = "DemoTest123!"

    /// Optional pre-minted token-pair fallback, read from the environment — this project's
    /// `/api/auth/*` endpoints are rate-limited per IP, a real, shared budget across every sibling
    /// port's own live verification runs against this same project. When set, these are used
    /// instead of calling `login`, so a rerun doesn't have to spend more of the shared per-IP
    /// budget.
    private static func resolveSession(authGateway: AuthGateway) async throws -> AuthGateway.LoginResult {
        let environment = ProcessInfo.processInfo.environment
        if let accessToken = environment["DEMO_ACCESS_TOKEN"], let refreshToken = environment["DEMO_REFRESH_TOKEN"],
           !accessToken.isEmpty, !refreshToken.isEmpty {
            return AuthGateway.LoginResult(accessToken: accessToken, refreshToken: refreshToken)
        }
        return try await authGateway.login(email: demoEmail, password: demoPassword)
    }

    @Test(.enabled(if: ManualLiveFlowTests.isEnabled))
    @MainActor
    func fullDocsSearchFlow() async throws {
        MudbaseSDKBootstrap.configure(baseURL: Self.config.baseURL)

        let authGateway = AuthGateway(projectId: Self.config.projectId)
        let documentsService = DocumentsService(config: Self.config)
        let searchLogService = SearchLogService(config: Self.config)

        // --- Public read / auth-gated writes: an anonymous session can read the library but
        // cannot create a document. ---
        let anonymousSession = try await authGateway.loginAnonymous()
        MudbaseSDKBootstrap.setAccessToken(anonymousSession.accessToken)
        let anonymousUser = try await authGateway.currentUser()
        #expect(anonymousUser.isGuest, "a freshly created anonymous session should report isGuest == true")
        _ = try await documentsService.list(limit: 5)
        do {
            _ = try await documentsService.create(
                title: "should never be created",
                content: "should never be created",
                tags: "",
                authorId: anonymousUser.id,
                authorName: "Anon"
            )
            Issue.record("an anonymous session was able to create a document — expected the platform to reject this with 403")
        } catch {
            let displayable = MudbaseAPIError.map(error)
            #expect(displayable.statusCode == 403, "expected anonymous document-create to 403, got \(displayable.statusCode): \(displayable.message)")
        }

        // --- Demo account signs in ---
        let session = try await Self.resolveSession(authGateway: authGateway)
        MudbaseSDKBootstrap.setAccessToken(session.accessToken)
        let user = try await authGateway.currentUser()
        #expect(!user.isGuest, "the demo account's session should not be the anonymous guest")
        #expect(user.email == Self.demoEmail)
        #expect(user.customRole == "customer")

        // --- Create a real document, verify it round-trips through list/get/update ---
        let uniqueSuffix = UUID().uuidString.prefix(8)
        let created = try await documentsService.create(
            title: "Manual live flow test document (\(uniqueSuffix))",
            content: "This document verifies the Swift port's document CRUD round trip against the real Mudbase project. Safe to delete.",
            tags: "swift,verification",
            authorId: user.id,
            authorName: user.displayName
        )
        #expect(created.authorId == user.id)

        let firstPage = try await documentsService.list(limit: 20)
        #expect(firstPage.contains { $0.id == created.id }, "library read did not include the just-created document")

        let fetched = try await documentsService.get(id: created.id)
        #expect(fetched.title == created.title)

        let updated = try await documentsService.update(
            id: created.id,
            title: "Manual live flow test document (\(uniqueSuffix), edited)",
            content: fetched.content,
            tags: fetched.tags ?? ""
        )
        #expect(updated.title.hasSuffix("edited)"))

        // --- Ownership check: the created document's authorId matches the signed-in user, the
        // exact condition `DocumentDetailViewModel.isOwner` and the web app's own `isOwner` check
        // both gate Edit/Delete on. ---
        #expect(updated.authorId == user.id)

        // --- search_log write with the real signed-in user's ObjectId (never a placeholder) ---
        let logged = try await searchLogService.log(
            queryText: "manual live flow test query (\(uniqueSuffix))",
            resultCount: 1,
            userId: user.id,
            userName: user.displayName
        )
        #expect(logged.userId == user.id)

        let recent = try await searchLogService.recent(limit: 10)
        #expect(recent.contains { $0.id == logged.id }, "recent search_log read did not include the just-logged entry")

        // --- 401 refresh-and-retry: force the in-memory access token invalid, keep the real
        // refresh token in a scratch Keychain entry, and confirm `AccessTokenCoordinator`
        // transparently refreshes and retries once instead of the call failing outright. ---
        let scratchTokenStore = KeychainTokenStore(service: "dev.mudbase.showcase.docssearch.manualtest")
        scratchTokenStore.save(.init(accessToken: session.accessToken, refreshToken: session.refreshToken))
        await AccessTokenCoordinator.shared.configure(authGateway: authGateway, tokenStore: scratchTokenStore)
        MudbaseSDKBootstrap.setAccessToken("this-access-token-is-intentionally-invalid")
        let documentsAfterForcedExpiry = try await documentsService.list(limit: 5)
        #expect(!documentsAfterForcedExpiry.isEmpty, "a call made with a deliberately invalid access token did not recover via refresh-and-retry")
        scratchTokenStore.clear()

        // --- Cleanup: delete the test document, confirm it's actually gone. The coordinator's
        // refresh above already restored a valid access token via
        // `MudbaseSDKBootstrap.setAccessToken` internally, so no re-assignment is needed here. ---
        try await documentsService.delete(id: created.id)
        do {
            _ = try await documentsService.get(id: created.id)
            Issue.record("expected the deleted document to 404 on a follow-up get")
        } catch {
            let displayable = MudbaseAPIError.map(error)
            #expect(displayable.statusCode == 404)
        }

        // --- Sign out (best-effort) ---
        try? await authGateway.logout()
    }
}
