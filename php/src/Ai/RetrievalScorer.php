<?php

declare(strict_types=1);

namespace App\Ai;

/**
 * Client-side (well — the PHP equivalent: this app has no client-side JS, so it runs on every
 * request instead of in the browser) keyword retrieval: scores each document by counting
 * query-term occurrences across title (weight 3), tags (weight 2), and content (weight 1). No
 * vector DB, no external search service — simple substring matching, a line-for-line PHP port of
 * the reference app's `scoreDocuments`/`matchesSearchTerm`/`topCandidates`/`tokenizeQuery`/
 * `countOccurrences` (src/lib/retrieval.ts, src/lib/utils.ts).
 */
final class RetrievalScorer
{
    private const MAX_CANDIDATE_CONTENT_CHARS = 4000;

    /**
     * @param list<array<string, mixed>> $documents
     * @return list<array{document: array<string, mixed>, score: int}> sorted by score descending,
     *         zero-score documents excluded
     */
    public static function scoreDocuments(array $documents, string $query): array
    {
        $terms = self::tokenizeQuery($query);
        if ($terms === []) {
            return [];
        }

        $scored = [];
        foreach ($documents as $document) {
            $title = is_string($document['title'] ?? null) ? $document['title'] : '';
            $tags = is_string($document['tags'] ?? null) ? $document['tags'] : '';
            $content = is_string($document['content'] ?? null) ? $document['content'] : '';

            $score = 0;
            foreach ($terms as $term) {
                $score += self::countOccurrences($title, $term) * 3;
                $score += self::countOccurrences($tags, $term) * 2;
                $score += self::countOccurrences($content, $term);
            }

            if ($score > 0) {
                $scored[] = ['document' => $document, 'score' => $score];
            }
        }

        usort($scored, static fn (array $a, array $b): int => $b['score'] <=> $a['score']);
        return $scored;
    }

    /** Matches the library page's plain-text search box: substring match across title+content+tags. */
    public static function matchesSearchTerm(array $document, string $term): bool
    {
        $trimmed = trim($term);
        if ($trimmed === '') {
            return true;
        }

        $needle = mb_strtolower($trimmed);
        $title = mb_strtolower(is_string($document['title'] ?? null) ? $document['title'] : '');
        $content = mb_strtolower(is_string($document['content'] ?? null) ? $document['content'] : '');
        $tags = mb_strtolower(is_string($document['tags'] ?? null) ? $document['tags'] : '');

        return str_contains($title, $needle) || str_contains($content, $needle) || str_contains($tags, $needle);
    }

    /**
     * Top-N candidates for the Ask AI Function payload, with content truncated to bound payload
     * size — same 4000-char cap and shape as the reference app's `topCandidates()`.
     *
     * @param list<array{document: array<string, mixed>, score: int}> $scored
     * @return list<array{documentId: string, title: string, content: string, tags?: string}>
     */
    public static function topCandidates(array $scored, int $limit = 5): array
    {
        $top = array_slice($scored, 0, $limit);
        $candidates = [];
        foreach ($top as $entry) {
            $document = $entry['document'];
            $candidate = [
                'documentId' => (string) ($document['_id'] ?? ''),
                'title' => is_string($document['title'] ?? null) ? $document['title'] : '',
                'content' => mb_substr(is_string($document['content'] ?? null) ? $document['content'] : '', 0, self::MAX_CANDIDATE_CONTENT_CHARS),
            ];
            $tags = $document['tags'] ?? null;
            if (is_string($tags) && $tags !== '') {
                $candidate['tags'] = $tags;
            }
            $candidates[] = $candidate;
        }
        return $candidates;
    }

    /** Splits free text into lowercase alphanumeric tokens of length > 2, deduplicated. */
    private static function tokenizeQuery(string $text): array
    {
        $lower = mb_strtolower($text);
        $parts = preg_split('/[^a-z0-9]+/', $lower) ?: [];
        $tokens = array_values(array_filter($parts, static fn (string $t): bool => mb_strlen($t) > 2));
        return array_values(array_unique($tokens));
    }

    /** Case-insensitive substring count of `$term` inside `$text`. */
    private static function countOccurrences(string $text, string $term): int
    {
        if ($term === '') {
            return 0;
        }

        $haystack = mb_strtolower($text);
        $needle = mb_strtolower($term);
        $count = 0;
        $offset = 0;
        while (($position = mb_strpos($haystack, $needle, $offset)) !== false) {
            $count++;
            $offset = $position + mb_strlen($needle);
        }
        return $count;
    }
}
