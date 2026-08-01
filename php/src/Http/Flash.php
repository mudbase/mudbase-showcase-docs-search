<?php

declare(strict_types=1);

namespace App\Http;

/**
 * One-shot session flash messages (set on one request, read and discarded on the next). Ported
 * verbatim from the sibling kanban/social PHP ports.
 */
final class Flash
{
    private const SESSION_KEY = 'flash';

    public static function set(string $type, string $message): void
    {
        $_SESSION[self::SESSION_KEY] = ['type' => $type, 'message' => $message];
    }

    /** @return array{type: string, message: string}|null */
    public static function consume(): ?array
    {
        $flash = $_SESSION[self::SESSION_KEY] ?? null;
        unset($_SESSION[self::SESSION_KEY]);
        return is_array($flash) ? $flash : null;
    }
}
