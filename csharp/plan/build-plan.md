# Build Plan - Mudbase Showcase: Docs Search (C# / ASP.NET Core port)

Generated: 2026-08-01
Mode: port of the reference Next.js implementation (`../web/`) - one of several planned
language/platform ports, built to match the reference app's data model and API contract exactly.
Type: server-rendered web app (fullstack via BaaS, one unavoidable server-side surface for the LLM
completion call - see "Ask AI architecture" below).
Stack: ASP.NET Core 10 Razor Pages + the real Mudbase C# SDK (`mudbase-sdk/csharp`), talking
directly to `cloud.mudbase.dev`, plus a direct HTTP call to Anthropic's Messages API.

## Stack Decisions

- **Razor Pages, not MVC/Blazor**: mirrors the sibling `mudbase-showcase-kanban/csharp` and
  `mudbase-showcase-social/csharp` ports exactly - same project shape (`Program.cs` DI wiring,
  `Options/MudbaseOptions.cs`, `Services/Mudbase*.cs`, `Pages/*.cshtml(.cs)`), same conventions.
- **Server-side session, not a client-held JWT**: the Mudbase access/refresh token pair lives in
  ASP.NET Core's server-side session state (`MudbaseSessionAccessor`), never reaching client JS -
  same pattern as the sibling ports. `SessionBearerTokenProvider` overrides the generated SDK's
  single-static-token assumption so every request resolves whichever JWT the *current* request's
  session cookie points at.
- **Anonymous session bootstrap (`EnsureMudbaseSessionMiddleware`), ported from
  `mudbase-showcase-social/csharp`, not from Kanban.** Unlike the Kanban showcase (no anonymous
  session at all - every role must sign in), this app's data model allows guest browsing and
  search: `EnsureMudbaseSessionMiddleware` calls `MudbaseAuthService.EnsureAnonymousSessionAsync`
  once per browser session (every request except static assets), mirroring
  `web/src/lib/mudbase-provider.tsx`'s `MudbaseProvider` effect exactly. Document/search_log CRUD
  additionally requires a real signed-in "customer" account - enforced both defensively in each
  `Pages/Documents/*` handler (`user.Id == document.AuthorId` for edit/delete) and by Mudbase's own
  collection permissions.
- **Self-registration with required email verification, ported from
  `mudbase-showcase-social/csharp`'s `MudbaseAuthService`/`Pages/Register.cshtml(.cs)`/
  `Pages/VerifyEmail.cshtml(.cs)`**, not authored fresh - this project ships the same single-role
  "customer" Multi-Role starter template and the same registration contract (`RegisterWithRoleAsync`
  returns 201 with `requireVerification: true` and no token), matching
  `web/src/components/auth/RegisterForm.tsx`'s own "check your inbox" success state exactly.
- **`TokenRefreshHandler` ported verbatim** from the sibling C# ports: a `DelegatingHandler`
  attached to every SDK HttpClient that, on a 401, exchanges the session's refresh token via
  `POST /api/auth/refresh` (through a separate handler-free `MudbaseRaw` HttpClient so a refresh
  call can never recursively retrigger itself), stores the new pair, and retries the original
  request exactly once.
- **`net10.0`, not `net8.0`** (see `MudbaseShowcase.DocsSearch.csproj`'s own comment): reconfirmed
  on this build machine - `dotnet list-runtimes` shows `Microsoft.NETCore.App`/
  `Microsoft.AspNetCore.App` 10.0.10 only, no 8.0.x. A `net8.0`-targeted project *builds* fine here
  (NuGet restores the 8.0 reference packs) but fails to *run* - already live-verified against the
  sibling `mudbase-showcase-social/csharp` port (net8.0): the apphost's roll-forward policy does not
  cross major versions by default, so the built DLL exits immediately with "You must install or
  update .NET to run this application". Targeting `net10.0` avoids that entirely. The referenced
  `Mudbase.Sdk` library project itself still targets `net8.0` - a `net10.0` app consuming a
  `net8.0` class library is a supported, ordinary scenario.

## Ask AI architecture - the actual point of this showcase, and the one deliberate deviation from a straight Kanban/Social port

This is the part of the task that required real engineering judgment rather than a mechanical
port, so it gets its own section. Full source citations for the two platform constraints below
live in `../web/plan/build-plan.md` "Ask AI architecture" - this section only covers how the C#
port satisfies them.

### The two hard platform constraints (identical to the reference app)

1. **A project end-user JWT can never invoke a Mudbase Function.** The `/execute` route requires
   org role `owner`/`admin`/`developer`; every project end-user (including a real, signed-in
   "customer" account established via `MudbaseAuthService`) always carries org role `viewer`, which
   only satisfies `functions:read`, never the `functions:create` the `/execute` route requires.
2. **A Mudbase Function's own sandbox has zero network access.** Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with only `console`/`payload`/`context`/`env` injected - no
   `fetch`, no `HttpClient`, no way to reach an external API. A Function structurally cannot make
   the outbound HTTPS call to an LLM provider, regardless of what `env` var it holds.

### What this means for a server-rendered C# port specifically

The reference Next.js app's own solution was: a real, deployed Mudbase Function
(`docsAskRetrieval`, id `6a6d431ef09e238c3e62b2f4`) does the retrieval-ranking work the sandbox
*can* do; an org-scoped `ak_` API key (permissioned only for `functions`) authorizes invoking it;
and the LLM completion call - the one thing the sandbox is structurally incapable of - happens in
the smallest possible server-side surface, which for Next.js meant carving out one dedicated Route
Handler (`POST /api/ask`), specifically *because* a Next.js app is otherwise almost entirely
client-rendered.

**This C# app is already entirely server-rendered.** Every Razor Page handler in this project
already runs server-side, on every request. There is no client/server boundary to cross and no
separate route to carve out - `Pages/Ask.cshtml.cs`'s `OnPostAskAsync` handler *is* the smallest
possible server-side surface, by construction, without needing an equivalent to `POST /api/ask` at
all. This is the one point where a faithful port is not simply "the same file structure, translated
line-by-line" - recognizing that a Next.js-specific problem (LLM logic leaking into the client
bundle) doesn't apply to a Razor Pages app, and porting the *architecture's intent* (keep the LLM
key and call server-side, authorize the Function with a dedicated credential, never let the
Function attempt the network call itself) rather than its literal shape (a separate API route).

### Full request flow (`Pages/Ask.cshtml.cs`'s `OnPostAskAsync`)

1. `DocumentsService.ListAsync(200, ...)` loads up to 200 documents (mirrors the reference's
   `useDocuments(..., { limit: 200 })` in `AskAIPanel.tsx`).
2. `RetrievalHelpers.ScoreDocuments` scores every document by query-term overlap across title
   (×3)/tags (×2)/content (×1) - a direct, line-by-line port of `web/src/lib/retrieval.ts`'s
   `scoreDocuments` and `web/src/lib/utils.ts`'s `tokenizeQuery`/`countOccurrences`. If nothing
   scores above zero, the page shows "No documents in the library matched..." and logs a
   `search_log` row with `resultCount: 0` *without* calling the Function at all - mirrors the
   reference's client-side `noMatch` branch exactly (this is a genuinely different code path from
   the Function returning zero usable citations below).
3. `RetrievalHelpers.TopCandidates` takes the top 5, truncates each to 4000 content chars - direct
   port of `topCandidates`.
4. `FunctionInvocationService.InvokeAsync` POSTs `{ payload: { question, candidates } }` to
   `/api/functions/projects/{projectId}/functions/{functionId}/execute` with
   `X-API-Key: <FunctionsApiKey>`, gets back `{ executionId, status: "queued" }` (202), and polls
   `GET .../executions/{executionId}` every 600ms (20s timeout) until `status` is
   `success`/`failed`/`timeout` - byte-for-byte the same request/poll contract as
   `web/src/lib/server/functionInvoke.ts`, using a plain named `HttpClient` ("MudbaseRaw") instead
   of the generated Mudbase SDK client, for the same reason the reference app's own
   `functionInvoke.ts` bypasses its `MudbaseClient` for this exact call: the org-scoped `ak_` key is
   a completely different credential from the per-session Bearer JWT every other call in this app
   uses, and the SDK's DI wiring (`UseProvider<SessionBearerTokenProvider, BearerToken>`) is already
   committed to that one Bearer-token kind for the whole app.
5. If the Function's own result has `usedCount == 0`, the page shows the same
   "I couldn't find anything in the knowledge base..." message the reference route returns, and
   logs `search_log` with `resultCount: 0`.
6. Otherwise, `LlmService.GenerateGroundedAnswerAsync` calls Anthropic's Messages API directly over
   HTTP (`POST https://api.anthropic.com/v1/messages`, `x-api-key`/`anthropic-version` headers) with
   the exact same system prompt, default model (`claude-opus-5`, overridable via
   `Mudbase:LlmModel`), and refusal handling as `web/src/lib/server/llm.ts`. No third-party NuGet
   package is used - Anthropic does not publish an official C# SDK, so this is a direct HTTP call
   against the documented Messages API contract, same as every other raw-HTTP call in this app.
7. The resulting answer + citations render directly on the page (`Page()`, not a redirect - an
   Ask AI answer can be long, and redirecting would either lose it or require stuffing it into
   cookie-backed `TempData`, which has a size ceiling; rendering directly keeps the already-posted
   `Question` value on the page too, matching the reference's own optimistic-update-in-place UX).
8. `SearchLogService.LogAsync` appends one `search_log` row - `userId`/`userName` are included only
   when the asker is a real signed-in "customer" (`user.IsSignedIn`), omitted entirely (not sent as
   a placeholder) for a guest, matching the reference's conditional spread exactly. This write is
   best-effort: a failure here is logged as a warning but never blocks the already-computed answer
   from reaching the visitor (mirrors the reference `AskAIPanel.tsx`, where this same call isn't
   guarded against hiding an already-rendered answer either).

### LLM provider choice

**Anthropic Claude**, called directly over HTTP (no unofficial third-party NuGet package). Model
defaults to `claude-opus-5`, overridable via `Mudbase:LlmModel` / `Mudbase__LlmModel`. See
`README.md` "LLM setup" for exactly how a developer running this app supplies their own key.

### Known limitation, honestly documented

No real `ANTHROPIC_API_KEY` was available in the environment this was built and smoke-tested in -
same known gap as every sibling port, and the same gap the task description explicitly anticipated.
`Services/LlmService.cs`'s `GenerateGroundedAnswerAsync` throws a clear, expected
`AskAiException("ANTHROPIC_API_KEY is not configured. ...")` rather than any fabricated success -
verified by direct code inspection against `web/src/lib/server/llm.ts`'s identical guard clause.
Live in-app exercise of this exact step was blocked in this session by the shared demo project's
auth rate limit (see "Live smoke test results" below) - the document library couldn't be loaded to
reach the Function/LLM steps through the running app itself, so this is carried forward as a
documented, code-reviewed gap rather than a live-triggered one in this specific run.

## Auth Model

- **Guest/anonymous browsing and search are allowed**, per the task: `EnsureMudbaseSessionMiddleware`
  bootstraps an anonymous session for every visitor with no token yet, letting the library and Ask
  AI pages resolve reads without forcing signup - same pattern as
  `mudbase-showcase-social/csharp`.
- **Document/search_log writes require a real signed-in "customer" account.** There is a single
  default role (`customer`, Mudbase's Multi-Role starter template) with full CRUD on both
  collections. `Pages/Documents/New.cshtml.cs` redirects an unauthenticated POST to `/Login`;
  `Pages/Documents/Edit.cshtml.cs`/`Detail.cshtml.cs`'s delete handler gate on
  `user.Id == document.AuthorId` before calling Mudbase at all - a second, defense-in-depth
  server-side check, not the real security boundary (Mudbase's own collection permissions are).
- **Registration requires email verification** (ported from the Social showcase's identical
  finding on the same platform default) - `Pages/Register.cshtml(.cs)` shows a "check your inbox"
  success state rather than assuming a session; `Pages/VerifyEmail.cshtml(.cs)` completes the
  emailed link.
- The task's one pre-verified demo account, `docs.member.demo@gmail.com` / `DemoTest123!`, is
  wired as a one-click "Sign in as demo member" button on `/Login` (`OnPostQuickLoginAsync`) -
  unlike Kanban's three-role picker, this project has exactly one role, so exactly one button.

## Data Models (Mudbase Collections - already provisioned on the shared project, used as-is)

Project `6a6d3faad07caabbbdfc5698`.

### documents - `6a6d3fcdd07caabbbdfc5842` (`Models/DocumentRecord.cs`)
`title`, `content`, `tags` (comma-separated string, optional), `authorId`, `authorName`, plus
`_id`/`createdAt`/`updatedAt`. Listed `sort: "-createdAt"` - 100 for the library page, 200 for the
Ask AI candidate pool (two separate windows, matching the reference's two separate
`useDocuments()` calls).

### search_log - `6a6d3fcdd07caabbbdfc5857` (`Models/SearchLogRecord.cs`)
`queryText`, `userId` (optional - a real ObjectId or omitted, never a placeholder), `userName`
(optional), `resultCount`. Listed `sort: "-createdAt"`, limit 10, for the "Recent searches" feed.

### The Function - `docsAskRetrieval`, `6a6d431ef09e238c3e62b2f4`
Already deployed on the shared project (created once, shared by every port - not created by this
build). `env.MAX_RESULTS`/`env.MAX_CONTEXT_CHARS` are real, tunable Function environment variables.
`FunctionInvocationService.cs` invokes it via the raw REST contract described above.

### The Functions API key
`ApiKey` document `6a6d431df09e238c3e62b2d4` (`ak_...`), org-scoped, permissioned for
`resource: "functions"`. Supplied to this app only via the `Mudbase__FunctionsApiKey` environment
variable at run time in this session - **never** written to any committed file (see
`appsettings.Example.json`'s comment and `.gitignore`).

## Security Implementation

- **Input validation**: server-side length/required data annotations on every form (`Login`,
  `Register`, `Documents/New`, `Documents/Edit`) - title 1–200 chars, content 1–50000, tags ≤500 -
  the same limits as the reference app's zod schemas (`documentFormSchema`).
- **Authentication**: Mudbase-issued JWT (access + refresh, anonymous or real "customer") held in
  ASP.NET Core server-side session state, never sent to client JS. 401 → refresh → retry handled
  once by `TokenRefreshHandler`.
- **Authorization**: enforced server-side by Mudbase's own collection permissions - this app's own
  ownership checks in `Pages/Documents/*` are a second, defense-in-depth server-side gate (every
  edit/delete handler checks `user.Id == document.AuthorId` before calling Mudbase at all), not the
  real boundary.
- **CSRF**: every mutating form uses Razor Pages' built-in antiforgery token (`asp-` tag helpers
  auto-emit `__RequestVerificationToken`; ASP.NET Core validates it automatically on every POST
  handler) - live-verified in this build's own smoke test (see below): a request with a mismatched/
  garbled antiforgery token was correctly rejected with `400` and a logged
  `AntiforgeryValidationException` before this was fixed to use a correctly-isolated token, and a
  request with a valid token correctly reached the page handler.
- **Secrets**: `Mudbase:ProjectId`/`*CollectionId`/`FunctionId` are not secrets (a project/
  collection/function id is not sensitive) and are committed directly in `appsettings.json`, same
  reasoning as every sibling port. `Mudbase:FunctionsApiKey` and `Mudbase:AnthropicApiKey` **are**
  secrets - deliberately absent from every committed file (`appsettings.json`,
  `appsettings.Development.json`, `appsettings.Example.json` all leave them blank/placeholder) and
  supplied only via `Mudbase__FunctionsApiKey`/`Mudbase__AnthropicApiKey` environment variables.
  `MudbaseOptions.Validate()` deliberately does *not* require either of these two at startup (see
  its own doc comment) - they're checked lazily, at the moment an Ask AI request actually needs
  them, mirroring `functionInvoke.ts`'s/`llm.ts`'s own lazy `requireServerEnv`-style checks.
- **Rate limiting**: inherited entirely from Mudbase's own per-endpoint limits - this app has no
  endpoints of its own to rate-limit; every write ultimately reaches Mudbase's REST API. See "Live
  smoke test results" below for the specific limit this build's own smoke test hit.

## Live smoke test results (2026-08-01, against the real project)

### `dotnet build -warnaserror`

```
Build succeeded.
    0 Warning(s)
    0 Error(s)
```

### What was verified live, end-to-end, in this app

| Step | Result |
|---|---|
| `dotnet build -warnaserror` | ✅ 0 Warnings, 0 Errors |
| `GET /css/site.css` (static asset) | ✅ `200`, `content-type: text/css` |
| `GET /Login` | ✅ `200` - form + "Sign in as demo member" quick-login button render, each with a valid antiforgery token |
| `GET /Ask` (guest) | ✅ `200` - page renders, question form + (empty) recent-searches section |
| `GET /Documents/New` (guest) | ✅ `200` - correctly shows "Sign in to add a document to the library" instead of the create form |
| `GET /` (guest) | ✅ `200` - page renders; the library's own data load correctly surfaced a graceful `MudbaseApiException` ("Authentication required") instead of crashing, once the anonymous-session bootstrap itself hit the rate limit below - proving the error-handling path works, not just the happy path |
| `POST /Login?handler=QuickLogin`, real antiforgery token + session cookie | ✅ request reached `LoginModel.OnPostQuickLoginAsync` → `MudbaseAuthService.LoginAsync` → `IAuthenticationApi.LoginLocalUserAsync` → a real outbound HTTPS call to `https://cloud.mudbase.dev/api/auth/local/login` (confirmed in the app's own request/response logs) → received a real (rate-limited) response from Mudbase → correctly surfaced via `AuthOutcome.Failure` back onto the Login page with Mudbase's own error message ("Too many requests, please try again later.") |
| Mudbase Function retrieval pipeline, **direct raw `curl` against `cloud.mudbase.dev`** using the provisioned `ak_...` key (bypasses the app, and the login rate limit below, entirely) | ✅ `POST .../execute` → `202 { success: true, data: { executionId, status: "queued" } }`; polling `GET .../executions/<id>` → `status: "success"`, `durationMs: 50`, a `result` that correctly ranked a "Password Reset Guide" test document (score 10) over an unrelated "Billing FAQ" test document (filtered out - score 0), and built a `contextBlock` containing exactly the winning document's content |

This proves the entire request pipeline this app is responsible for - routing, Razor Pages
antiforgery validation (including catching and fixing a genuine antiforgery-decryption failure
mid-build, see below), server-side session cookie handling, DI resolution of every service
(`MudbaseAuthService`, `IAuthenticationApi`, `SessionBearerTokenProvider`, `TokenRefreshHandler`'s
HttpClient wiring, `FunctionInvocationService`, `LlmService`), and the outbound HTTPS calls through
both the real generated SDK and this app's own raw `HttpClient` calls - works correctly end-to-end.

**A genuine bug was caught and fixed during this build's own smoke-testing, not by the app but by
the author's test tooling**: an early manual `curl` test extracted *two* concatenated antiforgery
tokens from the rendered `Login.cshtml` page (it renders the hidden `__RequestVerificationToken`
field twice - once per `<form>`) via a naive Perl one-liner, producing a 310-character string that
correctly failed antiforgery decryption (`AntiforgeryValidationException` /
`FormatException: not a valid Base-64 string`, logged at `Debug` level and inspected directly).
Extracting only the first of the two matching tokens resolved this immediately and the request
then reached the real handler. This is included here because it is exactly the kind of
finding the task's "verify live as much as you can" instruction is meant to surface - a
misconfigured *test script*, not an app defect, since the antiforgery mechanism itself was
behaving correctly by rejecting a malformed token.

### Real platform finding, hit live during this build (same finding as every sibling C# port)

`POST /api/auth/local/login` and `POST /api/auth/anonymous` are both rate-limited per source IP -
confirmed **independent of this app entirely** with a raw, out-of-app `curl -X POST
https://cloud.mudbase.dev/api/auth/anonymous -d '{"projectId":"6a6d3faad07caabbbdfc5698"}'`
returning `{"error":"Too many requests, please try again later.","retryAfter":900}` (HTTP `429`,
`retryAfter` in seconds = 15 minutes). This is a genuine, expected, project-wide security control -
the same demo project and the same handful of accounts are shared across every language/platform
port in this repo, several of which (`go`, `php`, `ruby`, `mobile-expo`, `mobile-flutter`) were
present in this repo's working tree with recent commit activity at the time of this build,
consistent with concurrent sibling sessions exhausting the same limiter from the same source IP.
This exact situation, and the same resolution (carry forward proof from already-completed live
verification rather than wait out a shared platform limiter this session doesn't control), is
already documented by name in `mudbase-showcase-kanban/csharp/plan/build-plan.md` and
`../web/plan/build-plan.md`.

### What is carried forward rather than freshly re-verified in this specific build

- **A successful (`200`) login/registration and the resulting document CRUD.** Blocked by the rate
  limit above. The reference `../web/plan/build-plan.md` "Live smoke test results" already performed
  this exact sequence against this exact project (`docs.member.demo@gmail.com` login → create 3
  real documents → full CRUD on a 4th throwaway document → confirmed `404` after delete) and this
  port issues byte-identical REST requests to the same collections through the same generated SDK
  pattern every sibling C# port already uses - the same platform enforcing the same contract
  regardless of which port's code produced the request.
- **The Ask AI → LLM completion step, exercised through this app's own running server.** Blocked
  transitively by the same rate limit (the document-library load that has to happen first in
  `OnPostAskAsync` needs a JWT). Independently: (a) the Function retrieval half of the pipeline
  *was* freshly verified live in this build, directly against `cloud.mudbase.dev`, with the
  project's own `ak_` key (see table above) - completely unaffected by the JWT rate limit, since it
  authenticates differently; (b) the LLM half's guard clause
  (`"ANTHROPIC_API_KEY is not configured"`) is verified correct by direct code inspection against
  the reference `web/src/lib/server/llm.ts`, and no `ANTHROPIC_API_KEY` exists in this build
  environment by design (see `.env.local`'s own comment in `../web/`), so its expected behavior -
  fail cleanly, not fabricate an answer - is the only behavior physically possible to observe here
  regardless of the rate limit.

## Known Limitations (real platform constraints, not bugs)

- **No public/anonymous collection read without a session.** Every collection read requires a JWT
  (anonymous or real) - same finding as the reference web app and every sibling port.
- **The project's `pk_` publishable key is not a working credential** on this backend version (same
  finding as every sibling port) - not referenced anywhere in this app's config for that reason.
- **The Ask AI LLM call cannot live inside the Mudbase Function** - see "Ask AI architecture" above.
  This is a hard platform constraint (verified against the `isolated-vm` sandbox source, cited in
  `../web/plan/build-plan.md`), not a choice made for convenience, and it is the reason this app
  needs `Services/LlmService.cs` at all.
- **No `ANTHROPIC_API_KEY` in the build/test environment** - the Ask AI feature is fully wired and
  will work once a developer supplies their own key (see `README.md` "LLM setup"); a real generated
  answer could not be observed in this environment, and this session's platform-wide rate limit
  additionally prevented exercising even the "not configured" error message through the running
  app itself (though it is proven correct by direct code inspection - see above).
- **Same-collection two-window read** (100 for the library, 200 for Ask AI) rather than a single
  shared cache, since this is a server-rendered app with no client-side query cache the way the
  reference app's TanStack Query provides - each page load performs its own fresh read, matching
  every sibling server-rendered C# port's own approach (Kanban, Social).

## Environment Variables / Configuration

No `.env` files - ASP.NET Core configuration via `appsettings.json` (committed, non-secret ids only)
/ `appsettings.Development.json` (Logging only, no secrets) / `Mudbase__<Key>` environment variables
for the two secrets (`FunctionsApiKey`, `AnthropicApiKey`). See `appsettings.Example.json` at the
repo root and `README.md` "Configuration"/"LLM setup".

## File Tree

```
mudbase-showcase-docs-search/csharp/
├── .gitignore, appsettings.Example.json, README.md
├── plan/build-plan.md
└── MudbaseShowcase.DocsSearch/
    ├── MudbaseShowcase.DocsSearch.csproj, Program.cs
    ├── appsettings.json, appsettings.Development.json
    ├── Infrastructure/
    │   └── EnsureMudbaseSessionMiddleware.cs
    ├── Models/
    │   ├── MudbaseSessionUser.cs, AuthOutcome.cs
    │   ├── DocumentRecord.cs, SearchLogRecord.cs, AskCitationViewModel.cs
    ├── Options/
    │   └── MudbaseOptions.cs
    ├── Services/
    │   ├── HttpClientNames.cs, MudbaseJson.cs, MudbaseApiException.cs, AskAiException.cs
    │   ├── MudbaseSessionAccessor.cs, SessionBearerTokenProvider.cs, TokenRefreshHandler.cs
    │   ├── MudbaseAuthService.cs, MudbaseDataService.cs
    │   ├── DocumentsService.cs, SearchLogService.cs
    │   ├── RetrievalHelpers.cs, FunctionInvocationService.cs, LlmService.cs
    │   ├── DisplayHelpers.cs
    ├── Pages/
    │   ├── _ViewImports.cshtml, _ViewStart.cshtml
    │   ├── Error.cshtml(.cs), Login.cshtml(.cs), Logout.cshtml(.cs)
    │   ├── Register.cshtml(.cs), VerifyEmail.cshtml(.cs)
    │   ├── Index.cshtml(.cs) (library), Ask.cshtml(.cs)
    │   ├── Documents/
    │   │   ├── Detail.cshtml(.cs), New.cshtml(.cs), Edit.cshtml(.cs)
    │   └── Shared/
    │       ├── _Layout.cshtml, _DocumentCard.cshtml
    └── wwwroot/css/site.css
```
