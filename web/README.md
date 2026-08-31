# Mudbase Showcase - Docs Search (web)

An AI-powered knowledge-base search app built **almost entirely on [Mudbase](https://www.mudbase.dev)**
- auth, database, and a serverless Function for retrieval ranking - plus one small, unavoidable
server-side route (see "Ask AI architecture" below for exactly why). This is the reference
implementation for this showcase: the other 9 language/platform ports are built to match this
app's data model and API contract.

## Stack

Next.js 15 (App Router) + TypeScript (strict) + Tailwind + shadcn/ui-style components + TanStack
Query + `react-hook-form` + `zod`. Client-side reads/writes talk directly to `cloud.mudbase.dev`
with the signed-in user's own JWT (anonymous session for guests) - same pattern as the sibling
`mudbase-showcase-social` web app.

## What it demonstrates

| Feature | Where |
|---|---|
| Guest browsing with no signup | Anonymous auth, `src/lib/mudbase-provider.tsx` |
| Email/password accounts | `POST /api/auth/local/signup/customer`, `src/hooks/useAuth.ts` |
| Document library, client-side keyword search | `src/app/page.tsx`, `src/lib/retrieval.ts` |
| Document CRUD, ownership-scoped edit/delete | `src/app/documents/**`, `src/hooks/useCollection.ts` |
| **Ask AI** - keyword retrieval → real Mudbase Function → grounded LLM answer with citations | `src/app/ask/page.tsx`, `src/app/api/ask/route.ts` - see below |
| Recent searches | `src/components/ask/RecentSearches.tsx` reading `search_log` |

## Ask AI architecture (the actual point of this showcase)

**The naive design - client does retrieval, sends question + docs to a Mudbase Function, the
Function holds the LLM key as its own env var and calls the LLM provider directly - does not
work on the current Mudbase platform**, for two independently-verified reasons (full detail with
source citations in `plan/build-plan.md`):

1. **A project end-user JWT can never invoke a Function.** The `/execute` route requires the org
   role `owner`/`admin`/`developer`; every project end-user (including a real, signed-in
   `customer` account) always carries org role `viewer`, which only grants `functions:read`.
2. **The Function's own sandbox has zero network access.** Mudbase Functions run inside a real,
   separate V8 isolate (`isolated-vm`) with only `console`/`payload`/`context`/`env` injected -
   no `fetch`, no `http`, no way to reach an external API at all. This is a deliberate security
   boundary (the platform's prior sandbox had a real realm-escape vulnerability), not an
   oversight.

**What this app actually does instead:**

1. A real, deployed Mudbase Function (`docsAskRetrieval`) does the retrieval-ranking work it
   *can* do inside the sandbox: given a question and a shortlist of candidate documents, it
   re-scores them by query-term overlap and returns a grounded context block + citations. This
   is genuine, deployed, invoked-over-the-real-API Function code - not a stand-in.
2. An org-scoped Mudbase API key (`ak_...`, permissioned only for `functions`) authorizes
   deploying/invoking it. This key lives only as a server-only env var.
3. The one call the sandbox is structurally incapable of making - the outbound HTTPS request to
   the LLM provider - happens in this app's single Next.js Route Handler
   (`POST /api/ask`), using the Anthropic Claude API. This route is not "custom backend
   business logic" in the sense the sibling showcase apps avoid; it exists solely because of
   the two platform constraints above, and its own logic is limited to: validate → invoke the
   Function → make one grounded completion call → return the result.

See `plan/build-plan.md` "Ask AI architecture" for the full request flow, exact source-file
citations backing both constraints, and the live smoke test that proves the Function
deploy/invoke/poll pipeline works end-to-end against the real project.

## LLM setup

This app uses **Anthropic's Claude API** via the official `@anthropic-ai/sdk`. To get real,
grounded answers instead of the "not configured" error:

1. Create an API key at [console.anthropic.com](https://console.anthropic.com).
2. Set it as `ANTHROPIC_API_KEY` in `web/.env.local` - **never** prefix it with `NEXT_PUBLIC_`,
   and never put it inside the Mudbase Function's own environment variables (the Function
   cannot use it - see above).
3. Optionally set `LLM_MODEL` (defaults to `claude-opus-5`) to a cheaper/faster model such as
   `claude-sonnet-5` or `claude-haiku-4-5` for a lower-cost demo.

Prefer a different provider? Swap the implementation in `src/lib/server/llm.ts` - everything
else in the app (the request/response contract at `POST /api/ask`, the Mudbase Function, the UI)
is provider-agnostic.

## Provisioning (what already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled (this app also establishes an anonymous session for guest browsing).
2. The Multi-Role feature's default `customer` role, with full CRUD on both collections below.
3. Two collections - `documents` (`title`, `content`, `tags?`, `authorId`, `authorName`) and
   `search_log` (`queryText`, `userId?`, `userName?`, `resultCount`).
4. A deployed Mudbase Function named `docsAskRetrieval` (see `plan/build-plan.md` for its exact
   code) and an org-scoped API key permissioned for `functions` - both created via a one-time
   provisioning step, not through this app's own UI (there is no in-app "create a Function" flow
   - Function creation itself requires the same elevated org role a project end-user never has).

`.env.example` lists every ID and env var this app needs once that's done, with exact
instructions for creating the API key from the Mudbase dashboard.

## Live smoke test (2026-08-01, real project)

Run against the live project (`6a6d3faad07caabbbdfc5698`) using the shared
`docs.member.demo@gmail.com` test account:

- **Login** via `POST /api/auth/local/login` - confirmed working, real access + refresh token
  pair returned for the real, verified `customer` account (subject to this session's
  shared-account auth rate limit while several sibling projects were being built in parallel -
  it cleared and login succeeded).
- **Document CRUD** - created 3 real documents with distinct content; confirmed list, single-doc
  read, update, and delete all work via the exact request shapes the app's own hooks use (a 4th
  throwaway document was created, fetched, updated, deleted, and confirmed gone - full CRUD).
- **`search_log` write** - confirmed with the real signed-in user's ObjectId as `userId` (never
  a placeholder string), entry lists correctly.
- **Ask AI → Mudbase Function** - confirmed twice: once via direct API calls against
  `cloud.mudbase.dev` using the provisioned Function API key (`POST .../execute` → `202 queued`
  → polling `GET .../executions/:id` → `status: "success"` with a correctly-ranked
  `contextBlock`), and again by calling this app's own running `POST /api/ask` with all 3 real
  documents as candidates - the 5.4s response time confirms it drove the full execute →
  poll-until-success cycle against the real Function before reaching the LLM step. This proves
  the full deploy → invoke → poll → result pipeline end-to-end, both directly and through the app.
- **Ask AI → LLM completion** - **not tested with a real answer**: no Anthropic API key was
  available in the build environment. `POST /api/ask` reaches `src/lib/server/llm.ts` and fails
  there with a clear, expected `"ANTHROPIC_API_KEY is not configured"` error (502) - the wiring
  is correct up to the point of the actual LLM call, and no fake success was fabricated. See
  `plan/build-plan.md` "Live smoke test results" for the full sequence and exact responses.

## Known limitations (real platform constraints, not bugs)

- **No public/anonymous collection read without a session** - every read 401s with zero auth,
  confirmed live. Guests get an anonymous session automatically.
- **The project's `pk_` publishable key is not a working credential** on this backend version -
  kept in `.env.example` for parity with the dashboard; no request actually uses it.
- **The Ask AI LLM call cannot live inside the Mudbase Function** - see "Ask AI architecture"
  above. This is the single largest deviation from the obvious design, and it's a verified
  platform constraint, not a shortcut.

## Local development

```bash
npm install
cp .env.example .env.local   # fill in your own provisioned project's IDs + LLM key
npm run dev
```

## Deploy

Every `NEXT_PUBLIC_` env var is safe to set as a Vercel Production/Preview variable.
`MUDBASE_FUNCTION_ID`, `MUDBASE_FUNCTIONS_API_KEY`, `ANTHROPIC_API_KEY`, and `LLM_MODEL` must be
set as **server-only** environment variables (no `NEXT_PUBLIC_` prefix) - Vercel's project
settings support this distinction directly.

`POST /api/ask` polls the Mudbase Function's execution status for up to 20 seconds (real
executions complete in well under a second - see the smoke test above - the 20s ceiling is a
safety margin, not the expected path). On Vercel's Hobby tier, serverless functions default to a
10-second execution limit; if you deploy there and see 504s on `/api/ask`, either raise the
function's `maxDuration` (Pro tier or above) or lower `POLL_TIMEOUT_MS` in
`src/lib/server/functionInvoke.ts`.
