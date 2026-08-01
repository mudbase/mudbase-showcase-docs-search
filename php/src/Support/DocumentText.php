<?php

declare(strict_types=1);

namespace App\Support;

/** A PHP port of the reference app's `parseTags`/`snippet` (src/lib/utils.ts). */
final class DocumentText
{
    /** Parses the documents.tags field (comma-separated string) into a clean array. */
    public static function parseTags(?string $tags): array
    {
        if ($tags === null || trim($tags) === '') {
            return [];
        }

        $parts = array_map('trim', explode(',', $tags));
        return array_values(array_filter($parts, static fn (string $tag): bool => $tag !== ''));
    }

    /** Builds a short plain-text snippet from document content, for library-card previews. */
    public static function snippet(string $text, int $maxLength = 160): string
    {
        $collapsed = trim((string) preg_replace('/\s+/', ' ', $text));
        if (mb_strlen($collapsed) <= $maxLength) {
            return $collapsed;
        }
        return rtrim(mb_substr($collapsed, 0, $maxLength)) . '…';
    }
}
