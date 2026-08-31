# Build Plan - Mudbase Showcase: Docs Search (Go port)
Generated: 2026-08-01
Mode: port (one of several language/platform ports of `../web/`, the reference Next.js
implementation)
Type: server-rendered web (fullstack via BaaS, no custom backend except the one unavoidable Ask
AI completion call)
Stack: Go 1.26 + net/http + chi/v5 + html/template + gorilla/sessions, backed by Mudbase
(cloud.mudbase.dev) via the official `github.com/mudbase/mudbase-sdk/go` SDK.

## Stack Decisions

- Mirrors `mudbase-showcase-kanban/go` and `mudbase-showcase-social/go`'s established framework
  exactly: net/http + chi, server-rendered `html/template` pages, a `gorilla/sessions` encrypted
  cookie holding the Mudbase JWT (there is no client-side JS framework, so the cookie is the only
  place a token can live), and the same `internal/mbase` package shape (Client, generic
  List/Get/Create/Update/Delete, TokenRefresher-carrying context) - read those two projects'
  `internal/mbase/refresh.go` and `internal/session/session.go` verbatim before writing this app's
  equivalents, which is exactly what happened here.
- **The 401 -> refresh -> retry pattern** (`internal/mbase/refresh.go`'s `callWithRefresh`, wired
  through request context by `internal/server/middleware.go`'s `tokenRefresher`) is carried over
  unchanged from the sibling ports - every `mbase.List/Get/Create/Update/Delete` call retries once
  on a 401 after exchanging the session's stored refresh token for a new pair.
- **Registration is implemented, unlike `mudbase-showcase-social/go`.** The reference web app's
  page map includes `/login` AND `/register` (`web/plan/build-plan.md`), so this port does too -
  `internal/mbase/auth.go`'s `Register` uses the same raw-HTTP workaround
  `mudbase-showcase-ecommerce/go` established: the vendored SDK's generated
  `RegisterWithRoleRequest` model has no field for `agreedToTerms`, which Mudbase's registration
  validator requires, so registration is issued as a direct HTTP call built the same way the
  generated method builds its own request (same path/method/headers/base URL), not through the
  generated SDK method itself.
- **Server-side keyword search, not client-side.** The reference web app loads up to 100
  documents and filters them client-side as the visitor types
  (`web/src/app/page.tsx`, `web/src/lib/retrieval.ts`'s `matchesSearchTerm`). This Go app has no
  client-side JS state to hold a loaded-but-unfiltered set across requests, so
  `store.DocumentService.Library` does the equivalent filtering server-side, on every `GET
  /?q=...` request: fetch up to 100 documents newest-first, then apply the identical
  case-insensitive substring match across title/content/tags in Go. Same algorithm, same
  behavior, different tier.
- **Ask AI is ported as a single Go-side pipeline, not split client/server like the Next.js app.**
  See "Ask AI architecture" below - this is the actual point of the showcase, and it survives the
  port unchanged in substance: client-side (here: Go-side) keyword retrieval shortlists
  candidates, a real deployed Mudbase Function re-ranks them and assembles a grounded context
  block, and this app's own handler makes the one Anthropic Claude completion call the Function's
  sandbox cannot make itself.

## Data Models (Mudbase Collections - already provisioned, used as-is, not recreated)

Identical schema to `web/plan/build-plan.md` - restated here only as this app's Go structs
(`internal/models/*.go`):

- **documents** (`6a6d3fcdd07caabbbdfc5842`): `title` (string), `content` (string), `tags`
  (string, optional, comma-separated), `authorId` (string), `authorName` (string).
- **search_log** (`6a6d3fcdd07caabbbdfc5857`): `queryText` (string), `userId` (string, optional -
  real ObjectId or omitted, never a placeholder), `userName` (string, optional), `resultCount`
  (number).
- Role: `customer` (Mudbase's single default starter role), full CRUD on both collections, no
  per-row `dataScope` restriction - which is exactly why document edit/delete ownership is this
  app's own UX-layer check (`doc.AuthorID == data.UserID()` in
  `internal/server/handlers_documents.go`), not a Mudbase-enforced security boundary. Same
  tradeoff the reference web app's own `isOwner`-gated UI makes.

## Auth Flow

```
First visit (no session cookie) → POST /api/auth/anonymous → guest session (viewer, no customRole)
                                                             → can browse the library, search, and
                                                               use Ask AI, cannot write
Sign in                          → POST /api/auth/local/login (email/password)
                                                             → 200 + token/refreshToken, stored in
                                                               the encrypted session cookie
Register                          → POST /api/auth/local/signup/customer (raw HTTP, see "Stack
                                                               Decisions") → session on success, or
                                                               a "check your inbox" flash if the
                                                               project requires email verification
Sign out                          → POST /api/auth/logout (revokes token) + clears session identity
```

## Ask AI architecture - the actual point of this showcase

### The naive plan and why it doesn't work

The obvious design: the client (here: this Go server, since there's no browser-side JS state)
does keyword retrieval, sends the question + top documents to a Mudbase Function, the Function
holds the LLM API key as its own environment variable and calls the LLM provider directly, returns
a grounded answer. **This does not work on the current Mudbase platform**, for two
independently-verified reasons (full detail with source citations in `../web/plan/build-plan.md`):

1. **A project end-user JWT can never invoke a Function.** The `/execute` route requires the org
   role `owner`/`admin`/`developer`; every project end-user - including a real, signed-in
   `customer` account - always carries org role `viewer`, which only grants `functions:read`, not
   `functions:create`. Only an org-scoped API key can invoke it.
2. **The Function's own sandbox has zero network access.** Mudbase Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with only `console`/`payload`/`context`/`env` injected - no
   `fetch`, no `http`, no way to reach an external API at all. A Function **cannot** make an
   outbound HTTPS call to any LLM provider, full stop, regardless of what env var it holds.

Both are genuine, independently-verified platform constraints (see the reference web app's plan
doc for the exact source citations against `mudbase-backend`), not a scope limitation on this
port.

### What was actually built instead

1. **The same real, deployed Mudbase Function the reference web app uses.** `docsAskRetrieval`
   (`_id 6a6d431ef09e238c3e62b2f4`) - not recreated, not a stand-in - receives
   `payload.question` and `payload.candidates` (documents already shortlisted server-side by this
   Go app), re-scores them by query-term overlap across title (×3)/tags (×2)/content (×1), and
   returns a `contextBlock` string plus a `citations` array. This Go app invokes it through the
   real generated SDK's `FunctionsAPI` (`ExecuteFunction`/`GetFunctionExecution`), not a hand-rolled
   HTTP client - the SDK's `ApiKeyAuth` context mechanism (`mudbase.ContextAPIKeys`) attaches the
   `X-API-Key` header exactly the way `mudbase-sdk/go/api_functions.go`'s generated code expects
   (confirmed by reading that generated code directly - see
   `internal/askai/functioninvoke.go`'s doc comment).
2. **The same org-scoped API key.** `MUDBASE_FUNCTIONS_API_KEY` (`ak_...`), permissioned only for
   `functions`, lives ONLY as a server-only env var - this Go app has no client-side JS at all, so
   there's no `NEXT_PUBLIC_`-equivalent risk, but the key still never appears in any
   template-rendered HTML or log line.
3. **The LLM completion call happens in the one place with a real network stack: this app's own
   `handleAskSubmit` handler.** `POST /ask` (`internal/server/handlers_ask.go`) validates the
   request, invokes the Function (`internal/askai/functioninvoke.go`), then makes one grounded
   completion call to Anthropic's Claude API (`internal/askai/llm.go`) using `ANTHROPIC_API_KEY`
   (server-only, never rendered client-side, never inside the Function's env - it would be
   unusable there per constraint #2 above).
4. **Full request flow:**
   - `store.DocumentService.CandidatePool` fetches up to 200 documents (same pool size the
     reference web app's Ask AI panel loads).
   - `askai.ScoreDocuments` scores them by keyword overlap (title ×3/tags ×2/content ×1, mirrors
     `web/src/lib/retrieval.ts`'s `scoreDocuments` exactly, same tokenization rules).
   - If nothing scores > 0, the search is logged with `resultCount: 0` and the page shows "no
     keyword match" - no Function call, no LLM call, mirrors the reference web app's
     `AskAIPanel.tsx` short-circuit exactly.
   - Otherwise the top 5 candidates (`askai.TopCandidates`, content truncated to 4000 chars each)
     are sent to the Function via `askai.FunctionInvoker.Invoke`, which executes it and polls
     `GetFunctionExecution` every 600ms (20s timeout) until `status` leaves `queued`/`running`.
   - If the Function found nothing usable (`usedCount == 0`), this is a normal, successful
     response (not an error) - the page shows a canned "couldn't find anything closely related"
     answer, and the search is still logged with `resultCount: 0`.
   - Otherwise the Function's `contextBlock` feeds `askai.LLMClient.GenerateGroundedAnswer`, which
     calls Anthropic's Messages API directly (`claude-opus-5` by default, overridable via
     `LLM_MODEL`) with a system prompt instructing the model to answer only from the provided
     excerpts and cite them by title.
   - The page renders the answer + citations, and the search is logged to `search_log` with
     `resultCount` = the number of citations - `userId`/`userName` are only included for a real
     signed-in visitor, never a placeholder, exactly like the reference web app's own
     spread-conditional.

### LLM provider choice

**Anthropic Claude**, via a direct HTTPS call to `https://api.anthropic.com/v1/messages`
(`internal/askai/llm.go`) - no SDK dependency needed for a single request/response shape. Model
defaults to `claude-opus-5`, overridable with the `LLM_MODEL` env var.

### Known limitation, honestly documented

No real `ANTHROPIC_API_KEY` was available in the environment this was built and smoke-tested in.
The full request/response pipeline is wired up and verified end-to-end up to the point of the
actual LLM call (see README "Live smoke test") - the Mudbase Function deployment, invocation,
polling, and retrieval-ranking are all confirmed working against the real, live Mudbase project,
using the real generated SDK's `FunctionsAPI`. The LLM completion step itself fails with a clear,
expected `ErrAnthropicKeyMissing` error rather than any fabricated success.

## UI Pages / Routes

- `GET /` - document library: search box (`?q=` query param, server-side substring match across
  title/content/tags), grid of document cards. Public read (anonymous session).
- `GET /documents/{id}` - full content, author, tags. Public read; edit/delete UI gated to
  `data.UserID() == doc.AuthorID`.
- `GET /documents/new`, `POST /documents` - create (`requireSignedIn`).
- `GET /documents/{id}/edit`, `POST /documents/{id}/edit` - edit (`requireSignedIn` + app-level
  ownership check).
- `POST /documents/{id}/delete` - delete (`requireSignedIn` + app-level ownership check).
- `GET /ask`, `POST /ask` - Ask AI panel + recent searches. Public (Ask AI works for guests too;
  `search_log.userId` is only set when signed in).
- `GET /login`, `POST /login`, `GET /register`, `POST /register`, `POST /logout`.

## Security Implementation

- Input validation: server-side length checks mirroring the reference web app's zod schemas
  (title ≤ 200 chars, content ≤ 50000 chars, tags ≤ 500 chars, question ≤ 2000 chars), required
  fields checked before any Mudbase call.
- Authentication: Mudbase-issued JWT (access + refresh) held in a signed, encrypted, httpOnly
  session cookie (`gorilla/sessions`, AES via a SHA-256-derived key from `SESSION_SECRET`,
  `SameSite=Lax`). 401 → refresh → retry wired through every collection call via request context.
- Authorization: document CRUD is enforced server-side by Mudbase collection permissions
  (`customer` role, full CRUD, no per-row scope); document edit/delete ownership is this app's own
  UX-layer gate (see "Data Models" above), not a Mudbase-enforced boundary.
- The Ask AI Function invocation uses a separate, narrowly-scoped org API key
  (`MUDBASE_FUNCTIONS_API_KEY`) - never the visitor's own session token, and never exposed to any
  client (this app has none besides server-rendered HTML).
- Secrets: `SESSION_SECRET` (≥ 32 chars, validated at startup), `MUDBASE_FUNCTIONS_API_KEY`, and
  `ANTHROPIC_API_KEY` are the real secrets this app holds - never logged, loaded from the
  environment. Every Mudbase project/collection/function ID is a plain identifier, not a secret.

## Known Limitations (real platform constraints, not bugs)

- **No public/anonymous collection read without a session.** Every collection read requires a JWT
  (anonymous or real) - confirmed live by the reference web app, restated here for this port.
- **Document edit/delete ownership is an app-level UX gate, not a Mudbase-enforced restriction** -
  see "Data Models" above.
- **The Ask AI LLM call cannot live inside the Mudbase Function** - see "Ask AI architecture"
  above. Hard platform constraint, not a choice made for convenience.
- **No `ANTHROPIC_API_KEY` in the build/test environment** - the Ask AI feature is fully wired and
  will work once a developer supplies their own key; it was not possible to test a real generated
  answer in this environment.

## Live Smoke Test Results

See `README.md` → "Live smoke test" for the full step-by-step results against the real project
(`6a6d3faad07caabbbdfc5698`), including: document CRUD (create/read/update/delete, confirmed gone
after delete), server-side keyword search (match and no-match), and the full Ask AI pipeline
verified twice - once via direct `curl` against the Function's execute/poll endpoints (proving the
deploy → invoke → poll → result pipeline independent of the auth-endpoint rate limit, since it
authenticates via a separate `X-API-Key` mechanism), and once through this app's own running
`POST /ask` handler end-to-end (2s response time confirming the real candidate-pool fetch +
Function round trip, failing only at the documented, honest `ANTHROPIC_API_KEY` gap). Also
documents how a shared, concurrently-exhausted login rate limit (multiple sibling ports of this
same showcase writing to the same project during this run) was handled by blocking synchronously
and retrying rather than skipping verification or fabricating a result.

## File Tree

```
mudbase-showcase-docs-search/go/
├── go.mod, go.sum, .env.example, .gitignore, README.md
├── plan/build-plan.md
├── cmd/server/main.go
├── internal/
│   ├── config/config.go
│   ├── mbase/ (client.go, auth.go, data.go, errors.go, refresh.go)
│   ├── models/ (document.go, searchlog.go)
│   ├── store/ (documents.go, searchlog.go)
│   ├── session/session.go
│   ├── askai/ (retrieval.go, functioninvoke.go, llm.go)
│   └── server/
│       ├── app.go, context.go, middleware.go, templates.go, view.go, format.go, helpers.go
│       ├── handlers_auth.go, handlers_documents.go, handlers_ask.go
│       ├── templates/ (layout.html, partials.html, home.html, document_detail.html,
│       │   document_form.html, ask.html, login.html, register.html)
│       └── static/style.css
```
