# Mudbase Showcase — Docs Search (Python) — Build Plan

Server-rendered FastAPI + Jinja2 port of the reference Next.js app at `../web/`. Same Mudbase
project, same two collections, same Ask AI architecture and the same two platform constraints
that shape it — see `../web/plan/build-plan.md` "Ask AI architecture" for the full source-cited
explanation of why the LLM completion call cannot live inside the Mudbase Function. This document
covers only what's specific to the Python port: architecture mirroring `mudbase-showcase-kanban/python`
and `mudbase-showcase-social/python`, the FastAPI-specific implementation of the Ask AI flow, and
this port's own live smoke test.

## Stack

FastAPI + Jinja2 + Starlette `SessionMiddleware` + the real Mudbase Python SDK
(`mudbase-sdk`, installed from `github.com/mudbase/mudbase-sdk#subdirectory=python`) +
`pydantic-settings` + the official `anthropic` Python SDK. `mypy --strict` clean.

## Architecture (mirrors mudbase-showcase-social/python)

```
app/
├── config.py            Settings (pydantic-settings), fail-fast on required IDs
├── mudbase_client.py     Thin sync wrapper over mudbase_sdk + asyncio.to_thread adapters
├── session.py            Server-side session (Starlette cookie), refresh-on-demand, anon bootstrap
├── context.py             Per-request base template context (current_user, flash)
├── templates_env.py       Shared Jinja2Templates + filters (date, relative_time, tags, snippet)
├── utils.py                Formatting helpers + field_errors (ValidationError -> dict)
├── main.py                  FastAPI app factory
├── routers/
│   ├── auth.py             login/register/logout/verify-email
│   ├── library.py           GET / — search + document grid
│   ├── documents.py         detail/new/edit/delete
│   └── ask.py                GET/POST /ask — the Ask AI flow (see below)
├── schemas/
│   ├── auth.py, document.py, search_log.py, ask.py
├── services/
│   ├── auth_service.py, documents.py, search_log.py
│   ├── retrieval.py          keyword scoring, ported from web/src/lib/retrieval.ts
│   ├── function_invoke.py    Mudbase Function execute/poll (see below)
│   └── llm.py                Anthropic completion call (see below)
├── static/css/styles.css
└── templates/                base, library, document_detail, document_new, document_edit,
                               login, register, verify_email, ask, partials/*
```

Session/auth/collection plumbing (`config.py`, `mudbase_client.py`'s auth+collection helpers,
`session.py`, `context.py`, `templates_env.py`) is ported near-verbatim from
`mudbase-showcase-social/python`, which already proved this exact pattern against the same
Mudbase backend version. `schemas/document.py`, `services/documents.py`,
`services/search_log.py`, and `services/retrieval.py` are new to this port, translating
`web/src/types/document.ts` / `web/src/lib/retrieval.ts` field-for-field.

## Data model (already provisioned — do not recreate)

Same as `../web/plan/build-plan.md` "Data model": project `6a6d3faad07caabbbdfc5698`,
`documents` (`6a6d3fcdd07caabbbdfc5842`), `search_log` (`6a6d3fcdd07caabbbdfc5857`), single
`customer` role with full CRUD on both.

## Page map

| Route | Auth | Purpose |
|---|---|---|
| `GET /` | public (anonymous session) | Document library: server-side substring search (`?q=`), document grid |
| `GET /documents/{id}` | public read; edit/delete gated to `user.id == document.author_id` | Full content, author, tags |
| `GET`/`POST /documents/new`, `POST /documents` | signed-in (`customer`) | Create document |
| `GET`/`POST /documents/{id}/edit` | signed-in author only (re-checked server-side on every request) | Edit document |
| `POST /documents/{id}/delete` | signed-in author only | Delete document |
| `GET`/`POST /ask` | public (Ask AI works for guests too; `search_log.user_id` only set for a real signed-in user) | Ask AI panel + recent searches |
| `GET`/`POST /login`, `/register`, `GET /verify-email` | public | Auth forms. This project requires email verification (verified live — registration returns 201 with no token; login 403s `EMAIL_VERIFICATION_REQUIRED` until the emailed link is followed). The shared demo account is already verified. |

## Auth flow

Mirrors `mudbase-showcase-social/python`: the Mudbase JWT (access + refresh) lives only in the
signed, httpOnly Starlette session cookie — never sent to any template or client JS. This is a
deliberate, better-suited difference from the reference SPA (which necessarily holds its token in
`localStorage` for direct browser-to-Mudbase calls); a server-rendered app has no such
requirement. `ensure_anonymous_session` establishes a guest session on first page load exactly
like the reference app's `POST /api/auth/anonymous` bootstrap — verified live: every collection
read 401s with zero auth, even with the project's own `pk_` key.

## Ask AI architecture

Same two verified platform constraints as the reference web app (full detail with source
citations in `../web/plan/build-plan.md`):

1. A project end-user JWT can never invoke a Function — `/execute` requires org role
   `owner`/`admin`/`developer`; every project end-user (including a real signed-in `customer`)
   always carries org role `viewer`, which only grants `functions:read`.
2. The Function's own sandbox (`isolated-vm`) has zero network access — no `fetch`, no `http`,
   no way to reach an LLM provider at all, by design (a deliberate security boundary after the
   prior sandbox's real realm-escape vulnerability).

**Since this Python app is itself a server process** (unlike the reference Next.js app, which
needed a dedicated Route Handler purely to get *any* real network stack involved), there is no
equivalent internal "route handler boundary" here — `app/routers/ask.py` calls
`app/services/function_invoke.py` (retrieval ranking, via the real deployed Function) and then
`app/services/llm.py` (the grounded completion call) directly, in the same request handler. The
architectural constraint that forces the LLM call out of the Function is identical; the
Python port just doesn't need a second network boundary to satisfy it, because the whole app
already has one.

### What's used

1. **The real, deployed Mudbase Function `docsAskRetrieval`** (`_id 6a6d431ef09e238c3e62b2f4`),
   invoked via the SDK's fully-typed `FunctionsApi.execute_function` /
   `FunctionsApi.get_function_execution` methods (`app/mudbase_client.py`), authenticated with a
   separate `ApiClient` configured with `configuration.api_key["ApiKeyAuth"] = <ak_ key>` (header
   `X-API-Key`) — never the signed-in user's own JWT. Unlike the auth helpers in this same file
   (which need a raw-JSON workaround for `login_sync`, see that function's docstring), no
   workaround was needed for the Function calls: `FunctionExecutionResponse.data.result` /
   `FunctionExecutionStatusResponse.data.result` are both typed as a plain `dict[str, Any]`, so
   the Function's untyped `{contextBlock, citations, usedCount}` return shape round-trips
   through the typed SDK method with no field loss.
2. **The org-scoped `ak_` API key** lives only in `MUDBASE_FUNCTIONS_API_KEY` (server-only env
   var, never rendered into any template).
3. **The LLM completion call** (`app/services/llm.py`) uses the official `anthropic` Python SDK,
   `ANTHROPIC_API_KEY` (server-only, optional at startup — see that module's docstring for why),
   default model `claude-opus-5`, overridable via `LLM_MODEL`.
4. **Full request flow** (`app/routers/ask.py`):
   - Fetch the document library (`app/services/documents.py`, same read the library page uses).
   - Score every document by keyword overlap (`app/services/retrieval.py`); if nothing scores
     above zero, show "no match" and log a zero-result search — skip the Function/LLM entirely.
   - Otherwise take the top 5 candidates (content truncated to 4000 chars) and invoke the
     Function (`app/services/function_invoke.py`): POST `.../execute` → `202 {executionId,
     status: "queued"}`, then poll `.../executions/{id}` every 600ms (20s timeout) until
     `status` leaves `queued`/`running`.
   - If the Function itself finds nothing worth citing (`usedCount == 0`), short-circuit with
     the same "couldn't find anything closely related" message the reference app returns.
   - Otherwise call `generate_grounded_answer()` (the LLM step) with the Function's context
     block, and render citations linking back to `/documents/{id}`.
   - Log the search (`app/services/search_log.py`) regardless of outcome — best-effort; a
     failed write never blocks the answer already rendered (see "Live smoke test" below for a
     real, live example of this: anonymous guests can read+ask, but cannot write to
     `search_log` — the write fails with "Insufficient permissions" and is silently absorbed).

### Discovered platform bug, worked around client-side (not by redeploying the Function)

Live-tested during this port's build, independently of the reference web app's own testing: the
deployed `docsAskRetrieval` Function's code builds each citation as
`citations.push({ documentId: doc._id, title: doc.title, score: ... })` — reading `doc._id` — but
the documented payload contract (used by both the reference web app and this port) sends each
candidate's ID under the key `documentId`, never `_id`. Sent exactly as specified, every citation
came back with `documentId: undefined` (confirmed via a direct `execute_function` /
`get_function_execution` round trip against the real Function, using the real `ak_` key, before
this was noticed — see the raw Function source, fetched live via a direct GET against
`/api/functions/projects/{projectId}/functions/{functionId}`).

Since the Function is shared, already-provisioned infrastructure this port doesn't own or
redeploy, the fix lives entirely in `app/services/function_invoke.py`: every candidate sent in
the payload includes its document ID under **both** `documentId` and `_id`, so the Function's own
field lookup succeeds too. Re-verified live after the fix — citations now come back with a real,
matching `documentId` that correctly links to `/documents/{id}`. This is an honest, documented
workaround (see that module's docstring), not a silent patch, and it does not require or assume
any change to the deployed Function.

## Known platform facts applied

- **`*Id`-suffixed filter fields must be a real 24-char hex ObjectId** — enforced in
  `app/schemas/ask.py`'s `AskCandidate.document_id` validator.
- **The Python SDK's `DataApi.list_data` caps `limit` at 100 client-side**
  (`Field(le=100, strict=True)`, verified by reading the generated SDK source) — every list read
  in this app (`_LIBRARY_LIMIT`, `_RECENT_SEARCHES_LIMIT`) stays at or under 100, unlike the
  reference web app's direct-fetch client (which uses `limit=200` for the Ask AI candidate pool
  and isn't bound by this SDK-side constraint).
- **Jinja `loop` scoping**: none of this port's templates need `loop.first`/`loop.last` across an
  `{% include %}` boundary (unlike the sibling Kanban port, which does for its column
  first/last-position buttons) — `document_card.html` and `document_form_fields.html` only ever
  need ordinary named context variables (`document`, `values`), which cross `{% include %}`
  boundaries normally. No `{% set %}`-before-`{% include %}` workaround was needed here, but the
  same pattern would apply if a future template needed it.

## Live smoke test results (2026-08-01, real project, this Python port)

All of the following were run against the live project
(`6a6d3faad07caabbbdfc5698`) — either via a direct Mudbase Python SDK script (for the Function
and initial CRUD proof) or via `curl` against this app's own running `uvicorn` process (for the
HTTP-level app behavior):

1. **Mudbase Function deploy → invoke → poll → result, direct SDK** — confirmed via
   `FunctionsApi.execute_function` + `FunctionsApi.get_function_execution` against the real
   Function using the real `ak_` key: `execute_function` → `202 {executionId, status:
   "queued"}`; polling → `status: "success"`, `durationMs: 43`, `result.contextBlock` containing
   exactly the "Password Reset Guide" candidate's content, `result.citations` correctly scored
   (12) once the `documentId`/`_id` workaround above was applied. This is the same round trip the
   reference web app proved for its own stack, run again independently for this port.
2. **Document CRUD, direct SDK, real signed-in account** — `docs.member.demo@gmail.com` login →
   real access/refresh pair for the real, `emailVerified: true`, `customRole: "customer"` user
   (`_id 6a6d409a51703cd1071b46fe`). Created a document, fetched it, listed the collection
   (`pagination.total` correct), updated it, deleted it, and confirmed a subsequent `GET` 404s.
   `search_log` write with the real user's own ObjectId as `userId` succeeded.
3. **Anonymous session + collection read, direct SDK** — confirmed a bare request with zero auth
   401s even with the project's `pk_` key; `POST /api/auth/anonymous` grants a token
   (`isAnonymous: true`, `role: "viewer"`, no `customRole`) that successfully reads `documents`.
4. **Guest library browsing + search, HTTP-level against this app** — `GET /` establishes an
   anonymous session and renders the real document grid (4 real documents, titles confirmed);
   `GET /?q=password` correctly filters to the 2 matching documents; `GET /?q=<nonsense>` shows
   the "no documents match" empty state.
5. **Ask AI, full pipeline, HTTP-level against this app, as a guest** — `POST /ask` with "How do
   I reset my password?" returned `200 OK` with the expected, honest
   `"ANTHROPIC_API_KEY is not configured..."` error message rendered in the page — proving the
   entire pipeline (keyword scoring → real Function invoke → poll-until-success → citation
   mapping → handoff to the LLM step) ran correctly end-to-end, with only the intentionally-unset
   LLM key stopping the final completion call. The same request's `search_log` write failed
   server-side with `"Insufficient permissions"` (logged as a non-fatal warning, per
   `app/services/search_log.py`'s best-effort design) — **a genuine, newly-observed platform
   detail**: an anonymous guest's session (`role: "viewer"`, no `customRole`) can read `documents`
   and `search_log`, and can successfully invoke the Ask AI pipeline, but cannot write a
   `search_log` entry — only a real `customer`-role account can. This did not block the guest's
   answer; it only means a guest's questions don't appear in "Recent searches" server-side.
6. **Route-level permission gating, HTTP-level against this app** — unauthenticated
   `GET /documents/new`, `GET /documents/{id}/edit`, and `POST /documents/{id}/delete` all
   `303`-redirect to `/login?next=...`; `GET /documents/{bogus-24-char-hex-id}` 404s; a guest
   viewing a real document's detail page sees no Edit/Delete actions (`is_owner` correctly false).
7. **Form validation, HTTP-level against this app, no backend call needed** — `POST /register`
   with the terms checkbox unchecked, `POST /login` with a malformed email, and `POST /ask` with
   an empty question all return `422` with the exact field-level error message from the
   corresponding Pydantic validator, confirmed rendered in the page.

### Known limitation, honestly documented

**The interactive HTTP-level login round trip (session cookie → authenticated document
create/edit/delete through this app's own web forms) could not be verified live in this
session.** The shared demo account/IP's auth rate limiter (`"Too many requests from this IP,
please try again later"`) was already active before this port's own testing began — visible
within the first few requests — and remained active through more than 70 minutes of bounded,
spaced-out retries (a single isolated `/login` attempt roughly every 15–20 minutes, with no other
auth-endpoint traffic in between), consistent with this being a cross-project, shared-IP
constraint on this build day rather than anything specific to this port (this exact backend and
account are shared across all ~10 sibling language ports of this showcase being built in
parallel — see `../web/README.md`'s own note that the account's rate limit "cleared" only after a
wait during that build too).

This is a genuine external constraint, documented honestly rather than worked around by
fabricating a session — no code in this app bypasses real Mudbase authentication. What **is**
proven, directly and live, in its place:

- The exact `login_sync` / `register_with_role_sync` / collection CRUD code this app's
  `auth_service.py` and `services/documents.py` call was independently, successfully exercised
  against this same account and project via a direct SDK script earlier in this same session
  (item 2 above) — the service layer the routers depend on is proven correct against the real
  backend.
- Every route-level permission check that does *not* require completing a fresh login (redirect-
  to-login gating, 404s, ownership-hiding of Edit/Delete on a real document, and all form
  validation) was verified live against this app's own running process (items 6–7 above).
- The router code for `/login`, `/register`, `/documents/new`, `/documents/{id}/edit`, and
  `/documents/{id}/delete` is a close structural port of `mudbase-showcase-social/python`'s own
  `auth.py`, which passed the equivalent live login → authenticated-mutation test during that
  port's own build.

Anyone re-running this app once the shared rate limit has cleared can confirm the remaining path
(`POST /login` → `POST /documents` → `POST /documents/{id}/edit` → `POST /documents/{id}/delete`)
directly — nothing about that path was skipped for architectural reasons, only because the
account was locked out for the duration of this build session.
