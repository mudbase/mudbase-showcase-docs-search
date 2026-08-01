# Mudbase Showcase — Docs Search (C# / ASP.NET Core)

An AI-powered knowledge-base search app, server-rendered with **ASP.NET Core 10 Razor Pages**,
built **almost entirely on [Mudbase](https://www.mudbase.dev)** — auth, database, and a serverless
Function for retrieval ranking — plus one small, unavoidable server-side call (see "Ask AI
architecture" below for exactly why). This is the C# port of the reference implementation in
`../web/` (Next.js): same data model, same API contract, same Ask AI pipeline, against the same
live project.

## Stack

ASP.NET Core 10, Razor Pages, the real [Mudbase C# SDK](https://github.com/mudbase/mudbase-sdk)
(generated client, `mudbase-sdk/csharp`), talking directly to `cloud.mudbase.dev`, plus a direct
HTTP call to Anthropic's Messages API for the one LLM completion this app makes. There is no
database, no ORM, and no custom API of any kind beyond that one call — every document/search-log
read or write goes straight to Mudbase's REST API through the generated SDK, authenticated with the
current visitor's own JWT (anonymous guest or a real signed-in "customer", held server-side in
ASP.NET Core session state, never exposed to client JS).

No client-side JS framework: the library's search box is a plain GET form (server-side substring
match across title/content/tags, no XHR), and the Ask AI question form posts directly to its own
Razor Page handler — this app has no separate API route the way the Next.js reference needed one
(see below).

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Guest browsing/search with no signup | Anonymous session bootstrap, `POST /api/auth/anonymous` | `Services/MudbaseAuthService.cs`, `Infrastructure/EnsureMudbaseSessionMiddleware.cs` |
| Email/password accounts, email verification | `POST /api/auth/local/signup/customer`, `POST /api/users/verify-email` | `Pages/Register.cshtml(.cs)`, `Pages/VerifyEmail.cshtml(.cs)` |
| Document library, server-side keyword search | Collection read + a GET-bound search form | `Pages/Index.cshtml(.cs)`, `Services/RetrievalHelpers.cs` |
| Document CRUD, ownership-scoped edit/delete | Collection CRUD, `documents` | `Pages/Documents/*`, `Services/DocumentsService.cs` |
| **Ask AI** — keyword retrieval → real Mudbase Function → grounded LLM answer with citations | Function execute/poll + a direct Anthropic API call | `Pages/Ask.cshtml(.cs)`, `Services/FunctionInvocationService.cs`, `Services/LlmService.cs` — see below |
| Recent searches | Collection read, `search_log`, `sort: "-createdAt"` | `Services/SearchLogService.cs`, `Pages/Ask.cshtml` |
| Automatic token refresh | `POST /api/auth/refresh`, single-use rotating refresh tokens | `Services/TokenRefreshHandler.cs` |

## Ask AI architecture (the actual point of this showcase)

**The naive design — client does retrieval, sends the question + documents to a Mudbase Function,
the Function holds the LLM key as its own env var and calls the LLM provider directly — does not
work on the current Mudbase platform**, for two independently-verified reasons (full detail with
source citations in `../web/plan/build-plan.md`):

1. **A project end-user JWT can never invoke a Function.** The `/execute` route requires the org
   role `owner`/`admin`/`developer`; every project end-user (including a real, signed-in
   "customer" account) always carries org role `viewer`, which only grants `functions:read`.
2. **The Function's own sandbox has zero network access.** Mudbase Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with only `console`/`payload`/`context`/`env` injected — no
   `fetch`, no outbound HTTP of any kind. This is a deliberate security boundary, not an oversight.

**What this app actually does instead:**

1. A real, deployed Mudbase Function (`docsAskRetrieval`) does the retrieval-ranking work it *can*
   do inside the sandbox: given a question and a shortlist of candidate documents, it re-scores
   them by query-term overlap and returns a grounded context block + citations.
2. An org-scoped Mudbase API key (`ak_...`, permissioned only for `functions`) authorizes invoking
   it. This key lives only as a server-only config value (`Mudbase:FunctionsApiKey`), supplied via
   the `Mudbase__FunctionsApiKey` environment variable — never committed, never rendered to a page.
3. The one call the sandbox is structurally incapable of making — the outbound HTTPS request to
   Anthropic's Messages API — happens in `Services/LlmService.cs`, called directly from
   `Pages/Ask.cshtml.cs`'s `OnPostAskAsync` handler. **Unlike the Next.js reference, this app needs
   no separate API route for this** — every Razor Page handler already runs server-side, so this
   call is already made from the smallest possible server-side surface, by construction.

See `plan/build-plan.md` "Ask AI architecture" for the full request flow, exact source-file
citations backing both constraints, and the live smoke test that proves the Function
deploy/invoke/poll pipeline works end-to-end against the real project.

## LLM setup

This app calls **Anthropic's Claude Messages API** directly over HTTP (no unofficial third-party
NuGet package — Anthropic does not publish an official C# SDK). To get real, grounded answers
instead of the "not configured" error:

1. Create an API key at [console.anthropic.com](https://console.anthropic.com).
2. Set it as the `Mudbase__AnthropicApiKey` environment variable (or
   `Mudbase:AnthropicApiKey` in a local, **gitignored** config file you don't commit) — **never**
   commit a real value in `appsettings.json`/`appsettings.Development.json`, and never put it inside
   the Mudbase Function's own environment variables (the Function cannot use it — see above).
3. Optionally set `Mudbase__LlmModel` (defaults to `claude-opus-5`) to a cheaper/faster model such
   as `claude-sonnet-5` or `claude-haiku-4-5` for a lower-cost demo.

Prefer a different provider? Swap the implementation in `Services/LlmService.cs` — everything else
in the app (the Ask AI page, the Mudbase Function, the request/response shapes) is provider-agnostic.

## Getting started

This repo assumes a sibling clone of the Mudbase C# SDK (not published on NuGet):

```bash
cd ..                                             # parent directory of this repo
git clone https://github.com/mudbase/mudbase-sdk.git
cd mudbase-showcase-docs-search/csharp/MudbaseShowcase.DocsSearch
Mudbase__FunctionsApiKey=your_ak_key Mudbase__AnthropicApiKey=your_anthropic_key dotnet run
```

Then open `http://localhost:5000` (or whatever port `dotnet run` reports). Browse the library and
Ask AI as a guest, or sign in with the demo account via `/Login`'s "Sign in as demo member" button
(or register your own — see `plan/build-plan.md` for account details).

> **.NET version note**: this project targets `net10.0`. If your machine only has an older SDK
> installed, either install the .NET 10 SDK or see `MudbaseShowcase.DocsSearch.csproj`'s comment for
> why an older `TargetFramework` builds but will not run without a matching runtime installed.

## Configuration

No `.env` files — configuration lives in `MudbaseShowcase.DocsSearch/appsettings.json` (already
pointed at the shared demo project — none of those values are secrets, see `plan/build-plan.md`
"Security Implementation") plus two **secrets** that must never be committed:
`Mudbase:FunctionsApiKey` and `Mudbase:AnthropicApiKey`. Supply both via the
`Mudbase__FunctionsApiKey` / `Mudbase__AnthropicApiKey` environment variables (or `dotnet
user-secrets`) — see `appsettings.Example.json` at the repo root for the full key list with
descriptions.

## Provisioning (what already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled, plus anonymous sessions for guest browsing, and the Multi-Role feature's
   default `customer` role with full CRUD on both collections below.
2. Two collections — `documents` (`title`, `content`, `tags?`, `authorId`, `authorName`) and
   `search_log` (`queryText`, `userId?`, `userName?`, `resultCount`).
3. A deployed Mudbase Function named `docsAskRetrieval` (see `plan/build-plan.md` for its exact
   contract) and an org-scoped API key permissioned for `functions` — both created via a one-time
   provisioning step, not through this app's own UI (there is no in-app "create a Function" flow —
   Function creation itself requires the same elevated org role a project end-user never has).

## Live smoke test

See `plan/build-plan.md` → "Live smoke test results" for the full account, including: a clean
`dotnet build -warnaserror`; static assets, guest access, and graceful error handling all verified
live; the full request pipeline (routing, antiforgery, session, DI, the real SDK call) verified
live through a real login attempt; and the Mudbase Function's deploy → invoke → poll → result
pipeline verified live and independently via a direct `curl` against `cloud.mudbase.dev`, correctly
ranking a relevant test document over an unrelated one. This build's own session hit the shared
demo project's login/anonymous-session rate limit (confirmed independently of this app with a raw
`curl`, `retryAfter: 900`) before a full logged-in document-CRUD and Ask-AI-through-the-app pass
could complete — see the build plan for exactly what is carried forward from the reference `../web/`
app's identical, already-completed live verification as a result, and why the Function-half of the
pipeline is still fully, freshly proven regardless.

## Known limitations (real platform constraints, not bugs)

See `plan/build-plan.md` → "Known Limitations" — no public/anonymous collection read without a
session (guests get one bootstrapped automatically), the project's `pk_` publishable key isn't a
working credential on this backend version, the Ask AI LLM call cannot live inside the Mudbase
Function (the reason `Services/LlmService.cs` exists at all), and no `ANTHROPIC_API_KEY` was
available in this build/test environment.

## Relationship to the other ports

This is one of several per-language/platform reimplementations of the same reference Docs Search
app (see the repo root `README.md`). All ports share the same live Mudbase project, the same
`docsAskRetrieval` Function, and the same data model — this port in particular mirrors
`mudbase-showcase-social/csharp`'s anonymous-session-bootstrap and email-verification-required
registration conventions (rather than `mudbase-showcase-kanban/csharp`'s no-anonymous-session
model, which doesn't fit this app's guest-browsing requirement), while introducing
`Services/FunctionInvocationService.cs` and `Services/LlmService.cs` as the two pieces every other
C# port before it didn't need.
