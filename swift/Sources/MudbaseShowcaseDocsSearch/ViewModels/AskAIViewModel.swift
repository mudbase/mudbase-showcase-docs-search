import Foundation

/// Backs `AskAIView`. This is the one screen in this port that deliberately does **not** match the
/// web reference app's behavior, and the mismatch is the actual point of this showcase — see this
/// package's README "Ask AI architecture" for the full reasoning. Short version:
///
/// The web app's `POST /api/ask` (`../web/src/app/api/ask/route.ts`) does three things: (1) client-
/// side keyword retrieval identical to `Retrieval.scoreDocuments` below, (2) invoke the real,
/// deployed `docsAskRetrieval` Mudbase Function to re-rank the shortlist and assemble a grounded
/// context block, (3) call the Anthropic Claude API with that context to synthesize a
/// natural-language answer. Steps 2 and 3 both require a secret that must stay server-side: step 2
/// needs an org-scoped `ak_` Mudbase API key (a project end-user JWT can never invoke a Function —
/// verified in `../web/plan/build-plan.md`), and step 3 needs the LLM provider's own API key. The
/// web app can do this because a Next.js Route Handler *is* a server. **A SwiftUI iOS app has no
/// equivalent server-side surface at all** — there is no process this app owns other than the
/// binary running on the user's device — so embedding either secret in the app bundle is the one
/// thing explicitly ruled out for this port (a distributed binary can be unpacked; see
/// `rules/ecc/swift/security.md` "never hardcode secrets in source — decompilation tools extract
/// them trivially," and this project's own non-negotiable "secrets in environment variables only,
/// never in client bundles").
///
/// **What this view model actually does instead:** step 1 only, for real, on-device, against the
/// real documents just fetched from the live Mudbase project — using the *exact same* title×3/
/// tags×2/content×1 scoring weights the deployed Function itself uses (see `Retrieval`'s doc
/// comment for the independent `curl` verification proving the weights match). That means the
/// *ranking* of results here is provably identical to what the Function would produce; the only
/// capability genuinely missing is step 3, the LLM's natural-language synthesis, which needs a
/// server-side proxy this app does not include. Rather than fabricate a fake "answer" string (which
/// would misrepresent what actually happened), this screen surfaces the ranked, cited source
/// excerpts directly and labels the missing step honestly — a real, useful, working search result,
/// not a broken chat feature. `search_log` is still written with the real result count, exactly as
/// the web app does.
@MainActor
final class AskAIViewModel: ObservableObject {
    struct RankedResult: Identifiable, Equatable {
        let documentId: String
        let title: String
        let snippet: String
        let score: Int
        var id: String { documentId }
    }

    @Published var question = ""
    @Published private(set) var isLoadingLibrary = true
    @Published private(set) var isAsking = false
    @Published private(set) var results: [RankedResult] = []
    @Published private(set) var hasAsked = false
    @Published private(set) var noMatch = false
    @Published private(set) var errorMessage: String?

    private var libraryDocuments: [DocumentRecord] = []
    private let documentsService: DocumentsService
    private let searchLogService: SearchLogService

    init(config: AppConfig) {
        documentsService = DocumentsService(config: config)
        searchLogService = SearchLogService(config: config)
    }

    var canAsk: Bool {
        !isAsking && !isLoadingLibrary && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadLibrary() async {
        isLoadingLibrary = true
        errorMessage = nil
        defer { isLoadingLibrary = false }
        do {
            libraryDocuments = try await documentsService.listForRetrieval()
        } catch {
            errorMessage = MudbaseAPIError.map(error).message
        }
    }

    /// Performs the on-device retrieval-only "ask," then logs the search — mirrors
    /// `AskAIPanel.tsx`'s `handleAsk` up through the point where the web version would call
    /// `POST /api/ask`; this port stops at the ranked candidates instead (see this type's doc
    /// comment).
    func ask(currentUser: AppUser?) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isAsking = true
        errorMessage = nil
        results = []
        noMatch = false
        hasAsked = true
        defer { isAsking = false }

        let scored = Retrieval.scoreDocuments(libraryDocuments, query: trimmed)

        guard !scored.isEmpty else {
            noMatch = true
            await logSearch(queryText: trimmed, resultCount: 0, currentUser: currentUser)
            return
        }

        let topScored = Retrieval.topCandidates(scored, limit: 5)
        results = topScored.map { scored in
            RankedResult(
                documentId: scored.document.id,
                title: scored.document.title,
                snippet: Formatting.snippet(scored.document.content),
                score: scored.score
            )
        }
        await logSearch(queryText: trimmed, resultCount: results.count, currentUser: currentUser)
    }

    private func logSearch(queryText: String, resultCount: Int, currentUser: AppUser?) async {
        let userId = (currentUser?.isGuest == false) ? currentUser?.id : nil
        let userName = (currentUser?.isGuest == false) ? currentUser?.displayName : nil
        _ = try? await searchLogService.log(queryText: queryText, resultCount: resultCount, userId: userId, userName: userName)
    }
}
