<?php

declare(strict_types=1);

namespace App\Http;

/**
 * Minimal per-session CSRF token for the app's state-changing forms (login, register, document
 * CRUD, ask) — every `<form method="post">` view includes the hidden field this class renders,
 * and every POST controller action verifies it before doing anything else. Ported verbatim from
 * the sibling kanban/social PHP ports.
 */
final class Csrf
{
    private const SESSION_KEY = 'csrf_token';

    public static function token(): string
    {
        $token = $_SESSION[self::SESSION_KEY] ?? null;
        if (!is_string($token) || $token === '') {
            $token = bin2hex(random_bytes(32));
            $_SESSION[self::SESSION_KEY] = $token;
        }
        return $token;
    }

    public static function field(): string
    {
        $token = htmlspecialchars(self::token(), ENT_QUOTES, 'UTF-8');
        return "<input type=\"hidden\" name=\"_csrf\" value=\"{$token}\">";
    }

    public static function verify(?string $submitted): bool
    {
        $expected = $_SESSION[self::SESSION_KEY] ?? null;
        return is_string($expected) && is_string($submitted) && $submitted !== '' && hash_equals($expected, $submitted);
    }
}
