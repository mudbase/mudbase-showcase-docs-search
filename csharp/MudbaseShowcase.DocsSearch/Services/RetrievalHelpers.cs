using System.Text.RegularExpressions;
using MudbaseShowcase.DocsSearch.Models;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>A document scored against a query - direct port of web/src/lib/retrieval.ts's ScoredDocument.</summary>
public sealed record ScoredDocument(DocumentRecord Document, int Score);

/// <summary>One shortlisted document sent to the Mudbase Function's retrieval-ranking payload - mirrors web/src/lib/ask-schema.ts's AskRequestCandidateSchema.</summary>
public sealed record RetrievalCandidate(string DocumentId, string Title, string Content, string? Tags);

/// <summary>
/// Client-side keyword retrieval, ported server-side since this app is itself server-rendered:
/// scores each document by counting query-term occurrences across title (weight 3), tags (weight
/// 2), and content (weight 1). No vector DB, no external search service - simple substring
/// matching, direct port of web/src/lib/retrieval.ts and the tokenizeQuery/countOccurrences
/// helpers from web/src/lib/utils.ts.
/// </summary>
public static class RetrievalHelpers
{
    private const int MaxCandidateContentChars = 4000;

    /// <summary>Splits free text into lowercase alphanumeric tokens of length &gt; 2, deduplicated (first-occurrence order preserved, matching JS Set semantics).</summary>
    public static IReadOnlyList<string> TokenizeQuery(string text)
    {
        return Regex.Split(text.ToLowerInvariant(), "[^a-z0-9]+")
            .Where(token => token.Length > 2)
            .Distinct()
            .ToList();
    }

    /// <summary>Case-insensitive substring count of `term` inside `text`.</summary>
    public static int CountOccurrences(string text, string term)
    {
        if (string.IsNullOrEmpty(term)) return 0;

        string haystack = text.ToLowerInvariant();
        string needle = term.ToLowerInvariant();
        int count = 0;
        int index = haystack.IndexOf(needle, StringComparison.Ordinal);
        while (index != -1)
        {
            count++;
            index = haystack.IndexOf(needle, index + needle.Length, StringComparison.Ordinal);
        }

        return count;
    }

    public static List<ScoredDocument> ScoreDocuments(IEnumerable<DocumentRecord> documents, string query)
    {
        IReadOnlyList<string> terms = TokenizeQuery(query);
        if (terms.Count == 0) return new List<ScoredDocument>();

        return documents
            .Select(document =>
            {
                int score = 0;
                foreach (string term in terms)
                {
                    score += CountOccurrences(document.Title, term) * 3;
                    score += CountOccurrences(document.Tags ?? string.Empty, term) * 2;
                    score += CountOccurrences(document.Content, term);
                }

                return new ScoredDocument(document, score);
            })
            .Where(entry => entry.Score > 0)
            .OrderByDescending(entry => entry.Score)
            .ToList();
    }

    /// <summary>Matches the library page's plain-text search box: substring match across title+content+tags.</summary>
    public static bool MatchesSearchTerm(DocumentRecord document, string term)
    {
        if (string.IsNullOrWhiteSpace(term)) return true;

        string needle = term.Trim().ToLowerInvariant();
        return document.Title.ToLowerInvariant().Contains(needle, StringComparison.Ordinal)
            || document.Content.ToLowerInvariant().Contains(needle, StringComparison.Ordinal)
            || (document.Tags ?? string.Empty).ToLowerInvariant().Contains(needle, StringComparison.Ordinal);
    }

    /// <summary>Top-N candidates for the Ask AI Function payload, with content truncated to bound payload size.</summary>
    public static List<RetrievalCandidate> TopCandidates(IReadOnlyList<ScoredDocument> scored, int limit = 5)
    {
        return scored
            .Take(limit)
            .Select(entry => new RetrievalCandidate(
                entry.Document.Id,
                entry.Document.Title,
                entry.Document.Content.Length > MaxCandidateContentChars
                    ? entry.Document.Content[..MaxCandidateContentChars]
                    : entry.Document.Content,
                entry.Document.Tags))
            .ToList();
    }
}
