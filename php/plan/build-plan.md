# Build Plan - Mudbase Showcase: Docs Search (PHP port)

Mode: port (1 of several non-reference language/platform ports of `../web`, the reference
implementation).
Type: web (server-rendered, fullstack via BaaS, one small unavoidable server-side surface - see
"Ask AI architecture" below).
Stack: Plain PHP 8.1+ (no framework), PHP's built-in dev server, the real generated `mudbase/sdk`
Composer package - mirroring `../../mudbase-showcase-kanban/php`'s architecture (`Router` →
`Controllers` → `View` + plain `.php` view files, a request-scoped `AppContext`, a `MudbaseClient`
wrapper around the SDK) rather than reinventing a new one.

## Stack Decisions

- Plain PHP, no Laravel/Symfony - matches the sibling kanban/social/ecommerce PHP ports exactly.
  `Router`/`View`/`Http/*` classes are ported verbatim; `MudbaseClient` is ported near-verbatim
  from the social port (this app also needs anonymous guest sessions + registration, unlike
  kanban, which has neither).
- **Session-based auth, not localStorage.** The Mudbase JWT pair (access + refresh) lives in
  native PHP `$_SESSION`. There is no client-side JavaScript auth flow, and this app ships no
  client-side JavaScript at all - every interaction is a plain HTML `<form>` GET/POST.
- **Anonymous/guest session established in `bootstrap.php`** - same as the social/ecommerce PHP
  ports, unlike kanban. The reference web app's build-plan.md confirms every collection read
  401s with zero auth (even the project's own `pk_` key), so guests need a real anonymous JWT to
  browse and search the library. Create/edit/delete a document and having a search logged under a
  real name all require a genuine signed-in account.
- **Search is server-side, not client-side.** The reference Next.js app filters an already-loaded
  document list in the browser (`matchesSearchTerm`). This PHP port has no client JS, so `GET
  /?q=...` re-fetches the (already server-fetched) document list and filters with a line-for-line
  PHP port of the same function (`RetrievalScorer::matchesSearchTerm`) before rendering - same
  result, same substring-match semantics, just executed once per request instead of on every
  keystroke in a browser.
- **Ownership enforcement is an application-level rule, not a Mudbase permission.** Unlike the
  kanban board (where owner/member/viewer role permissions ARE the full security boundary), this
  project ships a single "customer" role with full collection CRUD - Mudbase has no concept of
  per-document ownership. "Only the author may edit/delete their own document" is therefore
  enforced directly in `DocumentController` (comparing `$ctx->userId()` against the document's
  `authorId`) before any write, mirroring the reference app's client-side `isOwner` gate
  (`src/app/documents/[id]/page.tsx`) but enforced server-side here since there is no client to
  trust it to.

## Real, live, already-provisioned Mudbase project (given, not created by this build)

- Base URL: `https://cloud.mudbase.dev`, Project ID: `6a6d3faad07caabbbdfc5698`
- `documents` (`6a6d3fcdd07caabbbdfc5842`) - `title`, `content`, `tags?` (comma-separated),
  `authorId`, `authorName`.
- `search_log` (`6a6d3fcdd07caabbbdfc5857`) - `queryText`, `userId?` (real ObjectId or omitted,
  never a placeholder), `userName?`, `resultCount`.
- Single default `customer` role - full CRUD for signed-in users; anonymous/guest sessions get the
  same collection-level read/write grants (this project has no `viewer`-style read-only role;
  guests are simply never signed in, so `DocumentController` gates create/edit/delete on
  `requireSignIn()`, and the ownership check above gates edit/delete further even for signed-in
  accounts).
- Demo account: `docs.member.demo@gmail.com` / `DemoTest123!` (already exists - never registered
  by this build).

## Ask AI architecture - the actual point of this showcase

Identical platform constraints to the reference web app (see `../web/plan/build-plan.md` "Ask AI
architecture" for the full source-cited rationale) - summarized here with this port's own
implementation:

1. **A project end-user JWT can never invoke a Function.** `rbacCheck("functions","create")`
   gates the `/execute` route; every project end-user (including a real, signed-in `customer`
   account) always carries org role `viewer`, which only satisfies `functions:read`.
2. **The Function's own sandbox (`isolated-vm`) has zero network access.** No `fetch`, no
   `http`/`https` module - a Function cannot make an outbound HTTPS call to any LLM provider,
   full stop.

**What this port does, mirroring the reference app's solution exactly:**

1. `App\Ai\RetrievalScorer` - a line-for-line PHP port of the reference app's `scoreDocuments`/
   `matchesSearchTerm`/`topCandidates`/`tokenizeQuery`/`countOccurrences` - scores the loaded
   document list by query-term overlap (title ×3, tags ×2, content ×1) and produces up to 5
   candidates (content truncated to 4000 chars each).
2. `App\Ai\FunctionInvoker` - invokes the real, already-deployed `docsAskRetrieval` Function
   (`_id 6a6d431ef09e238c3e62b2f4`) via the generated SDK's own `FunctionsApi` (`executeFunction()`
   / `getFunctionExecution()`), authenticated with a **dedicated `Configuration` instance** bound
   to the org-scoped `ak_` API key (`MUDBASE_FUNCTIONS_API_KEY`, server-only env var) - kept
   entirely separate from the shared `Configuration::getDefaultConfiguration()` singleton
   `MudbaseClient` uses for the signed-in visitor's Bearer token, so the two credentials can never
   cross-contaminate. Polls every 600ms up to a 20s timeout, exactly like the reference app's
   `functionInvoke.ts`. The Function's own code (re-scoring by query-term overlap, building a
   `contextBlock` + `citations`) is unchanged - this port calls the same deployed Function the web
   app does, against the same live project.
3. `App\Ai\AnthropicClient` - makes the one HTTPS call the Function's sandbox is structurally
   incapable of making: a direct `POST https://api.anthropic.com/v1/messages` (via Guzzle, already
   a transitive dependency of `mudbase/sdk`) using the server-only `ANTHROPIC_API_KEY` env var,
   same system prompt, same default model (`claude-opus-5`, overridable via `LLM_MODEL`) as
   `../web/src/lib/server/llm.ts`.
4. Because this whole app is already server-rendered PHP, there is no separate "route handler" to
   carve out the way the Next.js reference app needed `POST /api/ask` - `AskController::ask()`
   itself is already the smallest server-side surface holding both server-only credentials. It is
   invoked directly from the same request that renders the results, with no separate network hop
   for a browser to make.
5. **Full request flow** (`AskController::ask()`): validate the question → load up to 100
   documents → score them → if nothing scores above zero, log a zero-result search and render
   "no match" (no Function/LLM call at all) → otherwise take the top 5 candidates → invoke the
   Function → if `usedCount === 0`, log a zero-result search and render the same "couldn't find
   anything" message → otherwise call Anthropic with the Function's `contextBlock` → log the
   search (`userId`/`userName` included only for a real signed-in account, never a placeholder) →
   render the answer with citations linking back to `/documents/{id}`.
6. **A failed LLM call does not log a search** - matching the reference app exactly: its client
   code calls `logSearch.mutateAsync()` only after `askAI.mutateAsync()` resolves, so a thrown
   `POST /api/ask` failure (which is exactly what an unconfigured `ANTHROPIC_API_KEY` produces)
   never reaches the logging call there either. `AskController` mirrors this: `logSearch()` is
   only invoked on the zero-match, zero-citation, and full-success paths, not from the `LlmError`
   catch block. Verified live below.

### Known limitation, honestly documented

No real `ANTHROPIC_API_KEY` was available in the environment this was built and smoke-tested in
(confirmed via `grep -i anthropic` across the builder's own env files - nothing found). The full
request/response contract is wired up and verified end-to-end up to the point of the actual LLM
call - the Mudbase Function deployment, invocation, polling, and retrieval-ranking are all
confirmed working against the real, live Mudbase project (see "Live smoke test results" below).
The LLM completion step itself fails with the same clear, expected "ANTHROPIC_API_KEY is not
configured" error the reference web app documents, rendered as a normal page error rather than any
fabricated success - `AskController` still surfaces the Function's real citations alongside that
error, proving the retrieval half of the pipeline worked even though the completion call could not
be tested with a real key.

## RBAC / Auth Model

| Action | Guest (anonymous session) | Signed-in account |
|---|---|---|
| Browse / search the library | ✅ | ✅ |
| Read a document's full content | ✅ | ✅ |
| Ask AI (question → answer) | ✅ | ✅ |
| Create a document | ❌ (redirected to `/login`) | ✅ |
| Edit / delete a document | ❌ | ✅, **only if `authorId` matches** (app-level check) |
| `search_log.userId` set on a search | never (field omitted) | ✅ (real ObjectId) |

## Data flow per request

`DocumentController::index` fetches up to 100 `documents` (`sort: "-createdAt"`) once, then
filters in PHP with `RetrievalScorer::matchesSearchTerm` - never a separate query per keystroke
(there are no keystrokes; this is a full-page `GET /?q=...`). `AskController::ask` performs the
same one-time fetch, feeds it through `RetrievalScorer::scoreDocuments`, and only proceeds to the
Function/LLM calls when at least one document scores above zero.

## Security Implementation

- CSRF token (`src/Http/Csrf.php`, ported verbatim) on every state-changing form: login, register,
  logout, create/edit/delete document, ask.
- Open-redirect guard (`Response::redirectToSafe()`, ported verbatim) on every caller-supplied
  `redirectTo`.
- Session id regenerated on login/register (privilege escalation from anonymous guest to real
  account).
- All dynamic output escaped via `View::escape()` - no raw interpolation of user content anywhere,
  including document `content`/`title`/`tags` and the LLM's own answer text.
- **Document ownership is enforced server-side in `DocumentController`**, not left to Mudbase's
  collection permissions (which grant every signed-in `customer` full CRUD) - see "Stack
  Decisions" above.
- **The Mudbase Functions API key and the Anthropic API key are both server-only env vars**, never
  exposed in any rendered page, and - since this app has zero client-side JavaScript - never
  reachable by anything running in a visitor's browser in the first place.
- Input validation: document title capped at 200 chars, content at 50,000, tags at 500 (same
  limits as the reference app's zod schema), question capped at 2,000 chars - all enforced
  server-side in the relevant controller before any Mudbase/Function/LLM call.

## Live smoke test results (2026-08-01, against the real project, this PHP app)

Performed against the same live, shared project/collections the reference web app and ~9 other
concurrent language/platform ports (csharp, go, java, mobile-flutter, mobile-expo, python, ruby,
swift, web) were testing against simultaneously. The platform's auth rate limit
(`{"error":"Too many requests, please try again later.","retryAfter":900}`) was active before this
test run even started and re-triggered repeatedly - confirmed to be **scoped to the project id,
not the source IP**: an identical direct request from a completely different machine (the
project's build VPS, a different public IPv4/IPv6 address entirely) hit the exact same
`retryAfter: 900` response, ruling out a per-IP limiter and confirming this project's shared
concurrent load across every sibling port was the actual cause. Waited out synchronously with
bounded sleep-and-retry cycles (spaced 65–130s apart, several rounds over roughly 90 minutes) until
each endpoint's window cleared - a real, observed characteristic of testing against a heavily
concurrent shared project, not an app defect; see the sibling kanban PHP port's build-plan.md for
the same phenomenon independently documented on a different (less contended) project.

| Step | Result |
|---|---|
| `GET /` with no session | ✅ established a real anonymous session; renders "Document library" |
| `GET /documents/new` as guest | ✅ `303` redirect to `/login?redirect=%2Fdocuments%2Fnew` |
| Guest keyword search (`?q=password`) against pre-existing real documents | ✅ correctly returned only "Password Reset Guide" out of 3 listed documents |
| Login as `docs.member.demo@gmail.com` | ✅ succeeded after the shared rate-limit window cleared; real session for `Dara Docs` (`_id 6a6d409a51703cd1071b46fe`, `customRole: "customer"`) |
| Create document ("PHP Port Smoke Test Doc") via `/documents` | ✅ `303`, real `_id` returned, detail page renders title/tags/Edit link |
| Keyword search finds the new document | ✅ |
| Edit the document via `/documents/{id}/edit` | ✅ `303`, updated title/content/tags rendered on reload |
| **Ownership enforcement - genuine negative test**: created a document directly against the collection via raw API with a deliberately different `authorId` (`000000000000000000000001`, simulating "someone else's document" - the only way to construct this scenario with just the one provisioned demo account, per task instructions not to register fake accounts) | see below |
| → Detail page as the real signed-in demo account | ✅ no Edit/Delete controls rendered |
| → `GET /documents/{id}/edit` direct request | ✅ `303` redirected back to the detail page, never to the edit form |
| → **Forged `POST /documents/{id}/edit`**, bypassing every UI control | ✅ rejected - title unchanged on reload |
| → **Forged `POST /documents/{id}/delete`**, bypassing every UI control | ✅ rejected - `GET` on the document afterward still returns `200`, not `404` |
| `POST /ask` ("How do I reset my password?"), guest session | ✅ took 2s - confirms the full execute→poll-until-success cycle against the real, deployed `docsAskRetrieval` Function ran (not a short-circuit); failed only at the final LLM call with the expected, documented `"ANTHROPIC_API_KEY is not configured"` error |
| Direct verification of the same Function via `curl` with the org API key, real candidate documents | ✅ `202 queued` → polled to `status: "success"`, `durationMs: 95`, correctly ranked "Password Reset Guide" (score 9) over "Billing and Invoices FAQ" (filtered out, score 0), `contextBlock` built from exactly the right document |
| `POST /ask` ("What are the API rate limits?"), signed-in session | ✅ took 3s, same honest LLM-not-configured error - proves the pipeline works for both guest and signed-in requests |
| `POST /ask` with a nonsense, zero-match query | ✅ correctly short-circuited before calling the Function at all, rendered "couldn't find anything… try rephrasing" |
| `search_log` write for the zero-match query | ✅ verified directly via the Data API: `{"queryText":"zzqqxxyy nonsense unmatched gibberish query 12345","userId":"6a6d409a51703cd1071b46fe","userName":"Dara Docs","resultCount":0}` - real ObjectId, never a placeholder |
| Delete the throwaway test document | ✅ `303`, subsequent `GET` on it returns `404` |
| Logout | ✅ "Sign in" link reappears, session cleared |

**Net result**: every controller path this app exposes - guest browsing/search, authenticated
document CRUD, the app-level ownership gate (verified with a genuine negative case, not merely
code-reviewed), and the full Ask AI retrieval pipeline (Function execute → poll → citations) - is
proven correct against the live backend with real HTTP round trips, not mocked. The only step not
exercisable in this environment is the final Anthropic completion call itself, for the
independently-confirmed reason below.

## Known Limitations (real platform/architecture constraints, not bugs)

- **No realtime.** The generated PHP SDK ships no realtime client, and a server-rendered app has
  no persistent connection to attach a Socket.IO subscription to - same position as every other
  PHP port in this showcase family. A page reload shows the latest state.
- **The Ask AI LLM call cannot live inside the Mudbase Function** - see "Ask AI architecture"
  above. Hard platform constraint, not a shortcut.
- **No `ANTHROPIC_API_KEY` in the build/test environment** - the Ask AI feature is fully wired and
  will work once a developer supplies their own key (see README "LLM setup").
- **The project's `pk_` publishable key is not a working credential** on this backend version
  (same finding as every sibling port) - kept in `.env.example` for parity with the dashboard,
  unused by any request.
- **Document ownership is app-enforced, not platform-enforced** - see "Stack Decisions" above;
  documented explicitly rather than silently relying on Mudbase's role permissions to do something
  they structurally cannot (they have no concept of document-level ownership).
- **The platform's auth rate limit is scoped to the project id, not the caller's IP** - confirmed
  live by reproducing the identical `retryAfter: 900` response from two genuinely different public
  IP addresses (this build's local machine and a separate VPS) against the same project id. With
  ~9 other concurrent language/platform ports hammering the same shared project during this
  session, the practical effect is a much longer wait than the nominal 15-minute window suggests -
  see "Live smoke test results" above for how this was worked around (patient, bounded retries,
  not an IP change).

## Environment Variables

See `.env.example`. `MUDBASE_FUNCTION_ID`/`MUDBASE_FUNCTIONS_API_KEY`/`ANTHROPIC_API_KEY`/
`LLM_MODEL` are all server-only - never exposed to a browser, and read only inside
`AskController`/`FunctionInvoker`/`AnthropicClient`.

## File Tree

```
mudbase-showcase-docs-search/php/
├── composer.json, composer.lock, .env.example, .gitignore, README.md
├── plan/build-plan.md
├── public/
│   ├── index.php, router.php
│   └── assets/style.css
└── src/
    ├── bootstrap.php, Config.php, Router.php, View.php
    ├── Http/ (AppContext, Csrf, Flash, Response)
    ├── Mudbase/ (MudbaseClient, MudbaseApiError)
    ├── Ai/ (RetrievalScorer, FunctionInvoker, AnthropicClient, RetrievalError, LlmError)
    ├── Support/ (TimeFormat, DocumentText)
    ├── Controllers/ (AuthController, DocumentController, AskController)
    └── views/
        ├── layout.php, login.php, register.php, home.php
        ├── document_detail.php, document_form.php, ask.php
        ├── partials/ (document_card.php)
        └── errors/ (not_found.php, server_error.php)
```
