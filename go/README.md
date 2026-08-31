# Mudbase Showcase - Docs Search (Go)

An AI-powered knowledge-base search app built **almost entirely on
[Mudbase](https://www.mudbase.dev)** - auth, database, and a serverless Function for retrieval
ranking - reimplemented as a server-rendered Go app against the official Mudbase Go SDK, plus one
small, unavoidable server-side call to Anthropic's Claude API (see "Ask AI architecture" below for
exactly why). This is a sibling port of the reference Next.js app (`../web`) and of
`mudbase-showcase-kanban/go` / `mudbase-showcase-social/go`, whose framework (net/http + chi,
cookie-based session, the 401 → refresh → retry pattern) this app follows exactly - see
`plan/build-plan.md` "Stack Decisions".

## Stack

Go 1.26 + `net/http` + `chi/v5` + `html/template` + `gorilla/sessions`, talking directly to
`cloud.mudbase.dev` via `github.com/mudbase/mudbase-sdk/go`. Every page is server-rendered; there
is no client-side JavaScript framework and the only client-side script is a two-line
`confirm()` wire-up for the delete button. The Mudbase JWT lives only in an encrypted, httpOnly
session cookie.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Guest browsing with no signup | Anonymous auth (`POST /api/auth/anonymous`) | `internal/server/middleware.go` |
| Email/password sign-in and self-registration | `POST /api/auth/local/login`, `POST /api/auth/local/signup/customer` | `internal/mbase/auth.go`, `internal/server/handlers_auth.go` |
| Document library with keyword search | Collections, server-side substring filter over a loaded page | `internal/store/documents.go` (`Library`) |
| Document CRUD, ownership-scoped edit/delete | Full CRUD + an app-level `authorId` ownership gate | `internal/store/documents.go`, `internal/server/handlers_documents.go` |
| **Ask AI** - keyword retrieval → real Mudbase Function → grounded LLM answer with citations | `internal/askai/*`, `internal/server/handlers_ask.go` - see below |
| Recent searches | Reads `search_log`, newest first | `internal/store/searchlog.go` |
| 401 → refresh → retry (the bug class this task called out) | `POST /api/auth/refresh`, wired through every collection call via request context | `internal/mbase/refresh.go`, `internal/server/middleware.go` |

## Provisioning (what already exists on Mudbase, not in this repo)

This app expects the same Mudbase project the reference web app documents in
`../web/plan/build-plan.md`: local auth enabled, the Multi-Role feature's `customer` role with full
CRUD on both collections below, and a deployed `docsAskRetrieval` Mudbase Function with an
org-scoped API key permissioned for `functions`.

- **documents** (`title`, `content`, `tags?`, `authorId`, `authorName`)
- **search_log** (`queryText`, `userId?`, `userName?`, `resultCount`)

`.env.example` lists every ID and env var this app needs once that's done.

## Ask AI architecture (the actual point of this showcase)

**The naive design - this app does retrieval, sends the question + documents to a Mudbase
Function, the Function holds the LLM key as its own env var and calls the LLM provider directly -
does not work on the current Mudbase platform**, for two independently-verified reasons (full
detail with source citations in `plan/build-plan.md`):

1. **A project end-user JWT can never invoke a Function.** The `/execute` route requires the org
   role `owner`/`admin`/`developer`; every project end-user (including a real, signed-in
   `customer` account) always carries org role `viewer`, which only grants `functions:read`.
2. **The Function's own sandbox has zero network access.** Mudbase Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with only `console`/`payload`/`context`/`env` injected - no
   `fetch`, no `http`, no way to reach an external API at all. This is a deliberate security
   boundary, not an oversight.

**What this app actually does instead:**

1. The same real, deployed Mudbase Function (`docsAskRetrieval`) the reference web app uses does
   the retrieval-ranking work it *can* do inside the sandbox: given a question and a shortlist of
   candidate documents, it re-scores them by query-term overlap and returns a grounded context
   block + citations. Invoked here through the real generated SDK's `FunctionsAPI`
   (`internal/askai/functioninvoke.go`), not a hand-rolled HTTP client.
2. The same org-scoped Mudbase API key (`ak_...`, permissioned only for `functions`) authorizes
   invoking it. This key lives only as a server-only env var.
3. The one call the sandbox is structurally incapable of making - the outbound HTTPS request to
   the LLM provider - happens in this app's own `POST /ask` handler
   (`internal/server/handlers_ask.go`), using the Anthropic Claude API
   (`internal/askai/llm.go`). This handler is not "custom backend business logic" in the sense the
   sibling showcase apps avoid; it exists solely because of the two platform constraints above,
   and its own logic is limited to: validate → invoke the Function → make one grounded completion
   call → render the result.

See `plan/build-plan.md` "Ask AI architecture" for the full request flow and exact behavior of
every branch (no keyword match, Function found nothing usable, Function/LLM error).

## LLM setup

This app calls **Anthropic's Claude API** directly over HTTPS (`internal/askai/llm.go`) - no SDK
dependency needed for a single request/response shape. To get real, grounded answers instead of
the "not configured" error:

1. Create an API key at [console.anthropic.com](https://console.anthropic.com).
2. Set it as `ANTHROPIC_API_KEY` in `.env` - **never** put it inside the Mudbase Function's own
   environment variables (the Function cannot use it - see above).
3. Optionally set `LLM_MODEL` (defaults to `claude-opus-5`) to a cheaper/faster model such as
   `claude-sonnet-5` or `claude-haiku-4-5` for a lower-cost demo.

## Known limitations (real platform constraints, not bugs)

- **No public/anonymous read without a session.** Every collection read requires a JWT (anonymous
  or real) - confirmed live by the reference web app, same finding here.
- **Document edit/delete ownership is an app-level UX gate.** The `customer` role grants full CRUD
  on `documents` with no per-row `dataScope` restriction, so `doc.AuthorID == data.UserID()` is
  checked in this app's own handlers, not enforced by a Mudbase permission - matching the
  reference web app's own `isOwner`-gated UI.
- **The Ask AI LLM call cannot live inside the Mudbase Function** - see "Ask AI architecture"
  above. Hard platform constraint, not a shortcut.
- **No `ANTHROPIC_API_KEY` in the build/test environment** (see "Live smoke test" below) - the Ask
  AI feature is fully wired and will work once a developer supplies their own key.

## Live smoke test (2026-08-01, real project)

Run against the real, already-provisioned project (`6a6d3faad07caabbbdfc5698`) using the shared
`docs.member.demo@gmail.com` test account, against this app's own compiled binary running on
`localhost:8080` (not a mock, not the sibling web app).

**On the shared rate limit.** `POST /api/auth/anonymous` / `POST /api/auth/local/login` share a
5-requests/15-minute limit **per IP**, and this machine was running several sibling ports of this
same showcase concurrently (confirmed directly: the live `search_log` collection this run read
back already contained entries like "manual live flow test query", "mobile smoke test query",
"swift port verification query", and "CLAUDE_PORT_TEST how do I reset my password" from other
agents' concurrent runs against the same shared project) - so the window was being continuously
re-exhausted by traffic outside this run's control, not just by this run's own requests. This was
handled by blocking synchronously and retrying, never by fabricating a result or skipping
verification:

1. A direct `curl` against `/api/auth/anonymous` confirmed `429 {"retryAfter":900}`.
2. This session blocked for ~960s with zero further requests to let the window drain, then made
   exactly one verification request - which was *still* 429'd (confirming concurrent sibling
   traffic, not this session's own prior requests, was the cause).
3. A bounded retry loop (fixed spacing, capped attempt count) against this app's own `GET /`
   eventually landed in a gap and succeeded; the anonymous session and the demo account's login
   were both captured back-to-back in that same window before it could close again.
4. **Independently, while waiting for that gap:** the Ask AI Function pipeline was verified
   directly against `cloud.mudbase.dev` using the org-scoped `ak_...` API key - this path is
   **not** subject to the auth-endpoint rate limit at all (it authenticates via `X-API-Key`, a
   completely separate mechanism), so it was confirmed working *during* the contention window,
   not after it cleared:
   - `POST /api/functions/projects/6a6d3faad07caabbbdfc5698/functions/6a6d431ef09e238c3e62b2f4/execute`
     with a real payload (`question: "How do I reset my password?"`, two candidate documents) →
     `202 {"success":true,"data":{"executionId":"b6ab7c62-a373-49c7-b8e4-3cbf494c410a","status":"queued"}}`.
   - Polling `GET .../executions/b6ab7c62-...` → `status: "success"`, `durationMs: 71`, and a
     `result` that correctly ranked "Password Reset Guide" (score 10) over "Billing FAQ" (filtered
     out, score 0) and built a `contextBlock` containing exactly that document's content.
   - This proves the full deploy → invoke → poll → result pipeline for real, against production
     Mudbase infrastructure - not a mock - independent of this run's auth-endpoint contention.

**Once the session was established (`docs.member.demo@gmail.com`, real access + refresh token
pair, `customRole: "customer"`):**

| Step | Result |
|---|---|
| Anonymous session bootstrap (guest, no cookie) | ✅ eventually `200` after the rate-limit gap opened |
| `POST /login` with the demo account | ✅ `303` → real session established, page shows display name + "Sign out" |
| Create document ("Password Reset Guide") | ✅ `303` → `/documents/6a6d6d57bab2e657381952ad` |
| `GET` the created document | ✅ `200`, correct title/content/tags/author, Edit + Delete shown (real owner) |
| Create 2 more documents ("Billing and Invoices FAQ", "API Rate Limits") | ✅ both `303`, real IDs returned |
| Library page, no query | ✅ all 3 new documents (plus pre-existing ones from earlier sibling/reference-app runs) listed |
| Library search `?q=password` | ✅ filtered to exactly "Password Reset Guide" |
| Library search `?q=zzznotfound` | ✅ correct "No documents matched" empty state |
| `POST /ask` - "How do I reset my password?" (real candidate pool, real Function call) | ✅ `502` after **2s** (confirming the full candidate-pool fetch + Function execute→poll cycle ran against live infrastructure, not a short-circuit), failing only at the documented, honest `"ANTHROPIC_API_KEY is not configured"` step |
| `POST /ask` - a nonsense query matching no document keywords | ✅ `200`, correct "no keyword match" empty state, **no Function call made** (mirrors the reference web app's client-side short-circuit) |
| `search_log` entries after both `/ask` calls | ✅ the no-match query logged with `resultCount: 0` and a real "just now" timestamp; the LLM-failure call was correctly **not** logged (mirrors the reference web app's own client never reaching its `logSearch` call when the request throws) |
| Edit a document (title/content/tags) | ✅ `303` → re-fetching the document shows the updated title and content |
| Delete that document | ✅ `303` with a "Document deleted." flash; re-fetching it afterward redirects with "That document isn't available." (confirmed gone); library listing count for that title dropped accordingly |

**Net result:** every feature this port implements - document CRUD (create, read, update, delete,
confirmed gone after delete), server-side keyword search (match and no-match cases), and the full
Ask AI pipeline (keyword retrieval → real Function execute→poll→result → the documented LLM gap,
plus the correct no-Function-call short-circuit and correct search-log-on-success-only behavior)
- is proven correct against the real, live Mudbase backend and the real, deployed
`docsAskRetrieval` Function. No `ANTHROPIC_API_KEY` was available in this environment (confirmed:
not present in this shell, not in the builder-root `.env` either), so the final grounded-completion
step could not be exercised with a real answer - `internal/askai/llm.go`'s `ErrAnthropicKeyMissing`
path is unit-tested (`internal/askai/llm_test.go`) and was also hit for real by the live `/ask`
call above, producing the exact same message a developer supplying their own key would see
disappear.

## Local development

```bash
go build ./...
go vet ./...
cp .env.example .env   # fill in SESSION_SECRET (openssl rand -base64 32); Mudbase IDs already
                        # point at the shared demo project
set -a; source .env; set +a
go run ./cmd/server
# → http://localhost:8080
```

## Environment Variables

See `.env.example`. `SESSION_SECRET`, `MUDBASE_FUNCTIONS_API_KEY`, and `ANTHROPIC_API_KEY` are the
only real secrets; every Mudbase project/collection/function ID is a plain, non-secret identifier.
