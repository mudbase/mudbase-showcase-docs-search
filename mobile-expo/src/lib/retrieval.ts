import type { DocumentRecord } from "@/api/schemas";
import { countOccurrences, tokenizeQuery } from "@/lib/format";

export interface ScoredDocument {
  document: DocumentRecord;
  score: number;
}

/**
 * Client-side keyword retrieval: scores each document by counting query-term occurrences across
 * title (weight 3), tags (weight 2), and content (weight 1). No vector DB, no external search
 * service - simple substring matching, per plan/build-plan.md. Byte-for-byte port of
 * web/src/lib/retrieval.ts.
 */
export function scoreDocuments(documents: DocumentRecord[], query: string): ScoredDocument[] {
  const terms = tokenizeQuery(query);
  if (terms.length === 0) return [];

  return documents
    .map((document) => {
      let score = 0;
      for (const term of terms) {
        score += countOccurrences(document.title, term) * 3;
        score += countOccurrences(document.tags ?? "", term) * 2;
        score += countOccurrences(document.content, term);
      }
      return { document, score };
    })
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score);
}

/** Matches the library screen's plain-text search box: substring match across title+content+tags. */
export function matchesSearchTerm(document: DocumentRecord, term: string): boolean {
  if (!term.trim()) return true;
  const needle = term.trim().toLowerCase();
  return (
    document.title.toLowerCase().includes(needle) ||
    document.content.toLowerCase().includes(needle) ||
    (document.tags ?? "").toLowerCase().includes(needle)
  );
}

const MAX_CANDIDATE_CONTENT_CHARS = 4000;

/** Top-N candidates for the Ask AI request payload, with content truncated to bound payload size. */
export function topCandidates(
  scored: ScoredDocument[],
  limit = 5,
): Array<{ documentId: string; title: string; content: string; tags?: string }> {
  return scored.slice(0, limit).map(({ document }) => ({
    documentId: document._id,
    title: document.title,
    content: document.content.slice(0, MAX_CANDIDATE_CONTENT_CHARS),
    ...(document.tags ? { tags: document.tags } : {}),
  }));
}
