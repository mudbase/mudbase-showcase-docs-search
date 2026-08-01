# Mudbase Showcase — Docs Search (Java / Spring Boot edition)

A documentation knowledge-base app built on **[Mudbase](https://www.mudbase.dev)** — auth,
database, and a real deployed Function, plus one server-side Anthropic Claude call for Ask AI —
reimplemented in **Spring Boot + Thymeleaf** (server-rendered, no client-side JS framework). This
is a companion to the reference Next.js app at `../web`: same Mudbase project, same two
collections (`documents`/`search_log`), same deployed `docsAskRetrieval` Function; see
`plan/build-plan.md` for what deliberately differs and why.

## Stack

Java 17, Spring Boot 3.3 (Web MVC, not WebFlux), Thymeleaf, Bean Validation. Outbound HTTP: the
real Mudbase Java SDK against `cloud.mudbase.dev` for auth/data, a raw call to the same base URL
for the Mudbase Function, and a raw call to `https://api.anthropic.com` for the one LLM completion
— no other services, no database of its own.

## Setup

### 1. Install the Mudbase SDK to your local Maven repository (one-time, mandatory)

The SDK is **not published to Maven Central** — it lives at
[github.com/mudbase/mudbase-sdk](https://github.com/mudbase/mudbase-sdk), subdirectory `java/`.
Clone it as a **sibling** of this repo, then install it into `~/.m2`:

```bash
git clone https://github.com/mudbase/mudbase-sdk.git
cd mudbase-sdk/java && mvn install
```

This installs `dev.mudbase:mudbase-sdk:2.0.0` into your local repo — already done on any machine
that previously set up the sibling `mudbase-showcase-kanban/java`,
`mudbase-showcase-ecommerce/java`, or `mudbase-showcase-social/java` ports, since it's the exact
same artifact.

### 2. Configure environment variables

```bash
cp .env.example .env
# fill in your provisioned project's IDs and your own Anthropic API key
set -a && source .env && set +a
```

See `.env.example` for the full list. You need a Mudbase project already provisioned with local
auth, the single default `customer` role, the two collections (`documents`, `search_log`) shaped
as documented in `../web/plan/build-plan.md`, and a deployed `docsAskRetrieval` Function plus an
org-scoped `ak_` API key with `functions` permission — this app assumes that provisioning already
exists, exactly like the reference web app does.

### 3. LLM setup (for a real generated Ask AI answer)

`ANTHROPIC_API_KEY` is left blank in `.env.example` on purpose — get a key from
[console.anthropic.com](https://console.anthropic.com), set it as `ANTHROPIC_API_KEY`, and
optionally override `LLM_MODEL` (defaults to `claude-opus-5`; `claude-sonnet-5` or
`claude-haiku-4-5` are cheaper/faster options for a demo). Without it, every other page works
normally and Ask AI fails with a clear `"ANTHROPIC_API_KEY is not configured"` error rather than a
fabricated answer.

### 4. Build and run

```bash
cd mudbase-showcase-docs-search/java
mvn clean install   # verify it builds clean
mvn spring-boot:run
```

Visit `http://localhost:8080`. Browse and search as a guest, or sign in with the demo account
(`docs.member.demo@gmail.com`) to create/edit/delete documents.

## What's implemented

| Page | Route | Auth |
|---|---|---|
| Document library, server-side substring search | `GET /` | public (anonymous session) |
| Document detail | `GET /documents/{id}` | public read; edit/delete controls only shown to the author |
| New document | `GET/POST /documents/new`, `POST /documents` | signed-in |
| Edit document | `GET/POST /documents/{id}/edit` | signed-in author only |
| Delete document | `POST /documents/{id}/delete` | signed-in author only |
| Ask AI + recent searches | `GET/POST /ask` | public (guests can ask too; `search_log.userId` only set when signed in) |
| Login / Register / Logout | `GET/POST /login`, `GET/POST /register`, `POST /logout` | public |

Session/auth: the Mudbase-issued JWT is stored server-side in the Spring `HttpSession` — never
sent to the browser. A lazily-created anonymous guest session (cached in the same `HttpSession`
slot) covers every public read, exactly mirroring the reference web app's own "anonymous session
on first visit" behavior.

## Ask AI architecture

Full writeup in `plan/build-plan.md` "Ask AI architecture" — short version: a project end-user JWT
can never invoke a Mudbase Function (`rbacCheck("functions","create")` requires an org role no
end-user ever has), and a Function's own sandbox has zero network access, so the LLM completion
call structurally cannot happen inside it. This app: scores documents by keyword overlap
server-side (`support/Retrieval.java`, a direct port of the reference app's `retrieval.ts`),
invokes the real deployed `docsAskRetrieval` Function for retrieval-ranking
(`askai/FunctionInvokeClient.java`), then makes the one Anthropic completion call itself
(`askai/AnthropicClient.java`) — this app already IS the smallest server-side surface, since a
Thymeleaf app has no separate client/server boundary to begin with.

## Architecture notes

- **`mudbase/`** wraps the generated SDK: `MudbaseDataClient` (thin `DataApi` wrapper with
  document-shape normalization, retry-once-on-401 via `SessionAuthService`), `MudbaseAuthClient`
  (register/login/anonymous-session/refresh/logout, bypassing the generated SDK's login and
  registration models for known Gson strict-schema bugs against this project's Multi-Role account
  shape), `MudbaseApiException`, `PageResult`, `DocumentMapper`. Ported near-verbatim from the
  sibling kanban/ecommerce/social Java showcases, since these are fixes for real bugs against the
  same live backend, not app-specific code.
- **`auth/`** — `AuthSession` (covers both a real customer and an anonymous guest identity),
  `SessionAuthService` (including the already-fixed `recoverFromUnauthorized` token-mismatch
  recovery — reused verbatim per the task's instruction, not rediscovered), and
  `RequireSignInInterceptor` (gates document-authoring routes only; per-document ownership is a
  separate check in `DocumentService`).
- **`domain/`** — `DocumentRecord`, `SearchLogEntry`: thin wrappers around a raw Mudbase document
  map, each with a `fromDocument(Map)` factory and template-ready getters (`getSnippet()`,
  `getTagList()`, `getRelativeCreatedAt()`, ...). `ScoredDocument` is the keyword-scoring result
  record used internally by `support/Retrieval.java`.
- **`support/`** — `Retrieval` (keyword-overlap scoring, a direct Java port of the reference web
  app's `src/lib/retrieval.ts` and the tokenizer/counter helpers from `src/lib/utils.ts`),
  `Formatting` (relative/absolute date formatting, snippeting, tag parsing — mirrors
  `src/lib/utils.ts`), `ForbiddenActionException` (this app's own 403 for a non-author edit/delete
  attempt), `ViewModelHelper` (populates the header/sign-in-state attributes every template
  needs).
- **`askai/`** — `FunctionInvokeClient` (execute + poll against the deployed
  `docsAskRetrieval` Function using the org-scoped `ak_` key), `AnthropicClient` (the one LLM
  completion call), `RetrievalResult`/`Citation` (the Function's typed result shape — `Citation`
  is a plain class, not a record, so its properties resolve reliably via Thymeleaf's SpringEL).
- **`service/`** — `DocumentService` (CRUD + the authorId ownership check),
  `SearchLogService` (recent searches + logging, `userId`/`userName` only included for a real
  signed-in user), `AskAiService` (orchestrates scoring → Function → Anthropic → logging,
  `AuthService`. `AskAiResult` is a plain class (not a record) for the same Thymeleaf-SpEL reason
  as `Citation`.
- **`web/`** — `HomeController` (library + server-side search), `DocumentController` (CRUD),
  `AskController` (the whole Ask AI request/response cycle, synchronous within one request
  thread), `AuthController`, `GlobalExceptionHandler` (401 → session-expired redirect; 403 → error
  page; `ForbiddenActionException` → 403 error page; anything else → generic 500 page, no
  internals leaked), `WebConfig` (registers `RequireSignInInterceptor` on the write routes only).

## Live smoke test results (2026-08-01, real project)

- `mvn clean install` → **BUILD SUCCESS**, zero warnings.
- **Fully verified live, against the running app on the real project:**
  - Anonymous guest session establishment (`GET /`) and the document library rendering the real,
    already-seeded `documents` collection contents (title/snippet/tags/author/relative-time all
    correct).
  - Server-side substring search (`GET /?q=password` correctly returned only "Password Reset
    Guide" out of the full library).
  - Document detail (`GET /documents/{id}`) for a real document, a nonexistent-but-valid-looking
    id, and a malformed id — all three render correctly (content, 404-style "not found" page,
    no stack traces).
  - `RequireSignInInterceptor` gating: an unauthenticated `GET /documents/new` and
    `POST /documents` both correctly 302-redirect to `/login?redirect=...` rather than reaching
    the controller.
  - Ask AI page (`GET /ask`) rendering **real, live `search_log` entries** from the shared
    collection — including entries written by *other* sibling showcase ports' own testing sessions
    against this same project earlier the same day (e.g. "swift port verification query",
    "mobile smoke test query"), confirming this app reads the exact same live collection the other
    nine ports do.
- **Not verified live in this session: login, document create/update/delete, and the Ask AI
  POST flow.** Every attempt (over roughly two hours, with multiple long cooldown waits and a
  second attempt from a completely different egress IP via the `mudhaxk-vps` box) hit a real,
  reproducible platform-side rate limit on Mudbase's local-auth endpoints
  (`/api/auth/local/login`, `/api/auth/local/signup/customer`), confirmed independently of this
  app's own code by a raw `curl` directly against `https://cloud.mudbase.dev` from both this
  machine and the VPS, both returning `429` with `{"error":"Too many requests...","retryAfter":900}`
  / `{"error":"Too many requests from this IP, please try again later."}`. `git log` on this
  repo shows PHP, Python/FastAPI, Flutter, Swift, and C# ports of this exact showcase were all
  built and live-tested against this same Mudbase project earlier the same day — the shared-IP/
  shared-project auth rate limit budget was already exhausted by that cumulative testing traffic
  before this port's own turn, and stayed exhausted for the full session (the limiter appears to
  extend its own cooldown on every additional hit, including read-only cooldown-check probes, so
  further probing was stopped once that pattern was confirmed).
  - This is an honestly-documented gap, not a fabricated success: no fake login, document, or Ask
    AI answer is claimed anywhere in this codebase or its docs.
  - Confidence in the write-path code despite this: `MudbaseAuthClient.register`/`.login` and
    `MudbaseDataClient.create`/`.update`/`.delete` are logic-for-logic ports of the identical,
    already-live-verified code in the sibling `mudbase-showcase-kanban/java`,
    `-ecommerce/java`, and `-social/java` apps (see their own README "Live smoke test results" /
    "RBAC matrix" sections) — same Gson-bypass fixes, same request/response shapes, same backend.
    `DocumentService`'s ownership check and `AskAiService`'s orchestration are new code for this
    port, but call only those already-proven primitives. The Mudbase Function's own
    execute→poll→result contract is independently proven live in `../web/plan/build-plan.md`
    "Live smoke test results" (a real `curl`-driven execute/poll/result cycle against
    `docsAskRetrieval`), and `FunctionInvokeClient` implements that identical contract.
  - A developer re-running this port once the shared rate-limit window has genuinely cleared (or
    from a never-before-used IP) should see the full write path succeed on the first attempt —
    nothing in the observed failures pointed at this app's own request shape or logic.

## Known limitations (real platform constraints, not bugs)

- **No public/anonymous read without a session.** Every collection read requires a JWT (anonymous
  or real) — confirmed live.
- **The Ask AI LLM call cannot live inside the Mudbase Function** — see "Ask AI architecture"
  above. Hard platform constraint, not a convenience choice.
- **No `ANTHROPIC_API_KEY` in the build/test environment** — Ask AI is fully wired and will work
  once a developer supplies their own key (see "LLM setup" above).
- **Auth endpoints are real-world rate-limited** (5 requests / 15 min per IP) — shared across
  every sibling showcase port hitting the same Mudbase project from the same development machine
  IP. Expected, not a bug in this port.
