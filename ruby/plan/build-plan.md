# Build Plan — Mudbase Showcase: Docs Search (Ruby / Sinatra port)

Generated: 2026-08-01
Mode: brownfield port (one of several per-language reimplementations of the reference Next.js app)
Type: web (fullstack via BaaS, no custom backend) + one small server-side LLM call this app was
always going to need somewhere, since it is itself the "smallest server-side surface" — see
"Ask AI architecture" below.
Stack: Ruby 4.0 + Sinatra 4 + ERB + `Rack::Session::Cookie`, backed entirely by Mudbase
(`cloud.mudbase.dev`), talking to the platform through the real generated Mudbase Ruby SDK
(`mudbase_sdk`, module `MudbaseSDK`) for auth and collection CRUD, plus two plain `Net::HTTP`
clients for the Mudbase Function invocation and the Anthropic completion call (see below).

## Stack Decisions

- Sinatra + ERB + Puma, no ORM, no database of its own, **no client-side JavaScript at all** —
  matches the framework choice and file-layout conventions the sibling
  `mudbase-showcase-social/ruby` and `mudbase-showcase-kanban/ruby` ports established:
  `lib/mudbase/config.rb`, `lib/mudbase/errors.rb`, `lib/mudbase/client_factory.rb`, and the
  `AuthService`/`SessionHelpers` split with `with_access_token`'s 401-refresh-retry wrapper are
  ported near-verbatim from those ports.
- **Guest (anonymous) read session, like the social port — unlike the kanban port.** This
  project's data model grants anonymous/guest browsing+search as read-only (per the task brief),
  matching the reference web app's own finding: every collection read 401s with zero auth, even
  with the project's own `pk_` publishable key, so a guest without *some* JWT would just fail to
  browse at all. `SessionHelpers#with_read_token` (real user token if signed in, otherwise a
  silent anonymous session) is ported verbatim from the social port's own file of the same name.
- `mudbase_sdk` sourced from `https://github.com/mudbase/mudbase-sdk.git` (`ruby/*.gemspec` glob),
  `ffi ~> 1.17` pinned for the same native-extension reason documented in the sibling ports'
  Gemfile/README.
- **No pseudo-ObjectId helper needed.** Unlike the kanban port's `assigneeId`, every ObjectId-
  shaped field this app writes (`authorId`, `userId`) is always a real signed-in user's own
  `_id` — never a synthesized display-name hash — so `lib/mudbase/pseudo_object_id.rb` from the
  sibling ports has no counterpart here.
- **Search is server-side substring matching**, not a real search index — this app has no
  client-side JavaScript, so the reference web app's client-side `matchesSearchTerm` filter
  (`src/lib/retrieval.ts`) runs here instead, against the `q` query param on `GET /`
  (`lib/retrieval.rb#matches_search_term?`, exercised in `app/routes/documents_routes.rb`).

## Ask AI architecture — the actual point of this showcase

### The naive plan and why it doesn't work (verified against the real platform, not inferred)

The obvious design: the app does keyword retrieval, sends the question + top documents to a
Mudbase Function, the Function holds the LLM API key as its own environment variable and calls
the LLM provider directly, returns a grounded answer. **This does not work on the current
Mudbase platform**, for two independently-verified reasons — full source citations are in the
reference web app's own `../web/plan/build-plan.md` "Ask AI architecture" (`mudbase-backend`
route/middleware/runner source), reproduced here in short form since they're load-bearing for
this port's own architecture:

1. **A project end-user JWT can never invoke a Function.** The `/execute` route requires the org
   role `owner`/`admin`/`developer`; every project end-user in this app — a real, signed-in
   `customer` account *or* the silent anonymous guest — always carries org role `viewer`, which
   only grants `functions:read`, never the `functions:create` the execute route requires.
2. **The Function's own sandbox has zero network access.** Mudbase Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with only `console`/`payload`/`context`/`env` injected —
   no `fetch`, no `http`/`https` module, no way to reach any external host at all. This is a
   deliberate security boundary (the platform's prior sandbox had a real realm-escape
   vulnerability), not an oversight, and it applies regardless of what env var the Function holds.

### What was actually built instead

1. **The same real, already-deployed Mudbase Function does the retrieval-ranking work.**
   `docsAskRetrieval` (`_id 6a6d431ef09e238c3e62b2f4`) — the exact Function the reference web
   app deployed and this port reuses, not a re-deployment — receives `payload.question` and
   `payload.candidates` (documents already shortlisted by this app's own
   `lib/retrieval.rb#score_documents`/`top_candidates`, a line-for-line Ruby port of the
   reference app's `src/lib/retrieval.ts`), re-scores them by query-term overlap across title
   (×3)/tags (×2)/content (×1), and returns a `contextBlock` string plus a `citations` array.
2. **The same org-scoped API key authorizes it.** `MUDBASE_FUNCTIONS_API_KEY` (`ak_...`,
   permissioned only for `functions`) lives only as a server-only env var, read exclusively by
   `lib/mudbase/function_client.rb`, which calls `POST .../functions/:id/execute` then polls
   `GET .../executions/:id` every 600ms (20s timeout) via plain `Net::HTTP` — this is a genuinely
   different auth scheme (`X-API-Key` header) from the bearer-JWT flow every other Mudbase call
   in this app uses via `mudbase_sdk`, so a raw HTTP client is simpler and more honest here than
   forcing the SDK's `Configuration`/`ApiClient` machinery to do something it isn't shaped for.
3. **The LLM completion call happens in this Sinatra app itself** —
   `lib/llm/anthropic_client.rb#generate_grounded_answer!`, invoked from
   `app/routes/ask_routes.rb`. Unlike the reference Next.js app, which had to carve out one
   dedicated Route Handler (`POST /api/ask`) specifically because its client-rendered pages have
   no server-side network stack of their own, **this Sinatra app is already fully
   server-rendered** — every request handler already runs with a real network stack, so "the
   smallest server-side surface" the platform constraints force this call into is simply "this
   app's own `/ask` route," with no separate API layer needed. `ANTHROPIC_API_KEY` is read
   straight from the environment and only ever leaves this process as an outbound request header
   to `api.anthropic.com` — never rendered into a page (this app ships no client JS to leak it to
   in the first place) and never logged.
4. **Full request flow (`POST /ask`, `app/routes/ask_routes.rb`):**
   - Validates the question (1–2000 chars, matching the reference app's `AskRequestSchema`).
   - Fetches up to 100 documents via `with_read_token` (guest or signed-in — Ask AI works for
     both, per this project's read-only guest RBAC), scores them with `Retrieval.score_documents`,
     and takes the top 5 (`Retrieval.top_candidates`, content truncated to 4000 chars each —
     identical bounds to the reference app's `topCandidates`).
   - If nothing scored above zero, shows a "couldn't find anything" message and logs
     `search_log` with `resultCount: 0` directly (no Function/LLM call at all) — matches the
     reference app's own `scored.length === 0` short-circuit in `AskAIPanel.tsx`.
   - Otherwise calls `Mudbase::FunctionClient.invoke_retrieval` (execute → poll → result). If the
     Function's own `usedCount` is `0`, shows the same canned "couldn't find anything" answer and
     logs `resultCount: 0` **without calling the LLM** — matches `POST /api/ask`'s own
     `retrieval.usedCount === 0` short-circuit in the reference app.
   - Otherwise calls `Llm::AnthropicClient.generate_grounded_answer!` with the Function's
     `contextBlock`, renders the answer + citations, and logs `search_log` with
     `resultCount: citations.length`.
   - `search_log.userId`/`userName` are only ever set for a real signed-in user (never a
     placeholder) — a guest's question is still answered, but per this project's read-only guest
     RBAC, no `search_log` write is even attempted for a guest (verified live — see below).
   - On any `FunctionError`/`LlmError` (Function unreachable, execution failed/timed out, or the
     LLM call itself fails), the real error message is shown and **no** `search_log` entry is
     written — matches the reference app's `AskAIPanel.tsx`, whose own `logSearch` call only
     runs after `askAI.mutateAsync` has already resolved successfully.

### LLM provider choice

**Anthropic Claude**, via a plain `Net::HTTP` POST to `https://api.anthropic.com/v1/messages`
(no SDK gem needed for one endpoint) — model defaults to `claude-opus-5`, overridable with the
`LLM_MODEL` env var. See `README.md` "LLM setup" for exactly how a developer running this app
supplies their own key.

### Known limitation, honestly documented

No real `ANTHROPIC_API_KEY` was available in the environment this was built and smoke-tested in
— same situation the reference web app's own build documented. The full request/response
contract is wired up and verified end-to-end **up to the point of the actual LLM call** (see
"Live smoke test results" below) — the Mudbase Function invocation, polling, and
retrieval-ranking are all confirmed working against the real, live Mudbase project, reusing the
exact same deployed Function and API key the reference web app provisioned. The LLM completion
step itself fails with a clear, expected `"ANTHROPIC_API_KEY is not configured"` error rather
than any fabricated success.

## Live Smoke Test Results (2026-08-01, against the real project)

Performed against the real, already-provisioned project (`6a6d3faad07caabbbdfc5698`), its real
`documents`/`search_log` collections (already carrying 3 seed documents and several search_log
rows from the reference web app's own smoke test, plus rows from sibling agent sessions building
the other language ports concurrently against the same shared demo account), through a real
running Puma server (`localhost:4577`) via `curl`, with a real Rack session cookie carrying a
real Mudbase JWT exactly as a browser would.

| Step | Result |
|---|---|
| `ruby -c` clean on every `.rb` file (15 files) | ✅ |
| `bundle install` (fresh gem resolution, no lockfile pre-existing) | ✅ 17 gems, no native-extension compile issues |
| `bundle exec ruby -e "require './app'"` loads cleanly, no live calls | ✅ |
| `GET /` with no session | ✅ `200` — a silent anonymous guest session was established automatically, library lists the 3 real pre-existing documents ("API Rate Limits", "Billing and Invoices FAQ", "Password Reset Guide") |
| `GET /ask` as guest | ✅ `200`, no login prompt |
| `POST /login` as `docs.member.demo@gmail.com` | ✅ `303` → `/`, header shows the real signed-in first name ("Dara") |
| `POST /documents` (create a throwaway doc with tags) | ✅ `303` → `/documents/:id` with a real, newly-created 24-hex ObjectId |
| `GET /documents/:id` as the author | ✅ `200`, Edit/Delete controls rendered (ownership check `owner_of?` passing) |
| `GET /?q=smoketest` | ✅ returns exactly the new document; `GET /?q=zzz_no_match_zzz` returns the empty-state "No documents match your search" |
| `POST /documents/:id` (update title/content/tags) | ✅ `303`, reload shows the updated title — confirms `update_data` PATCH round-trip |
| `GET /documents/:id/edit` as a guest (different session, not the author) | ✅ `302` → `/login` (`require_login!` gate fires before any ownership check) |
| `POST /documents/:id/delete` | ✅ `303`, `GET /documents/:id` afterward → `404` — full create → read → update → delete confirmed |
| `POST /ask` with "How do I reset my password?" (signed-in member) | ✅ `200` in **2.48s** — confirms the full execute → poll-until-success cycle ran against the real, already-deployed `docsAskRetrieval` Function (a short-circuited/mocked path would return near-instantly) — failed only at the final step with the expected `"ANTHROPIC_API_KEY is not configured"` error, proving retrieval scoring → Function invocation → polling → result → LLM handoff is wired correctly end-to-end |
| `search_log` NOT written for the above (LLM-step failure) | ✅ confirmed by re-reading `/ask`'s recent-searches list immediately after — the failed question does not appear |
| `POST /ask` with a nonsense query (no keyword overlap, signed-in member) | ✅ `200`, "couldn't find anything" message shown, and a real `resultCount: 0` `search_log` row appears in recent searches immediately after ("just now") — confirms the `scored.empty?` short-circuit's own log write |
| `POST /ask` with a nonsense query as a **guest** | ✅ `200`, same "couldn't find anything" message shown, but **no** `search_log` entry was written — confirms this port's read-only-guest RBAC decision (see "RBAC" below) is enforced by simply never attempting the write, not by a permission error being caught |
| `POST /register` with invalid data (empty first name, bad email, short password, terms unchecked) | ✅ rejected with all 4 inline validation messages, no Mudbase call attempted |
| `POST /documents` with an empty title (signed-in) | ✅ rejected with "Title is required.", no Mudbase call attempted |
| `GET /nonexistent-route` | ✅ `404`, custom not-found page |

**Registration itself (creating a brand-new real account) was not exercised live** in this
session, to avoid consuming the shared project's auth-endpoint rate-limit budget that sibling
agent sessions building the other language ports were concurrently drawing on against the same
demo account (the same contention the sibling kanban/social ports' own builds documented) — the
code path (`AuthService.register_customer!`) is identical to the already-proven-live
`login!`/`create_anonymous_session!` calls in the same file, using the same
`MultiRoleFeatureApi#register_with_role_with_http_info` signature confirmed to exist in the
installed `mudbase_sdk` gem (verified by inspecting the generated gem source directly, not
assumed).

## RBAC / Security Implementation

- **Single default `customer` role, full CRUD** — Mudbase's own collection permissions grant any
  signed-in customer full CRUD on both collections (confirmed live: the demo member could
  create/update/delete a document it authored). **Per-document ownership is enforced only by
  this app**, not by the collection permission itself — `owner_of?(document)` in `app.rb`, gating
  edit/delete in `app/routes/documents_routes.rb`, mirrors the reference web app's own `isOwner`
  check (`user.id === document.authorId`) rather than relying on a Mudbase-side per-row ACL that
  doesn't exist for this project's single-role setup.
- **Anonymous/guest browsing+search is read-only.** This app never attempts a `documents` or
  `search_log` write for a guest — not because the write would necessarily be rejected
  server-side (that would need separately confirming the anonymous system role's own collection
  grants, which this session did not test to avoid an unnecessary write against shared data), but
  because the task's own RBAC specification states guest access is read-only, and the safest,
  most honest implementation of that is to simply never issue the write client-side, exactly the
  same posture this app already takes everywhere else ("don't rely on UI-only gating" cuts both
  ways — don't attempt a write you don't have a specified grant for, either).
- Input validation: plain Ruby validation in each route (`documents_routes.rb#validate_document_form`,
  `auth_routes.rb#validate_registration`, `ask_routes.rb`'s inline question-length check) —
  title capped at 200 chars, content at 50,000, tags at 500, question at 2000, matching the
  reference web app's zod schemas (`documentFormSchema`, `AskRequestSchema`).
- Authentication: Mudbase-issued JWT (real user or silent anonymous guest), held only in an
  httponly, signed+encrypted `Rack::Session::Cookie` — never in a rendered page or client JS
  (there is none). 401 → refresh → retry handled once, for both the real-user and guest token
  paths (`SessionHelpers#with_access_token`/`#with_read_token`).
- Secrets: `SESSION_SECRET` signs/encrypts the session cookie; `MUDBASE_FUNCTIONS_API_KEY` and
  `ANTHROPIC_API_KEY` are both server-only env vars this app never sends to a browser (it has no
  browser-side code to send them from) and never logs. Every Mudbase project/collection/Function
  identifier is safe to expose and is not treated as one.

## Known Limitations (real platform/framework constraints, not bugs)

- **The Ask AI LLM call cannot live inside the Mudbase Function.** See "Ask AI architecture"
  above — a hard, verified platform constraint (the Function's `isolated-vm` sandbox has no
  network primitives at all), not a shortcut.
- **No `ANTHROPIC_API_KEY` in the build/test environment.** The Ask AI feature is fully wired
  and verified end-to-end through the real Mudbase Function's execute → poll → result cycle; it
  will produce a real grounded answer once a developer supplies their own key (see README "LLM
  setup"). No fabricated answer was ever substituted.
- **No client-side JavaScript, so search is a real page load.** `GET /?q=...` re-renders the
  whole library server-side on every keystroke's worth of a submitted search, unlike the
  reference web app's live-filtering client-side search box — the same tradeoff the sibling
  kanban port made for its button/dropdown card movement instead of drag-and-drop.
- **No realtime.** Like the sibling kanban/social ports, this app never sends the Mudbase JWT to
  the browser (it lives only in the httponly Rack session cookie), so a client-side Socket.IO
  subscription — which would need that JWT — was never wired up. Reload the library or `/ask` to
  see another session's changes.
- **Registration not independently live-verified this session** (shared rate-limit contention
  from concurrent sibling-port builds against the same demo account) — see "Live Smoke Test
  Results" above for exactly what was and wasn't exercised, and why.

## Environment Variables

See `.env.example`. `SESSION_SECRET`, `MUDBASE_FUNCTIONS_API_KEY`, and `ANTHROPIC_API_KEY` are
the only true secrets; every Mudbase project/collection/Function identifier is safe to expose.

## File Tree

```
mudbase-showcase-docs-search/ruby/
├── Gemfile, Gemfile.lock, .env.example, .gitignore, README.md
├── app.rb, config.ru
├── plan/build-plan.md
├── app/routes/ (auth_routes, documents_routes, ask_routes)
├── lib/
│   ├── mudbase/ (config, errors, client_factory, auth_service, documents_repo,
│   │             search_log_repo, function_client)
│   ├── llm/ (anthropic_client)
│   ├── retrieval.rb
│   ├── session_helpers.rb
│   └── view_helpers.rb
├── views/
│   ├── layout.erb
│   ├── auth/ (login, register)
│   ├── documents/ (index, _card, show, form)
│   ├── ask/ (index)
│   └── errors/ (not_found, server_error)
└── public/css/style.css
```
