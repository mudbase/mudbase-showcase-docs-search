# Mudbase Showcase — Docs Search (PHP)

An AI-powered knowledge-base search app built **almost entirely on [Mudbase](https://www.mudbase.dev)**
— auth, database, and a serverless Function for retrieval ranking — plus one small, unavoidable
server-side surface (see "Ask AI architecture" below), reimplemented as a plain, server-rendered
PHP application. This is a port of the reference Next.js app in `../web`; see that project for the
canonical data model and API contract.

## Stack

Plain PHP 8.1+ (no framework — no Laravel/Symfony), PHP's built-in dev server for local
development, and the real generated `mudbase/sdk` Composer package — the same SDK used by the
sibling `mudbase-showcase-kanban/php` and `mudbase-showcase-social/php` ports. This project
mirrors that architecture: `Router` → `Controllers` → `View` + plain `.php` view files, a
request-scoped `AppContext`, and a `MudbaseClient` wrapper around the SDK.

Auth is session-based: the Mudbase JWT pair lives in native PHP `$_SESSION`, not `localStorage` —
there is no client-side JavaScript auth flow, and in fact **no client-side JavaScript at all** in
this app. Every interaction — search, sign in/up, create/edit/delete a document, ask a question —
is a plain HTML `<form>` GET/POST.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Guest browsing + search, no signup | Anonymous session (`POST /api/auth/anonymous`) | `src/bootstrap.php`, `src/Controllers/DocumentController.php` |
| Email/password accounts, single `customer` role | `POST /api/auth/local/signup/customer` | `src/Controllers/AuthController.php` |
| Document library + keyword search | Collection read, server-side filter | `DocumentController::index`, `src/Ai/RetrievalScorer.php` |
| Document CRUD, app-enforced ownership | Collection CRUD | `DocumentController` (create/editForm/update/delete) |
| **Ask AI** — keyword retrieval → real Mudbase Function → grounded LLM answer with citations | Deployed Function + direct Anthropic call | `src/Controllers/AskController.php`, `src/Ai/*` — see below |
| Recent searches | Collection read, `search_log` | `AskController::form`/`loadRecentSearches` |

## Ask AI architecture (the actual point of this showcase)

**The naive design — the app does retrieval, sends question + docs to a Mudbase Function, the
Function holds the LLM key as its own env var and calls the LLM provider directly — does not work
on the current Mudbase platform**, for two independently-verified reasons (full detail with source
citations in `../web/plan/build-plan.md`, this port's own summary in `plan/build-plan.md`):

1. **A project end-user JWT can never invoke a Function.** The `/execute` route requires org role
   `owner`/`admin`/`developer`; every project end-user (including a real, signed-in `customer`
   account) always carries org role `viewer`, which only grants `functions:read`.
2. **The Function's own sandbox has zero network access.** Mudbase Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with only `console`/`payload`/`context`/`env` injected — no
   `fetch`, no `http`, no way to reach an external API at all.

**What this app actually does instead:**

1. A real, deployed Mudbase Function (`docsAskRetrieval`, `_id 6a6d431ef09e238c3e62b2f4`) does the
   retrieval-ranking work it *can* do inside the sandbox: given a question and a shortlist of
   candidate documents, it re-scores them by query-term overlap and returns a grounded context
   block + citations. `src/Ai/FunctionInvoker.php` invokes it through the generated SDK's own
   `FunctionsApi`, authenticated with a dedicated `Configuration` bound to an org-scoped API key —
   never the signed-in visitor's own Bearer token.
2. An org-scoped Mudbase API key (`ak_...`, permissioned only for `functions`) authorizes invoking
   it. This key lives only as the server-only `MUDBASE_FUNCTIONS_API_KEY` env var.
3. The one call the sandbox is structurally incapable of making — the outbound HTTPS request to
   the LLM provider — happens in `src/Ai/AnthropicClient.php`, called directly from
   `AskController::ask()`. Because this whole app is already server-side PHP, there is no separate
   "route" to carve out the way the Next.js reference app needed `POST /api/ask` — the controller
   method itself is already the smallest server-side surface holding both credentials.

See `plan/build-plan.md` "Ask AI architecture" for the full request flow and the live smoke test
that proves the Function deploy/invoke/poll pipeline works end-to-end against the real project.

## LLM setup

This app uses **Anthropic's Claude API** via a direct HTTPS call (Guzzle, already a transitive
dependency of `mudbase/sdk` — no separate SDK needed). To get real, grounded answers instead of the
"not configured" error:

1. Create an API key at [console.anthropic.com](https://console.anthropic.com).
2. Set it as `ANTHROPIC_API_KEY` in `.env` — **never** prefix it with anything that would expose
   it client-side, and never put it inside the Mudbase Function's own environment variables (the
   Function cannot use it — see above).
3. Optionally set `LLM_MODEL` (defaults to `claude-opus-5`) to a cheaper/faster model such as
   `claude-sonnet-5` or `claude-haiku-4-5` for a lower-cost demo.

Prefer a different provider? Swap the implementation in `src/Ai/AnthropicClient.php` — everything
else (the Function invocation, the controller flow, the views) is provider-agnostic.

## Getting started

This app expects a Mudbase project already provisioned with:

1. Local auth enabled with the Multi-Role feature's default `customer` role, full CRUD on both
   collections below.
2. Two collections — `documents` (`title`, `content`, `tags?`, `authorId`, `authorName`) and
   `search_log` (`queryText`, `userId?`, `userName?`, `resultCount`).
3. A deployed Mudbase Function named `docsAskRetrieval` and an org-scoped API key permissioned for
   `functions` — see `.env.example` for exactly how to create that key.

```bash
composer install
cp .env.example .env   # fill in your own provisioned project's IDs + keys
php -S localhost:8080 -t public public/router.php
```

Then visit `http://localhost:8080`. Browse and search as a guest, or sign in with the demo account
(one-click form on `/login`, or type credentials manually) — see `plan/build-plan.md` for the full
RBAC/auth model.

## Live smoke test

Run 2026-08-01 against the real, live project. See `plan/build-plan.md` → "Live smoke test
results" for the full step-by-step table. Summary: guest browsing/search, authenticated document
CRUD (create/search/edit/delete, all confirmed with real HTTP round trips), and the app-level
ownership gate (verified with a genuine negative case — a document created with a deliberately
different `authorId`, then a forged edit/delete attempt against it correctly rejected) all passed.
The Ask AI pipeline was verified end-to-end twice — once as a guest, once signed in — each
completing the real Function execute→poll→citations cycle in 2–3 seconds (confirmed independently
via a direct `curl` against the Function using the org API key, which correctly ranked "Password
Reset Guide" over an unrelated document) before reaching the honest, expected
`"ANTHROPIC_API_KEY is not configured"` error at the final LLM step (no key was available in this
build/test environment — see "Known limitations"). `search_log` writes were confirmed with the
real signed-in user's ObjectId, never a placeholder.

The platform's shared auth rate limit (`retryAfter: 900`) was heavily contended during this run —
confirmed to be scoped to the project id rather than the caller's IP (reproduced the identical
response from a second, unrelated public IP address) — because roughly 9 other concurrent
language/platform ports of this same showcase were testing against the same project
simultaneously. Every login/anonymous-session step above needed several bounded, patient retries
before landing in a window the other concurrent builds hadn't already consumed.

## Known limitations (real platform/architecture constraints, not bugs)

See `plan/build-plan.md` → "Known Limitations":

- **No realtime.** The generated PHP SDK ships no realtime client, and a server-rendered app has
  no persistent connection to attach one to — every mutation already reloads the page, which shows
  the latest state.
- **The Ask AI LLM call cannot live inside the Mudbase Function** — see "Ask AI architecture"
  above. This is the single largest architectural deviation from the most obvious design, and it
  is a hard platform constraint, not a choice made for convenience.
- **No `ANTHROPIC_API_KEY` in the build/test environment** — the Ask AI feature is fully wired and
  will work once a developer supplies their own key (see "LLM setup" above).
- **Document ownership is enforced by this app, not by Mudbase** — this project's single
  `customer` role grants every signed-in account full collection CRUD; Mudbase has no per-document
  ownership concept, so "you can only edit/delete what you authored" is an application-level rule
  (`DocumentController`), not a platform permission. Documented explicitly rather than silently
  relying on something the platform cannot do.

## Design choice: forms, not client-side search or fetch

Search runs via `GET /?q=...` (a full page reload, not a live-filtering input) and Ask AI via a
plain `POST /ask` form — no `fetch()`, no client JavaScript at all. This is a deliberate,
dependency-light choice that stays fully keyboard- and screen-reader-operable, matching the same
zero-JS stance the sibling kanban PHP port takes for its own reasons — see that project's README
for the fuller rationale.

## Security

- CSRF token on every state-changing form, verified before any controller logic runs.
- Open-redirect guard (`Response::redirectToSafe()`) on the login/register `redirectTo` value.
- Session id regenerated on login/register.
- All dynamic output escaped via `View::escape()` — no raw interpolation of user content anywhere,
  including the LLM's own generated answer text.
- Document ownership enforced server-side in `DocumentController` (see "Known limitations").
- `MUDBASE_FUNCTIONS_API_KEY` and `ANTHROPIC_API_KEY` are server-only env vars, read only inside
  `AskController`/`FunctionInvoker`/`AnthropicClient` — never rendered into any page.

## Environment Variables

See `.env.example`.
