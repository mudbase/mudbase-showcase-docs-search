# Mudbase Showcase - Docs Search (web) - Build Plan

Reference implementation for the docs-search showcase. The other 9 language/platform ports are
built to match this app's data model and API contract.

## Stack

Next.js 15 (App Router) + TypeScript strict + Tailwind CSS + shadcn/ui-style components (Radix
primitives + `class-variance-authority` + `tailwind-merge`) + TanStack Query + `react-hook-form` +
`zod`. Same conventions as the sibling `mudbase-showcase-social` web app (`src/lib/mudbase.ts` is
ported directly from it).

## Data model (already provisioned - do not recreate)

- **Project**: `6a6d3faad07caabbbdfc5698`, org `69bfe82fca1f8eea275419b8` ("MUDBASE Platform
  (internal)" - the shared internal org that hosts every showcase demo project this session).
- **`documents`** (`6a6d3fcdd07caabbbdfc5842`): `title` (string), `content` (string), `tags`
  (string, optional, comma-separated), `authorId` (string), `authorName` (string).
- **`search_log`** (`6a6d3fcdd07caabbbdfc5857`): `queryText` (string), `userId` (string,
  optional - real ObjectId or omitted, never a placeholder), `userName` (string, optional),
  `resultCount` (number).
- Role: `customer` (Mudbase's single default starter role), full CRUD on both collections.
  Verified live: **every collection read 401s with zero auth**, even with the project's `pk_`
  key - an anonymous session (`POST /api/auth/anonymous`) is required for guest browsing, same
  pattern as the sibling social/ecommerce apps.

## Page map

| Route | Auth | Purpose |
|---|---|---|
| `/` | public (anonymous session) | Document library: search box (client-side substring match across title/content/tags), grid of `DocumentCard`s |
| `/documents/[id]` | public read; edit/delete gated to `user.id === document.authorId` | Full content, author, tags |
| `/documents/new` | signed-in | Create document |
| `/documents/[id]/edit` | signed-in author only | Edit document |
| `/ask` | public (Ask AI works for guests too; search_log.userId only set when signed in) | Ask AI panel + recent searches |
| `/login`, `/register` | public | Auth forms |
| `/api/ask` | server-only route handler | Ask AI orchestration - see below |

## Auth flow

Identical to `mudbase-showcase-social`: `MudbaseClient` (`src/lib/mudbase.ts`) stores access +
refresh tokens in `localStorage`, dedupes concurrent refreshes via `refreshInFlight`, and retries
once on a 401. `MudbaseProvider` establishes an anonymous session on mount if no token exists, so
guests can browse. `useAuth().isAuthenticated` is true only for a real signed-in user (not the
anonymous guest identity).

## Ask AI architecture - the actual point of this showcase

### The naive plan and why it doesn't work

The obvious design: client does keyword retrieval, sends the question + top documents to a
Mudbase Function, the Function holds the LLM API key as its own environment variable and calls
the LLM provider directly, returns a grounded answer. **This does not work on the current
Mudbase platform**, for two independently-verified reasons:

**1. A project end-user JWT can never invoke a Function.** `rbacCheck("functions", "create")`
gates the `/execute` route (`mudbase-backend/routes/functions.js:319-322`), and the permission
table (`mudbase-backend/middleware/rbac.js:94-99`) only allows org roles
`owner`/`admin`/`developer` for `functions:create`. Every project end-user - including a real,
signed-in `customer` account - always carries org role `viewer` (`utils/projectEndUserRole.js`,
confirmed by querying this project's own users in the database: `docs.member.demo@gmail.com` has
`role: "viewer"`). `viewer` only satisfies `functions:read`. The only auth-free invocation path is
the webhook trigger (`POST /webhook/:projectId`, gated by a per-project `webhookSecret`) - but
that still runs through the exact same sandboxed execution path as `/execute`, so it doesn't
change constraint #2 below, and exposing the webhook secret client-side would mean anyone reading
the JS bundle could trigger arbitrary executions.

**2. The Function's own sandbox has zero network access.** Function code runs inside a genuine,
separate V8 isolate via `isolated-vm` (`mudbase-backend/runner/src/execution/sandboxWorker.js`),
specifically because the platform's prior sandbox (Node's `vm` module) had a real, exploitable
realm-escape bug (documented in that file's own comments). The isolate bootstrap
(`sandboxWorker.js:67-77`) only ever injects `console`, `payload`, `context`, and `env` as
globals - no `fetch`, no `http`/`https` module, no `require`. This was independently confirmed by
reading the runner source directly and by a parallel research pass that found the runner's own
test suite proves `process`/`require`/dynamic `import()` are all absent. `services/functionsService.js`
and `services/functions/sandboxUtils.js` build a richer `db`/`files`/`messaging`/`wallet`/`utils`
API surface, but that code is **never actually wired into the isolate** - dead code, confirmed by
grep (defined, never invoked). A Function **cannot** make an outbound HTTPS call to any LLM
provider, full stop, regardless of what env var it holds.

Both of these are genuine platform constraints, not a scope limitation on this build - verified
against the actual `mudbase-backend` source, not inferred from behavior.

### What was actually built instead

1. **A real, deployed Mudbase Function does real work.** `docsAskRetrieval`
   (`_id 6a6d431ef09e238c3e62b2f4`) was created via the platform's own
   `functionsService.createFunction()` (not hand-rolled - the exact same code path
   `POST /api/functions/projects/:id/functions` uses). Its code (pure JS, no network calls -
   everything it's structurally capable of) receives `payload.question` and
   `payload.candidates` (documents already shortlisted client-side), re-scores them by
   query-term overlap across title (×3)/tags (×2)/content (×1), and returns a `contextBlock`
   string plus a `citations` array. `env.MAX_RESULTS` / `env.MAX_CONTEXT_CHARS` are real,
   used Function environment variables (tunable without redeploying code).
2. **An org-scoped API key authorizes it.** `ApiKey` document `6a6d431df09e238c3e62b2d4`
   (`ak_...`), created directly against this project's org with
   `permissions: [{resource: "functions", actions: ["create","read","update","delete"]}]` -
   the minimum grant the `/execute` and `/executions/:id` routes require. This key lives ONLY
   as the server-only `MUDBASE_FUNCTIONS_API_KEY` env var (never `NEXT_PUBLIC_`), used
   exclusively by `src/lib/server/functionInvoke.ts`.
3. **The LLM completion call happens in the one place with a real network stack: the Next.js
   Route Handler.** `POST /api/ask` (`src/app/api/ask/route.ts`) is genuinely the only
   server-side code in this app, and it exists purely because of constraints #1 and #2 above -
   it is not "custom backend business logic" in the sense the other showcase apps avoid; it's
   the unavoidable consequence of two documented platform limits. Its job is narrowly scoped:
   validate the request, invoke the Function (`functionInvoke.ts`), then make one grounded
   completion call to Anthropic's Claude API (`src/lib/server/llm.ts`) using
   `ANTHROPIC_API_KEY` (server-only, never `NEXT_PUBLIC_`, never inside the Function's env -
   it would be unusable there per constraint #2).
4. **Full request flow:**
   - Client scores all loaded documents by keyword overlap (`src/lib/retrieval.ts`,
     `scoreDocuments`), takes the top 5, truncates each to 4000 chars, sends `{ question,
     candidates }` to `POST /api/ask`.
   - The route validates the body against `AskRequestSchema` (`src/lib/ask-schema.ts`), calls
     `invokeRetrievalFunction()` which POSTs to
     `/api/functions/projects/:projectId/functions/:functionId/execute` with
     `X-API-Key: <MUDBASE_FUNCTIONS_API_KEY>`, gets back `{ executionId, status: "queued" }`,
     and polls `GET .../executions/:executionId` every 600ms (20s timeout) until `status` is
     `success`/`failed`/`timeout`.
   - On success, the Function's `{ contextBlock, citations, usedCount }` result feeds
     `generateGroundedAnswer()`, which calls `client.messages.create()` (Anthropic SDK,
     `claude-opus-5` by default, overridable via `LLM_MODEL`) with a system prompt instructing
     the model to answer only from the provided excerpts and cite them by title.
   - The route returns `{ answer, citations, usedCount }` (validated against
     `AskResponseSchema` client-side too).
   - The client then logs `{ queryText, resultCount: citations.length, userId?,
     userName? }` to `search_log` - `userId` is only included when `useAuth().user.id` is a
     real signed-in user's ObjectId, never a placeholder.

### LLM provider choice

**Anthropic Claude**, via the official `@anthropic-ai/sdk`. Model defaults to `claude-opus-5`,
overridable with the `LLM_MODEL` env var (e.g. `claude-sonnet-5` or `claude-haiku-4-5` for a
cheaper/faster demo). See `web/README.md` "LLM setup" for exactly how a developer running this
app supplies their own key.

### Known limitation, honestly documented

No real `ANTHROPIC_API_KEY` was available in the environment this was built and smoke-tested in.
The full request/response contract is wired up and verified end-to-end up to the point of the
actual LLM call (see "Live smoke test results" below) - the Mudbase Function deployment,
invocation, polling, and retrieval-ranking are all confirmed working against the real, live
Mudbase project. The LLM completion step itself fails with a clear, expected
"ANTHROPIC_API_KEY is not configured" error rather than any fabricated success.

## Live smoke test results (2026-08-01, real project)

1. **Function deployment** - confirmed via direct `curl` against `cloud.mudbase.dev` using the
   provisioned `ak_...` key:
   - `POST /api/functions/projects/6a6d3faad07caabbbdfc5698/functions/6a6d431ef09e238c3e62b2f4/execute`
     with a real payload (`question: "How do I reset my password?"`, two candidate documents)
     → `202 { success: true, data: { executionId, status: "queued" } }`.
   - Polling `GET .../executions/<id>` → `status: "success"`, `durationMs: 54`, and a `result`
     that correctly ranked "Password Reset Guide" (score 11) over "Billing FAQ" (filtered out,
     score 0) and built a `contextBlock` containing exactly that document's content.
   - This proves the full deploy → invoke → poll → result pipeline for real, against production
     Mudbase infrastructure - not a mock.
2. **App-level smoke test, full login (2026-08-01, after the shared account's auth rate limit
   cleared)**:
   - `POST /api/auth/local/login` with `docs.member.demo@gmail.com` → real access + refresh
     token pair for a real, `emailVerified: true`, `customRole: "customer"` user
     (`_id 6a6d409a51703cd1071b46fe`).
   - Created 3 real documents with distinct content ("Password Reset Guide", "Billing and
     Invoices FAQ", "API Rate Limits") via `POST .../collections/<documentsId>/data` - all
     succeeded, `GET .../data?sort=-createdAt` lists all 3 correctly.
   - Full CRUD verified on a 4th throwaway document: create → `GET` single doc → `PATCH` update
     → `DELETE` → confirmed `404` afterward. Ownership-scoped edit/delete in the UI relies on
     this exact request shape.
   - `search_log` write verified with the real signed-in user's ObjectId as `userId` (never a
     placeholder) - `POST .../collections/<searchLogId>/data` succeeded, entry lists correctly.
   - **`POST /api/ask` against the running dev server**, with the question "How do I reset my
     password?" and all 3 real documents as candidates: the request took 5.4s (confirming it
     drove the full execute → poll-until-success cycle against the real Function, not a
     short-circuit) and failed only at the final LLM call with the expected, documented
     `"ANTHROPIC_API_KEY is not configured"` error (502) - proving the entire pipeline
     (retrieval scoring → Function invocation → polling → result → handoff to the LLM call) is
     wired correctly end-to-end, with the LLM step itself gated only by the intentionally-unset
     API key.

## Known limitations (real platform constraints, not bugs)

- **No public/anonymous read without a session.** Every collection read requires a JWT
  (anonymous or real) - confirmed live, see "Data model" above.
- **The project's `pk_` publishable key is not a working credential** on this backend version
  (same finding as the sibling `mudbase-showcase-social` app) - kept in `.env.example` for
  parity with the dashboard, unused by any request.
- **The Ask AI LLM call cannot live inside the Mudbase Function** - see "Ask AI architecture"
  above. This is the single largest architectural deviation from the most obvious design, and
  it is a hard platform constraint (verified against `isolated-vm` sandbox source), not a
  choice made for convenience.
- **No `ANTHROPIC_API_KEY` in the build/test environment** - the Ask AI feature is fully wired
  and will work once a developer supplies their own key (see README "LLM setup"); it was not
  possible to test a real generated answer in this environment.
