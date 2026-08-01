import '../models/document_record.dart';

// Client-side keyword retrieval - a line-for-line Dart port of the
// reference web app's `src/lib/retrieval.ts` and `src/lib/utils.ts`
// (`tokenizeQuery`/`countOccurrences`). No vector DB, no external search
// service - simple substring/token-overlap scoring, matching the exact
// weights the deployed Mudbase Function (`docsAskRetrieval`) itself uses
// server-side: title x3, tags x2, content x1 (see
// `plan/build-plan.md` "Ask AI architecture" for why this app runs this
// scoring on-device rather than invoking that Function directly).

/// Case-insensitive substring count of `term` inside `text`.
int countOccurrences(String text, String term) {
  if (term.isEmpty) return 0;
  final haystack = text.toLowerCase();
  final needle = term.toLowerCase();
  var count = 0;
  var index = haystack.indexOf(needle);
  while (index != -1) {
    count += 1;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return count;
}

/// Splits free text into lowercase alphanumeric tokens of length > 2,
/// deduplicated (order-preserving).
List<String> tokenizeQuery(String text) {
  final tokens = text
      .toLowerCase()
      .split(RegExp('[^a-z0-9]+'))
      .where((token) => token.length > 2);
  final seen = <String>{};
  final result = <String>[];
  for (final token in tokens) {
    if (seen.add(token)) result.add(token);
  }
  return List.unmodifiable(result);
}

class ScoredDocument {
  const ScoredDocument({required this.document, required this.score});

  final DocumentRecord document;
  final int score;
}

/// Scores each document by counting query-term occurrences across title
/// (weight 3), tags (weight 2), and content (weight 1). Documents scoring 0
/// are dropped; the rest are sorted highest-score-first.
List<ScoredDocument> scoreDocuments(
  List<DocumentRecord> documents,
  String query,
) {
  final terms = tokenizeQuery(query);
  if (terms.isEmpty) return const [];

  final scored = documents
      .map((document) {
        var score = 0;
        for (final term in terms) {
          score += countOccurrences(document.title, term) * 3;
          score += countOccurrences(document.tags ?? '', term) * 2;
          score += countOccurrences(document.content, term);
        }
        return ScoredDocument(document: document, score: score);
      })
      .where((entry) => entry.score > 0)
      .toList();

  scored.sort((a, b) => b.score.compareTo(a.score));
  return List.unmodifiable(scored);
}

/// Matches the library screen's plain-text search box: substring match
/// across title+content+tags.
bool matchesSearchTerm(DocumentRecord document, String term) {
  final trimmed = term.trim();
  if (trimmed.isEmpty) return true;
  final needle = trimmed.toLowerCase();
  return document.title.toLowerCase().contains(needle) ||
      document.content.toLowerCase().contains(needle) ||
      (document.tags ?? '').toLowerCase().contains(needle);
}

const int _maxCandidateContentChars = 4000;

class AskCandidate {
  const AskCandidate({
    required this.documentId,
    required this.title,
    required this.content,
    this.tags,
  });

  final String documentId;
  final String title;
  final String content;
  final String? tags;
}

/// Top-N ranked candidates, content truncated to bound payload/context size -
/// the same shape (and same truncation limit) the reference web app builds
/// before invoking the real Mudbase Function.
List<AskCandidate> topCandidates(List<ScoredDocument> scored, {int limit = 5}) {
  return scored
      .take(limit)
      .map(
        (entry) => AskCandidate(
          documentId: entry.document.id,
          title: entry.document.title,
          content: entry.document.content.length > _maxCandidateContentChars
              ? entry.document.content.substring(0, _maxCandidateContentChars)
              : entry.document.content,
          tags: entry.document.tags,
        ),
      )
      .toList(growable: false);
}
