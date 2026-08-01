package dev.mudbase.showcase.docssearch.support;

import dev.mudbase.showcase.docssearch.domain.DocumentRecord;
import dev.mudbase.showcase.docssearch.domain.ScoredDocument;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Java port of the reference web app's {@code src/lib/retrieval.ts} and the tokenizer/counter
 * helpers from {@code src/lib/utils.ts}. Since this app is server-rendered (Thymeleaf, no client
 * JS framework), the exact same "client-side keyword retrieval" logic the Next.js app runs in the
 * browser runs here on the server instead - same scoring weights, same behavior, same reason it
 * exists: no vector DB, no external search service, just substring matching, per
 * plan/build-plan.md.
 */
public final class Retrieval {

  private static final int TITLE_WEIGHT = 3;
  private static final int TAGS_WEIGHT = 2;
  private static final int CONTENT_WEIGHT = 1;
  private static final int MIN_TOKEN_LENGTH = 3;
  private static final int MAX_CANDIDATE_CONTENT_CHARS = 4000;

  private Retrieval() {}

  /** Splits free text into lowercase alphanumeric tokens of length > 2, deduplicated. */
  public static List<String> tokenizeQuery(String text) {
    Set<String> tokens = new LinkedHashSet<>();
    if (text == null) {
      return List.of();
    }
    for (String token : text.toLowerCase().split("[^a-z0-9]+")) {
      if (token.length() >= MIN_TOKEN_LENGTH) {
        tokens.add(token);
      }
    }
    return List.copyOf(tokens);
  }

  /** Case-insensitive substring count of {@code term} inside {@code text}. */
  public static int countOccurrences(String text, String term) {
    if (text == null || term == null || term.isEmpty()) {
      return 0;
    }
    String haystack = text.toLowerCase();
    String needle = term.toLowerCase();
    int count = 0;
    int index = haystack.indexOf(needle);
    while (index != -1) {
      count++;
      index = haystack.indexOf(needle, index + needle.length());
    }
    return count;
  }

  /**
   * Scores each document by counting query-term occurrences across title (weight 3), tags
   * (weight 2), and content (weight 1). Documents with a zero score are dropped, and the rest
   * are sorted highest-first - mirrors {@code scoreDocuments} in retrieval.ts exactly.
   */
  public static List<ScoredDocument> scoreDocuments(List<DocumentRecord> documents, String query) {
    List<String> terms = tokenizeQuery(query);
    if (terms.isEmpty()) {
      return List.of();
    }
    List<ScoredDocument> scored = new ArrayList<>();
    for (DocumentRecord document : documents) {
      int score = 0;
      for (String term : terms) {
        score += countOccurrences(document.getTitle(), term) * TITLE_WEIGHT;
        score += countOccurrences(document.getTags(), term) * TAGS_WEIGHT;
        score += countOccurrences(document.getContent(), term) * CONTENT_WEIGHT;
      }
      if (score > 0) {
        scored.add(new ScoredDocument(document, score));
      }
    }
    scored.sort((a, b) -> Integer.compare(b.score(), a.score()));
    return scored;
  }

  /** Matches the library page's plain-text search box: substring match across title+content+tags. */
  public static boolean matchesSearchTerm(DocumentRecord document, String term) {
    if (term == null || term.trim().isEmpty()) {
      return true;
    }
    String needle = term.trim().toLowerCase();
    String title = document.getTitle() != null ? document.getTitle().toLowerCase() : "";
    String content = document.getContent() != null ? document.getContent().toLowerCase() : "";
    String tags = document.getTags() != null ? document.getTags().toLowerCase() : "";
    return title.contains(needle) || content.contains(needle) || tags.contains(needle);
  }

  /** Top-N candidates for the Ask AI request payload, with content truncated to bound payload size. */
  public static List<AskCandidate> topCandidates(List<ScoredDocument> scored, int limit) {
    List<AskCandidate> candidates = new ArrayList<>();
    int count = Math.min(limit, scored.size());
    for (int i = 0; i < count; i++) {
      DocumentRecord document = scored.get(i).document();
      String content = document.getContent() != null ? document.getContent() : "";
      String truncated = content.length() > MAX_CANDIDATE_CONTENT_CHARS ? content.substring(0, MAX_CANDIDATE_CONTENT_CHARS) : content;
      candidates.add(new AskCandidate(document.getId(), document.getTitle(), truncated, document.getTags()));
    }
    return candidates;
  }

  /** One shortlisted document sent to the Mudbase Function's retrieval-ranking payload. */
  public record AskCandidate(String documentId, String title, String content, String tags) {}
}
