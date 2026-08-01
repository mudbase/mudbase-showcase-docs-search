import Foundation
import Testing
@testable import MudbaseShowcaseDocsSearch

/// Pure, offline unit tests for `Retrieval` — no network calls, always runs as part of a plain
/// `swift test` (unlike `ManualLiveFlowTests`, which is gated behind `RUN_LIVE_FLOW_TEST=1`). These
/// lock in the one fact the whole "Ask AI architecture" README section depends on: this on-device
/// scoring uses the *exact* title×3/tags×2/content×1 weighting the deployed `docsAskRetrieval`
/// Mudbase Function itself uses (independently confirmed live via `curl` — see README "Ask AI
/// architecture" for the exact request/response transcript). If these weights ever drift from the
/// Function's own, this test — not a live network call — is what should catch it first.
@Suite
struct RetrievalTests {
    private static func makeDocument(id: String, title: String, content: String, tags: String? = nil) -> DocumentRecord {
        DocumentRecord(id: id, title: title, content: content, tags: tags, authorId: "author", authorName: "Author", createdAt: nil, updatedAt: nil)
    }

    @Test("title matches outweigh content matches by the documented 3x weight")
    func titleWeightIsTriple() throws {
        let titleMatch = Self.makeDocument(id: "1", title: "Password Reset Guide", content: "Unrelated filler content.")
        let contentMatch = Self.makeDocument(id: "2", title: "Unrelated", content: "password password password")

        let scored = Retrieval.scoreDocuments([titleMatch, contentMatch], query: "password")
        let titleScore = scored.first { $0.document.id == "1" }?.score
        let contentScore = scored.first { $0.document.id == "2" }?.score

        // "password" appears once in the title (weight 3) vs. three times in content (weight 1) —
        // both come out to 3, proving the weight actually applies per-occurrence rather than being
        // a flat per-document bonus.
        #expect(titleScore == 3)
        #expect(contentScore == 3)
    }

    @Test("tag matches count double a content match")
    func tagWeightIsDouble() throws {
        let tagMatch = Self.makeDocument(id: "1", title: "Unrelated", content: "filler", tags: "billing")
        let scored = Retrieval.scoreDocuments([tagMatch], query: "billing")
        #expect(scored.first?.score == 2)
    }

    @Test("documents with zero score are excluded, not just ranked last")
    func zeroScoreDocumentsAreFiltered() throws {
        let noMatch = Self.makeDocument(id: "1", title: "Completely unrelated", content: "nothing matches here")
        let scored = Retrieval.scoreDocuments([noMatch], query: "password reset")
        #expect(scored.isEmpty)
    }

    @Test("ranking matches the deployed Function's own live-verified result")
    func rankingMatchesLiveVerifiedFunctionResult() throws {
        // Same two documents and question used in this port's own curl verification against the
        // real, deployed docsAskRetrieval Function (see README "Ask AI architecture" — "Live
        // verification"): the Function ranked "Password Reset Guide" (score 12 there, using a
        // slightly different tokenization of the longer question) above "Billing FAQ" (filtered
        // out entirely, score 0). This test proves this on-device scorer produces the same
        // *ordering* for the same inputs, independent of the exact numeric score.
        let passwordDoc = Self.makeDocument(
            id: "pw",
            title: "Password Reset Guide",
            content: "To reset your password, go to account settings and click reset password. You will receive an email link.",
            tags: "account,password"
        )
        let billingDoc = Self.makeDocument(
            id: "bill",
            title: "Billing FAQ",
            content: "Invoices are generated monthly. Contact billing support for refunds.",
            tags: "billing"
        )

        let scored = Retrieval.scoreDocuments([passwordDoc, billingDoc], query: "How do I reset my password?")
        #expect(scored.count == 1, "expected only the password document to score above zero, matching the live Function's usedCount: 1")
        #expect(scored.first?.document.id == "pw")
    }

    @Test("tokenizeQuery drops short tokens and dedupes, matching the web app's utils.ts")
    func tokenizeQueryMatchesWebBehavior() throws {
        let tokens = Retrieval.tokenizeQuery("How do I reset my password? password!")
        // "how", "do", "i", "my" are all length <= 2 or excluded by the >2 rule; "password" appears
        // twice in the source text but must be deduplicated to one token.
        #expect(tokens.contains("reset"))
        #expect(tokens.contains("password"))
        #expect(tokens.filter { $0 == "password" }.count == 1)
        #expect(!tokens.contains("do"))
        #expect(!tokens.contains("i"))
    }

    @Test("matchesSearchTerm mirrors the library screen's substring search across title/content/tags")
    func matchesSearchTermChecksAllThreeFields() throws {
        let document = Self.makeDocument(id: "1", title: "API Rate Limits", content: "Requests are capped per minute.", tags: "api,limits")
        #expect(Retrieval.matchesSearchTerm(document, term: "rate"))
        #expect(Retrieval.matchesSearchTerm(document, term: "capped"))
        #expect(Retrieval.matchesSearchTerm(document, term: "limits"))
        #expect(!Retrieval.matchesSearchTerm(document, term: "unrelated-term"))
        #expect(Retrieval.matchesSearchTerm(document, term: ""), "an empty search term should match everything, same as the web page's default state")
    }

    @Test("topCandidates truncates to the requested limit, highest score first")
    func topCandidatesRespectsLimit() throws {
        let documents = (0..<10).map { index in
            Self.makeDocument(id: "\(index)", title: String(repeating: "password ", count: index + 1), content: "filler")
        }
        let scored = Retrieval.scoreDocuments(documents, query: "password")
        let top = Retrieval.topCandidates(scored, limit: 5)
        #expect(top.count == 5)
        #expect(top.first?.document.id == "9", "the document with the most title occurrences should rank first")
    }
}
