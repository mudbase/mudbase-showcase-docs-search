# Mudbase Showcase — Docs Search (Python)

Server-rendered FastAPI + Jinja2 port of the reference Next.js app at `../web/`. Same Mudbase
project, same data model, same Ask AI architecture — see `plan/build-plan.md` for the full
implementation detail and this port's own live smoke test.

## Stack

FastAPI + Jinja2 + Starlette `SessionMiddleware` + the real Mudbase Python SDK
(`mudbase-sdk`, git-installed from `github.com/mudbase/mudbase-sdk#subdirectory=python`) +
`pydantic`/`pydantic-settings` + the official `anthropic` SDK. `mypy --strict` clean. Architecture
mirrors the sibling `mudbase-showcase-kanban/python` and `mudbase-showcase-social/python` ports:
`app/config.py`, `app/mudbase_client.py`, `app/session.py`, `app/routers/*`, `app/services/*`,
`app/schemas/*`.

## What it demonstrates

| Feature | Where |
|---|---|
| Guest browsing with no signup | Anonymous auth bootstrap, `app/session.py::ensure_anonymous_session` |
| Email/password accounts (email verification required) | `app/routers/auth.py`, `app/services/auth_service.py` |
| Document library, server-side keyword search | `app/routers/library.py`, `app/services/retrieval.py` |
| Document CRUD, ownership-scoped edit/delete | `app/routers/documents.py`, `app/services/documents.py` |
| **Ask AI** — keyword retrieval → real Mudbase Function → grounded LLM answer with citations | `app/routers/ask.py`, `app/services/function_invoke.py`, `app/services/llm.py` |
| Recent searches | `app/services/search_log.py`, rendered on `/ask` |

## Ask AI architecture (the actual point of this showcase)

Same two verified platform constraints as the reference web app — a project end-user JWT can
never invoke a Mudbase Function, and the Function's own `isolated-vm` sandbox has zero network
access, so the LLM completion call cannot happen inside it no matter what env var it holds. This
app's `POST /ask` handler: fetches the document library, scores it by keyword overlap, invokes
the real deployed Function `docsAskRetrieval` (an org-scoped `ak_` API key, never the signed-in
user's own JWT) for retrieval ranking, then makes the one Anthropic Claude completion call this
process's own service layer is capable of. See `plan/build-plan.md` "Ask AI architecture" for the
full request flow, the exact source citations behind both constraints, and a discovered
citation-field bug in the deployed Function that this app works around client-side (documented,
not silently patched).

## LLM setup

1. Create an API key at [console.anthropic.com](https://console.anthropic.com).
2. Set it as `ANTHROPIC_API_KEY` in `.env` — **never** prefix it, and never put it inside the
   Mudbase Function's own environment variables (the Function's sandbox has no network access,
   so a key placed there would be unusable — see `plan/build-plan.md`).
3. Optionally set `LLM_MODEL` (defaults to `claude-opus-5`) to a cheaper/faster model such as
   `claude-sonnet-5` or `claude-haiku-4-5`.

Prefer a different provider? Swap the implementation in `app/services/llm.py` — everything else
(the retrieval Function, the request/response shapes, the templates) is provider-agnostic.

## Local development

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in your own provisioned project's IDs + LLM key
uvicorn app.main:app --reload
```

Then open `http://127.0.0.1:8000`.

## Type checking

```bash
source .venv/bin/activate
python -m mypy app --config-file mypy.ini
```

`mypy --strict` clean as of this build.

## Live smoke test (2026-08-01, real project)

Run against the live project (`6a6d3faad07caabbbdfc5698`):

- **Mudbase Function** — confirmed via a direct SDK execute → poll → result round trip against
  the real, deployed `docsAskRetrieval` Function, and again through this app's own running
  `POST /ask` as a guest.
- **Document CRUD** — full create → read → list → update → delete → confirm-404 verified via the
  Mudbase Python SDK against the real signed-in demo account.
- **Guest browsing, search, and the full Ask AI pipeline** — verified live, end-to-end, through
  this app's own HTTP endpoints. `POST /ask` correctly ran the entire pipeline (keyword scoring →
  real Function invoke → poll-until-success → citation mapping) and failed only at the final LLM
  call with the expected `"ANTHROPIC_API_KEY is not configured"` error — no fabricated answer.
- **Route permission gating and form validation** — verified live: unauthenticated access to
  protected routes redirects to `/login`; a non-owner sees no Edit/Delete actions; a bogus
  document ID 404s; every form's Pydantic validation renders the correct field-level error.
- **Login-gated document CRUD through this app's own web forms** — **not verified in this
  session**: the shared demo account/IP's own Mudbase auth rate limiter remained active through
  more than 70 minutes of bounded, spaced-out retries. See `plan/build-plan.md` "Known
  limitation, honestly documented" for exactly what this means and what's proven in its place
  (the identical underlying SDK calls this app's service layer uses were independently verified
  live, directly, against the same account, earlier in this same session).

## Known limitations (real platform constraints, not bugs)

- **No public/anonymous collection read without a session** — every read requires a JWT
  (anonymous or real); this app establishes an anonymous session automatically for guests.
- **The project's `pk_` publishable key is not a working credential** on this backend version —
  kept in `.env.example` for parity with the dashboard, unused by any request.
- **The Ask AI LLM call cannot live inside the Mudbase Function** — see "Ask AI architecture"
  above; a hard platform constraint, not a convenience choice.
- **No `ANTHROPIC_API_KEY` in the build/test environment** — the Ask AI feature is fully wired
  and verified end-to-end up to the LLM call; it will produce real answers once a developer
  supplies their own key.
- **An anonymous guest session cannot write to `search_log`** — newly observed during this
  port's own live testing (see `plan/build-plan.md` item 5): guests can read, search, and use
  Ask AI, but only a real `customer`-role account's search gets recorded in "Recent searches".
  This fails silently (logged, non-fatal) and never blocks the guest's answer.
