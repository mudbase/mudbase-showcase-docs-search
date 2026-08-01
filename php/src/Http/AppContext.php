<?php

declare(strict_types=1);

namespace App\Http;

use App\Mudbase\MudbaseClient;

/**
 * Per-request registry handed to every controller and view: the authenticated Mudbase client and
 * the current session user (real account, or the anonymous guest session, or null) — the
 * server-rendered counterpart of the reference app's React `useMudbase()` context
 * (src/lib/mudbase-provider.tsx). One instance per request; built once in bootstrap.php right
 * after the session/auth handshake.
 *
 * Carries the Ask AI server-only config (Function id/key, Anthropic key/model) alongside the
 * regular Mudbase wiring so `AskController` has everything it needs from one place, exactly like
 * every other controller reads its collection ids from here.
 */
final class AppContext
{
    private static ?self $instance = null;

    /** @param array<string, mixed>|null $user */
    public function __construct(
        public readonly MudbaseClient $mudbase,
        public readonly ?array $user,
        public readonly string $projectId,
        public readonly string $documentsCollectionId,
        public readonly string $searchLogCollectionId,
        public readonly string $mudbaseUrl,
        public readonly ?string $functionId,
        public readonly ?string $functionsApiKey,
        public readonly ?string $anthropicApiKey,
        public readonly string $llmModel,
    ) {
    }

    public static function set(self $context): void
    {
        self::$instance = $context;
    }

    public static function current(): self
    {
        if (self::$instance === null) {
            throw new \RuntimeException('AppContext accessed before bootstrap set it.');
        }
        return self::$instance;
    }

    public function isSignedIn(): bool
    {
        // `GET /api/auth/local/session` (see MudbaseClient::fetchSessionUser()) does not reliably
        // return an `isAnonymous` key at all for anonymous sessions in practice — confirmed
        // against the live API on the sibling social/ecommerce PHP ports, the key is simply
        // absent from the response body — so a bare
        // `($this->user['isAnonymous'] ?? false) !== true` check treats every anonymous guest as
        // signed in (missing key -> false -> "not anonymous"). `customRole` is the reliable
        // signal instead: Mudbase only ever assigns a customRole ("customer") to a real
        // registered account; anonymous sessions always come back with `customRole: null`. Kept
        // the `isAnonymous` check too as defense in depth for any response shape that does
        // include it.
        return $this->user !== null
            && ($this->user['isAnonymous'] ?? false) !== true
            && ($this->user['customRole'] ?? null) !== null;
    }

    /**
     * Redirects an unauthenticated visitor to `/login`, carrying the originally-requested path
     * back through `?redirect=` so they land where they meant to go after signing in. Used by
     * document create/edit — guest browsing and search stay public (see plan/build-plan.md
     * "Auth Model").
     */
    public function requireSignIn(string $requestedPath): void
    {
        if (!$this->isSignedIn()) {
            Response::redirect('/login?redirect=' . urlencode($requestedPath));
        }
    }

    public function userId(): ?string
    {
        $id = $this->user['id'] ?? $this->user['_id'] ?? null;
        return is_string($id) ? $id : null;
    }

    /** `"{firstName} {lastName}"`, trimmed — the denormalized author name every write stores. */
    public function displayName(): ?string
    {
        if ($this->user === null) {
            return null;
        }
        $first = is_string($this->user['firstName'] ?? null) ? $this->user['firstName'] : '';
        $last = is_string($this->user['lastName'] ?? null) ? $this->user['lastName'] : '';
        $name = trim("{$first} {$last}");
        return $name !== '' ? $name : null;
    }
}
