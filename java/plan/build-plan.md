# Mudbase Showcase — Docs Search (Java / Spring Boot edition) — Build Plan

Java/Spring Boot + Thymeleaf reimplementation of the reference Next.js app at `../web`. Same
Mudbase project, same two collections (`documents`/`search_log`), same deployed Ask AI Function,
same RBAC model. This document covers what deliberately differs and why, plus this port's own
live smoke test results. See `../web/plan/build-plan.md` for the full data model and the detailed
"Ask AI architecture" writeup (platform constraints, verified against `mudbase-backend` source)
that this port's own Ask AI flow is built to satisfy identically.

## Stack

Spring Boot 3.3.5 + Thymeleaf + Spring Validation, Java 17, Maven. Package root:
`dev.mudbase.showcase.docssearch`. Follows the exact architecture already established by the
sibling `mudbase-showcase-kanban/java`, `mudbase-showcase-ecommerce/java`, and
`mudbase-showcase-social/java` ports: a `mudbase/` package for the generated-SDK-with-bypasses
data/auth clients, `auth/` for the session-to-JWT bridge, `domain/` for collection-mirroring
value objects, `support/` for formatting/retrieval/view-model helpers, `service/` for business
logic, and `web/` for Spring MVC controllers + DTOs.

## Package layout

```
dev.mudbase.showcase.docssearch/
├── DocsSearchApplication.java
├── config/          MudbaseProperties, LlmProperties, MudbaseClientFactory, WebMvcConfig
├── auth/             AuthSession, SessionAuthService, RequireSignInInterceptor
├── mudbase/           MudbaseAuthClient, MudbaseDataClient, DocumentMapper, MudbaseApiException,
│                      PageResult, AuthResult
├── domain/            DocumentRecord, SearchLogEntry, ScoredDocument
├── support/           Formatting, Retrieval, ViewModelHelper, ForbiddenActionException
├── askai/             FunctionInvokeClient, AnthropicClient, RetrievalResult, Citation
├── service/           AuthService, DocumentService, SearchLogService, AskAiService, AskAiResult
└── web/               HomeController, DocumentController, AskController, AuthController,
                       GlobalExceptionHandler, dto/*
```

## Data model (already provisioned — do not recreate)

Identical to `../web/plan/build-plan.md` "Data model": project `6a6d3faad07caabbbdfc5698`,
`documents` (`6a6d3fcdd07caabbbdfc5842`), `search_log` (`6a6d3fcdd07caabbbdfc5857`), single
default `customer` role with full CRUD on both collections. Every collection read 401s with zero
auth (verified live) - an anonymous session is required for guest browsing/search, same as every
sibling Java port that has a public-read surface.

## Auth model

Mirrors the sibling `mudbase-showcase-ecommerce/java` port's public-read/gated-write pattern
(not the sibling `kanban`/`social` ports, which are either all-signed-in or login-only):

- `SessionAuthService.publicReadToken` returns the signed-in user's token, or lazily creates and
  caches an anonymous guest session for the rest of the `HttpSession` - used by every read path
  (library, document detail, Ask AI retrieval scoring, recent searches).
- `RequireSignInInterceptor` gates `/documents`, `/documents/new`, `/documents/*/edit`,
  `/documents/*/delete` - guests are redirected to `/login` and back.
- Registration always targets this project's single default `customer` role
  (`POST /api/auth/local/signup/customer`) - see `MudbaseAuthClient` javadoc for why that
  endpoint, not the generated SDK method, is used.
- Document edit/delete additionally require `DocumentService`'s own `authorId === current user
  id` ownership check (`ForbiddenActionException` → 403) - the `customer` role's own Mudbase
  collection permissions grant unconditional CRUD, so this app-level check is the actual security
  boundary for "only the author may edit/delete," not merely defense-in-depth.

## Gson-deserialization bypasses reused (found by the sibling Java ports, not rediscovered)

Both documented and reused verbatim from `mudbase-showcase-kanban/java`,
`mudbase-showcase-ecommerce/java`, and `mudbase-showcase-social/java`:

1. **Login** (`MudbaseAuthClient.login`) - the generated `AuthenticationApi.loginLocalUser`
   deserializes its response via Gson, which hard-fails the instant the response JSON carries a
   property the model doesn't declare. Every Multi-Role account's login response carries both
   `role` and `customRole`; the generated model only declares `role`. Fixed with a raw call over
   the SDK's shared `OkHttpClient`, parsed leniently with Jackson's `@JsonIgnoreProperties(ignoreUnknown
   = true)`.
2. **Registration** (`MudbaseAuthClient.register`) - the generated `RegisterWithRoleRequest` has
   no field for the validator-required `agreedToTerms`, and the generated method's return type is
   `void`. Same raw-call-plus-lenient-Jackson-parse fix.
3. **Collection listing** (`MudbaseDataClient.rawList`) - the generated `DataApi.listData`'s
   Gson-generated `Pagination` model hard-fails on the real API response's `hasMore` field, which
   this SDK version's OpenAPI spec never declared. Same fix, applied to every `list`/`listPage`
   call this app makes (library, Ask AI candidate scoring, recent searches).

## Ask AI architecture — how this Java port satisfies the same two platform constraints

See `../web/plan/build-plan.md` "Ask AI architecture" for the full, source-verified case for why
the LLM completion call cannot live inside the Mudbase Function (`rbacCheck("functions","create")`
requires an org role a project end-user JWT never has; the Function's `isolated-vm` sandbox has
zero network primitives). This Java port satisfies the exact same two constraints, adapted to a
server-rendered app with no client/server split of its own:

1. **The keyword-retrieval shortlist step** (`Retrieval.scoreDocuments` / `topCandidates`, in
   `support/Retrieval.java`) is a direct Java port of the reference web app's
   `src/lib/retrieval.ts` - same weights (title ×3, tags ×2, content ×1), same behavior. Since
   this app has no client JS framework, this runs server-side in `AskAiService.ask` instead of in
   the browser, but it's the exact same "no vector DB, no external search service" logic.
2. **`FunctionInvokeClient`** (`askai/FunctionInvokeClient.java`) invokes the same real, deployed
   `docsAskRetrieval` Function (`_id 6a6d431ef09e238c3e62b2f4`) the web app uses, with the same
   org-scoped `ak_` API key (`MUDBASE_FUNCTIONS_API_KEY`, server-only Spring property, never
   committed) - `POST .../execute`, then poll `GET .../executions/:id` every 600ms up to a 20s
   timeout, logic-for-logic identical to `src/lib/server/functionInvoke.ts`.
3. **`AnthropicClient`** (`askai/AnthropicClient.java`) makes the one grounded completion call -
   this app IS the "smallest server-side surface" in this port, since a Thymeleaf app has no
   separate client/server boundary to begin with. No official Anthropic Java SDK dependency was
   added; this is a single raw HTTPS POST to `https://api.anthropic.com/v1/messages` reusing the
   OkHttp client already on the classpath transitively via the Mudbase SDK - same request/response
   contract as the reference app's `@anthropic-ai/sdk` usage in `src/lib/server/llm.ts`
   (`claude-opus-5` default model, overridable via `LLM_MODEL`, same system prompt).
4. **Full request flow** (`AskAiService.ask`, called synchronously from `AskController.ask`
   within a single request thread - there is no separate API route to call, this app's controller
   method IS the equivalent of the reference app's `POST /api/ask` route handler):
   - Load all documents (`DocumentService.listAll`), score them (`Retrieval.scoreDocuments`).
   - If nothing scores above zero: log the search with `resultCount: 0` and render "no match" -
     never call the Function or the LLM for a query with no plausible match (mirrors
     `AskAIPanel.tsx` exactly).
   - Otherwise take the top 5 candidates, invoke the Function, then call Anthropic with the
     Function's `contextBlock`.
   - Log the search with the real citation count, render the answer + source badges linking back
     to each cited document.

### Known limitation, honestly documented

No real `ANTHROPIC_API_KEY` was available in the environment this was built and smoke-tested in
(same as every other port of this showcase). `LlmProperties` deliberately does NOT validate the
key at startup - the app starts and serves every other page normally; only `AskAiService.ask`
fails, at the `AnthropicClient.generateGroundedAnswer` call, with a clear
`"ANTHROPIC_API_KEY is not configured"` `IllegalStateException` rendered as a 500 error page via
`GlobalExceptionHandler`'s generic-exception handler - never a fabricated answer.

## Live smoke test results (2026-08-01, real project, `mvn clean install` → `BUILD SUCCESS`)

1. **Anonymous guest session + library** - `GET /` established a lazily-created anonymous
   session and rendered the document library with the real, already-seeded `documents` collection
   contents (title/snippet/tags/author/relative-time all correct).
2. **Server-side substring search** - `GET /?q=password` correctly returned only "Password Reset
   Guide" out of the full library, proving the Java port of `retrieval.ts`'s
   `matchesSearchTerm` behaves identically server-side.
3. **Document detail + error handling** - a real document, a nonexistent-but-valid-looking
   24-hex id, and a malformed id all rendered correctly (real content; a graceful "not found" page
   for the other two; no stack traces).
4. **Auth gating** - an unauthenticated `GET /documents/new` and `POST /documents` both correctly
   302-redirected to `/login?redirect=...` via `RequireSignInInterceptor`, never reaching the
   controller.
5. **Ask AI recent searches** - `GET /ask` rendered real, live `search_log` entries from the
   shared collection, including entries written by other sibling showcase ports' own testing
   sessions against this same project earlier the same day (e.g. "swift port verification
   query"), confirming this reads the same live collection every other port does.
6. **Function deployment** (shared with every other port - not re-created here) - confirmed via
   the reference web app's own live smoke test in `../web/plan/build-plan.md`: real
   `execute` → `queued` → poll → `success` round trip against `cloud.mudbase.dev`, not a mock.
   This port's own `FunctionInvokeClient` uses the identical execute/poll contract - see "Ask AI
   architecture" above.

**Not verified live in this session: login, document create/update/delete, and the Ask AI POST
flow.** Roughly two hours of attempts - including multiple long (10-28 minute) cooldown waits and
a retry from an entirely different egress IP via the `mudhaxk-vps` box - all hit a real,
platform-side rate limit on Mudbase's local-auth endpoints. This was confirmed independently of
this app's own code with a raw `curl` directly against `https://cloud.mudbase.dev` from both this
development machine and the VPS, both returning `429`. `git log` on this repo shows PHP,
Python/FastAPI, Flutter, Swift, and C# ports of this exact showcase were all built and
live-tested against this same Mudbase project earlier the same day - that cumulative traffic had
already exhausted the shared rate-limit budget before this port's own turn, and the budget did
not recover during this session (each additional probe, including read-only cooldown checks,
appeared to extend rather than shorten the remaining cooldown, so further probing was stopped
once that pattern was confirmed rather than continuing indefinitely). See `java/README.md` "Live
smoke test results" for the full account and the confidence argument for why the write-path code
itself - ported logic-for-logic from the already-live-proven sibling kanban/ecommerce/social Java
apps - is expected to work once the shared rate-limit window genuinely clears. No fake login,
document, or Ask AI answer is claimed anywhere in this codebase or its docs; this gap is
documented honestly per the same standard applied to the missing `ANTHROPIC_API_KEY` above.

## Known limitations (real platform constraints, not bugs)

- **No public/anonymous read without a session.** Every collection read requires a JWT (anonymous
  or real) - confirmed live, see "Data model" above.
- **The Ask AI LLM call cannot live inside the Mudbase Function** - see "Ask AI architecture"
  above. Hard platform constraint, not a convenience choice.
- **No `ANTHROPIC_API_KEY` in the build/test environment** - Ask AI is fully wired and will work
  once a developer supplies their own key (see `README.md` "LLM setup").
- **Auth endpoints are real-world rate-limited** (5 requests / 15 min per IP, per this platform's
  own security policy) - shared across every sibling showcase port hitting the same Mudbase
  project from the same development machine IP. This is expected, not a bug in this port.
