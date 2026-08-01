import Foundation

/// Client-side keyword retrieval — a Swift port of `../web/src/lib/retrieval.ts` +
/// `../web/src/lib/utils.ts`'s `tokenizeQuery`/`countOccurrences`, using the *identical* scoring
/// weights (title ×3, tags ×2, content ×1) the real, deployed `docsAskRetrieval` Mudbase Function
/// itself uses (confirmed by reading the Function's own code referenced in
/// `../web/plan/build-plan.md` "Ask AI architecture", and independently re-verified for this port
/// via a direct `curl` against the live Function — see this package's README "Ask AI architecture"
/// for the exact request/response). Because the weights match exactly, this on-device scoring is
/// not a lesser stand-in for the Function's ranking — it produces the same relative ordering the
/// Function would. What it cannot do is synthesize a natural-language answer from that ranking;
/// see `AskAIViewModel` and the README for why that step is a documented, honest gap in this port.
enum Retrieval {
    struct ScoredDocument {
        let document: DocumentRecord
        let score: Int
    }

    /// Splits free text into lowercase alphanumeric tokens of length > 2, deduplicated. Mirrors
    /// `tokenizeQuery` in `../web/src/lib/utils.ts`.
    static func tokenizeQuery(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let tokens = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 }
        var seen = Set<String>()
        var result: [String] = []
        for token in tokens where seen.insert(token).inserted {
            result.append(token)
        }
        return result
    }

    /// Case-insensitive substring occurrence count. Mirrors `countOccurrences` in
    /// `../web/src/lib/utils.ts`.
    static func countOccurrences(_ text: String, term: String) -> Int {
        guard !term.isEmpty else { return 0 }
        let haystack = text.lowercased()
        let needle = term.lowercased()
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }
        return count
    }

    /// Scores each document by counting query-term occurrences across title (weight 3), tags
    /// (weight 2), and content (weight 1), descending. Mirrors `scoreDocuments` in
    /// `../web/src/lib/retrieval.ts` exactly.
    static func scoreDocuments(_ documents: [DocumentRecord], query: String) -> [ScoredDocument] {
        let terms = tokenizeQuery(query)
        guard !terms.isEmpty else { return [] }

        return documents
            .map { document -> ScoredDocument in
                var score = 0
                for term in terms {
                    score += countOccurrences(document.title, term: term) * 3
                    score += countOccurrences(document.tags ?? "", term: term) * 2
                    score += countOccurrences(document.content, term: term)
                }
                return ScoredDocument(document: document, score: score)
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
    }

    /// Matches the library screen's plain-text search box: substring match across
    /// title+content+tags. Mirrors `matchesSearchTerm` in `../web/src/lib/retrieval.ts`.
    static func matchesSearchTerm(_ document: DocumentRecord, term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let needle = trimmed.lowercased()
        return document.title.lowercased().contains(needle)
            || document.content.lowercased().contains(needle)
            || (document.tags ?? "").lowercased().contains(needle)
    }

    static let maxCandidateContentChars = 4000

    /// Top-N scored candidates, content truncated to bound size — mirrors `topCandidates` in
    /// `../web/src/lib/retrieval.ts`. Used by `AskAIViewModel` to build the on-device "Ask AI"
    /// result surface (see that type's doc comment for why it stops at ranked candidates rather
    /// than an LLM-synthesized answer).
    static func topCandidates(_ scored: [ScoredDocument], limit: Int = 5) -> [ScoredDocument] {
        Array(scored.prefix(limit))
    }
}
