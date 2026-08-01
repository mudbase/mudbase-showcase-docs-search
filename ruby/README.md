# Mudbase Showcase — Docs Search (Ruby / Sinatra)

An AI-powered knowledge-base search app built **almost entirely on [Mudbase](https://www.mudbase.dev)**
— auth, database, and a serverless Function for retrieval ranking — implemented in
**Sinatra + ERB**, talking to `cloud.mudbase.dev` through the real generated **Mudbase Ruby SDK**
(`mudbase_sdk`, module `MudbaseSDK`). This is the Ruby reimplementation of the reference Next.js
app (see `../web`): same Mudbase project, same two collections (`documents`/`search_log`), same
single default `customer` role, same Ask AI architecture — different stack, following the
Sinatra structure the sibling `mudbase-showcase-social`/`mudbase-showcase-kanban` ports
established.

## Stack

Sinatra 4 + ERB + `Rack::Session::Cookie`, `mudbase_sdk` (git-sourced), Puma. No ORM, no database
of its own, no client-side JavaScript — every collection read/write goes to Mudbase's Collections
REST API, every interaction is a plain HTML form (or link) navigation, and the Mudbase Function
invocation + the Anthropic LLM call are plain `Net::HTTP` requests (see "Ask AI architecture"
below for why those two don't go through the SDK).

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Guest browsing + search, no signup | Anonymous session, read-only per this project's RBAC | `lib/session_helpers.rb#with_read_token`, `app/routes/documents_routes.rb` |
| Email/password accounts | `POST /api/auth/local/signup/customer` via `MultiRoleFeatureApi` | `lib/mudbase/auth_service.rb`, `app/routes/auth_routes.rb` |
| Document library, server-side keyword search | Collections list + server-side substring filter (`?q=`) | `app/routes/documents_routes.rb`, `lib/retrieval.rb` |
| Document CRUD, ownership-scoped edit/delete | Full CRUD granted to any signed-in customer; this app's own `owner_of?` gate | `app/routes/documents_routes.rb` |
| **Ask AI** — keyword retrieval → real Mudbase Function → grounded LLM answer with citations | Deployed Function (`docsAskRetrieval`) + org-scoped API key + Anthropic Claude | `app/routes/ask_routes.rb`, `lib/mudbase/function_client.rb`, `lib/llm/anthropic_client.rb` — see below |
| Recent searches | Append-only `search_log` collection, read by all, written only for signed-in users | `lib/mudbase/search_log_repo.rb`, `app/routes/ask_routes.rb` |

## Ask AI architecture (the actual point of this showcase)

**The naive design — the app does retrieval, sends the question + documents to a Mudbase
Function, the Function holds the LLM key as its own env var and calls the LLM provider directly
— does not work on the current Mudbase platform**, for two independently-verified reasons (full
detail with source citations in `../web/plan/build-plan.md`, reproduced in short form in this
port's own `plan/build-plan.md`):

1. **A project end-user JWT can never invoke a Function.** The `/execute` route requires the org
   role `owner`/`admin`/`developer`; every project end-user here (signed-in customer or
   anonymous guest) always carries org role `viewer`, which only grants `functions:read`.
2. **The Function's own sandbox has zero network access.** Mudbase Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with no `fetch`, no `http`/`https` module — no way to
   reach any external API at all. A deliberate security boundary, not an oversight.

**What this app actually does instead:**

1. The same real, already-deployed Mudbase Function (`docsAskRetrieval`, `_id
   6a6d431ef09e238c3e62b2f4`) the reference web app provisioned does the retrieval-ranking work
   it *can* do inside the sandbox — this port reuses it rather than deploying a second copy.
2. The same org-scoped Mudbase API key (`ak_...`, permissioned only for `functions`) authorizes
   invoking it. This key lives only as the server-only `MUDBASE_FUNCTIONS_API_KEY` env var, used
   exclusively by `lib/mudbase/function_client.rb`.
3. The outbound HTTPS call to the LLM provider — the one thing the sandbox is structurally
   incapable of doing — happens in **this app's own `/ask` route**
   (`lib/llm/anthropic_client.rb`). Unlike the reference Next.js app, which had to carve out one
   dedicated Route Handler specifically because its pages have no server-side network stack of
   their own, this Sinatra app is already fully server-rendered, so there's no separate "server
   surface" to build — the smallest one available is simply this app itself.

See `plan/build-plan.md` "Ask AI architecture" for the full request flow and the live smoke test
that proves the Function execute → poll → result pipeline works end-to-end against the real
project, reusing the exact Function and API key the reference web app deployed.

## LLM setup

This app calls **Anthropic's Claude API** directly via `Net::HTTP` (no SDK gem needed for one
endpoint — see `lib/llm/anthropic_client.rb`). To get real, grounded answers instead of the
"not configured" error:

1. Create an API key at [console.anthropic.com](https://console.anthropic.com).
2. Set it as `ANTHROPIC_API_KEY` in `.env` — never commit it, never log it.
3. Optionally set `LLM_MODEL` (defaults to `claude-opus-5`) to a cheaper/faster model such as
   `claude-sonnet-5` or `claude-haiku-4-5` for a lower-cost demo.

Prefer a different provider? Swap the implementation in `lib/llm/anthropic_client.rb` —
everything else in the app (the Function, the `/ask` route's flow, the views) is
provider-agnostic.

## Provisioning (what already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled, with the Multi-Role feature's default `customer` role granted full CRUD
   on both collections below, and anonymous sessions enabled for guest browsing+search
   (read-only).
2. Two collections — `documents` (`title`, `content`, `tags?`, `authorId`, `authorName`) and
   `search_log` (`queryText`, `userId?`, `userName?`, `resultCount`).
3. A deployed Mudbase Function named `docsAskRetrieval` (see `plan/build-plan.md` for what it
   does) and an org-scoped API key permissioned for `functions` — both created via a one-time
   provisioning step, not through this app's own UI.

`.env.example` lists every ID and env var this app needs once that's done.

## Setup

```bash
bundle install
cp .env.example .env   # fill in your own provisioned project's IDs, Function ID/key, LLM key, and a session secret
bundle exec puma -p 4567 config.ru
# or: bundle exec rackup config.ru
```

Open `http://localhost:4567`. Browse and search the library as a guest, or sign in to publish
documents:

| Role | Email | Password |
|---|---|---|
| Demo member | `docs.member.demo@gmail.com` | `DemoTest123!` |

Or use the "Sign in as demo member" quick-fill button on `/login`, or `/register` a new account
(single default `customer` role, no role picker).

### Native-extension (ffi) caveat

`mudbase_sdk` depends on `typhoeus` → `ethon` → `ffi` for its HTTP transport. `ffi`'s native
extension is loosely pinned by the SDK's own gemspec and can fail to compile against a newer
Xcode/Clang toolchain than the gem release expects. This Gemfile pins `ffi ~> 1.17` explicitly (a
version with prebuilt `arm64-darwin`/`x86_64-darwin`/Linux bottles, so `bundle install` typically
doesn't need to compile anything). If you still hit a build failure, run
`gem install ffi -v '~> 1.17'` on its own first to confirm a prebuilt binary is available for your
platform before touching the vendored SDK gemspec.

### Verifying the app

```bash
find . -name "*.rb" -not -path "./vendor/*" -exec ruby -c {} \;   # every file: Syntax OK
bundle exec ruby -e "require './app'"                             # loads cleanly, no live calls
```

## Live smoke test (2026-08-01, real project, real account)

See `plan/build-plan.md` → "Live Smoke Test Results" for the full step-by-step table: guest
browsing establishing a silent anonymous session, full document CRUD (create → read → update →
delete, ownership-gated edit/delete confirmed rejected for a non-author session), server-side
search matching and non-matching queries, form validation rejecting bad input before any Mudbase
call, and the full **Ask AI pipeline** exercised twice — once with a real keyword match (2.48s
response time confirming the real execute → poll-until-success cycle against the deployed
`docsAskRetrieval` Function, failing only at the final `"ANTHROPIC_API_KEY is not configured"`
step) and once with a nonsense query that correctly short-circuits before ever calling the
Function, logging a real `resultCount: 0` `search_log` row.

**Registration was not independently exercised live** in this session, to avoid drawing further
on the shared demo account's auth-endpoint rate limit while several sibling agent sessions were
concurrently building this showcase's other language ports against the same account — see
`plan/build-plan.md` "Live Smoke Test Results" for exactly what was and wasn't tested and why.
`login!`/`create_anonymous_session!` (the same file, same call pattern) were both confirmed live.

## Known limitations (real platform/framework constraints, not bugs)

- **The Ask AI LLM call cannot live inside the Mudbase Function.** See "Ask AI architecture"
  above — a hard, verified platform constraint (the Function's `isolated-vm` sandbox has no
  network access at all), not a shortcut.
- **No `ANTHROPIC_API_KEY` in the build/test environment.** The Ask AI feature is fully wired
  and verified end-to-end through the real Mudbase Function's execute → poll → result cycle; it
  was not possible to test a real generated answer in this environment. No fabricated answer was
  ever substituted — see `plan/build-plan.md` for the exact error returned.
- **No client-side JavaScript, so search is a real page load** (`GET /?q=...`), not a live
  client-side filter — the only interaction model available with zero shipped JS.
- **No realtime.** Like the sibling kanban/social ports, this app never sends the Mudbase JWT to
  the browser (it lives only in the httponly Rack session cookie), so there is no client-side
  Socket.IO subscription. Reload the page to see another session's changes.
- **Registration not independently live-verified this session** (shared rate-limit contention
  from concurrent sibling-port builds) — see `plan/build-plan.md` for detail.

## Local development

```bash
bundle install
cp .env.example .env
bundle exec puma -p 4567 config.ru
```

## Deploy

Any Ruby host that runs Puma behind `config.ru` (Fly.io, Render, a bare VPS with systemd) works
unmodified. Set every variable in `.env.example` as a real environment variable —
`SESSION_SECRET` must be a long random value distinct from any other app's secret, and
`RACK_ENV=production` turns on the `secure` cookie flag (HTTPS-only session cookie).
