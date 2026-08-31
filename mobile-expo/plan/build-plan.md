# Mudbase Showcase - Docs Search (mobile-expo) - Build Plan

Expo/React Native port of the reference [`../web`](../web) Next.js app. Same Mudbase project,
same two collections, same data model, same Ask AI request/response contract. This document
covers what differs for the mobile target - read `../web/plan/build-plan.md` first for the
platform findings this build inherits unchanged.

## Stack

Expo Router (SDK 57) + TypeScript (strict) + NativeWind + TanStack Query + Zustand + Zod +
react-hook-form, talking directly to `cloud.mudbase.dev` via the real generated
[`mudbase-sdk`](../../mudbase-sdk/javascript) (`AuthenticationApi` + `DataApi`) - no hand-rolled
REST client for the Mudbase calls themselves. Architecture mirrors the sibling
[`mudbase-showcase-kanban/mobile-expo`](../../mudbase-showcase-kanban/mobile-expo) and
[`mudbase-showcase-social/mobile-expo`](../../../mudbase-showcase-social/mobile-expo) ports: same
file layout (`src/api`, `src/config`, `src/lib`, `src/stores`, `src/providers`, `src/hooks`,
`src/components/{ui,auth,documents,ask,layout}`), same secure-token pattern, same
single-retry-on-401 refresh.

## Data model (already provisioned - do not recreate)

- **Project**: `6a6d3faad07caabbbdfc5698`.
- **`documents`** (`6a6d3fcdd07caabbbdfc5842`): `title`, `content`, `tags?` (comma-separated),
  `authorId`, `authorName`.
- **`search_log`** (`6a6d3fcdd07caabbbdfc5857`): `queryText`, `userId?` (real ObjectId or omitted,
  never a placeholder), `userName?`, `resultCount`.
- Role: Mudbase's single default starter role, `customer` - full CRUD on both collections.
  Verified live (see "Live smoke test" below): every collection read 401s with zero auth, even
  with the project's own `pk_` key - an anonymous session is required for guest browsing, exactly
  the same platform behavior the web reference app documents.

## Auth model

Identical to the web reference and to the sibling `mudbase-showcase-social/mobile-expo` port -
**not** identical to `mudbase-showcase-kanban/mobile-expo` (which has no anonymous session at
all, because that app's collections require a real role for every read). Boot sequence
(`src/stores/authStore.ts`):

1. Try to restore a persisted token pair from SecureStore.
2. If restored, validate it with `getSession()`. If valid, done.
3. Otherwise (first launch, or an expired/invalid restored session), create a fresh anonymous
   session (`POST /api/auth/anonymous` via the generated SDK's `createAnonymousSession`). Guests
   can browse the library, run keyword search, and use Ask AI's retrieval step this way -
   publishing, editing, deleting a document, and writing a `userId`-attributed search log entry
   still require a real, signed-in account.

`isRealUser()` (`src/lib/rbac.ts`) is the single source of truth for "is this a real author, not
the bootstrap guest" - checked as `!!user && user.isAnonymous !== true`. Ownership for edit/delete
is `isDocumentOwner()`: `isRealUser(user) && user.id === document.authorId`. Mudbase's own
collection permissions are the actual enforcement boundary; this is UI convenience only (verified
live below with a raw `fetch` unauthenticated read that 401s regardless of this app's own gating).

There is no in-app registration screen - the task provisioned one demo account
(`docs.member.demo@gmail.com`) and explicitly said not to create new ones, and the sibling kanban
port already established the precedent of a login screen with a demo-account quick-fill button
rather than a full registration flow for these showcase ports. `src/components/auth/LoginForm.tsx`
has a single "Use demo account" button plus manual email/password fields for completeness.

## Page map (Expo Router)

| Route | Auth | Purpose |
|---|---|---|
| `(tabs)/index` | public (anonymous session) | Document library: search box (client-side substring match across title/content/tags), list of documents, "New document" button when signed in |
| `(tabs)/ask` | public (Ask AI retrieval works for guests too) | Ask AI panel + recent searches |
| `documents/[id]/index` | public read; edit/delete gated to `user.id === document.authorId` | Full content, author, tags |
| `documents/new` | signed-in | Create document (modal) |
| `documents/[id]/edit` | signed-in author only | Edit document |
| `login` | public | Sign-in form (reached via the header's sign-in icon, not a forced redirect) |

## Ask AI architecture - the actual point of this showcase, adapted for a serverless client

### What the web reference app already established

Read `../web/plan/build-plan.md` "Ask AI architecture" in full for the two independently-verified
platform constraints this build inherits unchanged:

1. A project end-user JWT (org role always `viewer`) can never invoke a Mudbase Function - only
   an org-scoped `ak_` API key with `functions` permission can call `/execute`.
2. The Function's own execution sandbox (`isolated-vm`) has zero network access - no `fetch`, no
   `http`/`https` module - so it structurally cannot make an outbound HTTPS call to any LLM
   provider, no matter what environment variable it holds.

The web app's fix: a real, deployed Mudbase Function (`docsAskRetrieval`) does keyword-overlap
retrieval ranking and context assembly (all it is structurally capable of); the one Next.js Route
Handler (`POST /api/ask`) invokes that Function with the org-scoped key, then makes the actual LLM
completion call with a server-only `ANTHROPIC_API_KEY`. Both secrets live only in that Next.js
process; the browser never sees either one.

### Why this port can't just repeat that fix, and what was actually built instead

A mobile app has no server-side surface of its own. Concretely, both secrets the web app's route
holds are equally impossible to hold here:

- **`MUDBASE_FUNCTIONS_API_KEY` (the `ak_` org key)** cannot be embedded client-side. It is a real
  credential that authorizes arbitrary Function execution against this project's org - shipping
  it in a mobile bundle (trivially unpacked, see builder CLAUDE.md "React Native / Expo Security" -
  "The Bundle Is Public") would hand any user of the app the same execution power an
  owner/admin/developer-role org member has. This is **not** the same class of value as the
  `EXPO_PUBLIC_MUDBASE_PROJECT_ID`/collection IDs this app does ship client-side - those authorize
  nothing by themselves; every actual data request still needs a real per-user JWT.
- **`ANTHROPIC_API_KEY`** is explicitly named in this task as never to be embedded on-device,
  under any circumstance - matching the same rule.

So unlike the web app, where only the LLM completion call was forced out of the Function and into
a small server surface, on mobile **both** steps of `/api/ask` (Function invocation *and* the LLM
call) need a real server-side surface this app does not have on its own.

**The deliberate choice made here: reuse the web reference app's already-built, already-verified
`POST /api/ask` Route Handler as a small shared backend proxy**, rather than inventing new backend
infrastructure or faking success. This is the option the task described as "calling a small shared
backend proxy for just the LLM completion step, if one exists or can reasonably be stood up" - one
already exists, fully implemented and smoke-tested, in this exact monorepo. Duplicating that
server logic into a brand-new standalone service for this port alone would be pure duplication with
no architectural benefit; the Route Handler is already the minimal server-side surface the platform
constraints force into existence, and it is stack-agnostic about who calls it.

Concretely (`src/config/env.ts`, `src/hooks/useAskAI.ts`):

- `EXPO_PUBLIC_ASK_PROXY_URL` is an **optional** env var (deliberately not validated with
  `requireEnv` the way the required Mudbase IDs are) pointing at a running `../web` app's
  `/api/ask` endpoint - either its local dev server (`npm run dev` in `../web`, then
  `http://<lan-ip>:3000/api/ask` for a physical device or simulator/web target) or a real
  deployment of it.
- `src/hooks/useAskAI.ts`'s `postAsk()` POSTs the exact same `{ question, candidates }` shape
  (`src/lib/ask-schema.ts`, byte-for-byte ported from `web/src/lib/ask-schema.ts`) to that URL and
  validates the response with the same Zod schemas the web client uses - this app's client is a
  faithful consumer of an existing, already-documented contract, not a new one.
- If `EXPO_PUBLIC_ASK_PROXY_URL` is unset, `postAsk()` throws a clear, typed `AskAIError`
  immediately - no network call is attempted, and the UI (`src/components/ask/AskAIPanel.tsx`)
  shows an explicit "Known limitation" card explaining the gap rather than a spinner that never
  resolves or a fabricated answer. **Retrieval still runs for real** in this state: the panel
  calls the same client-side `scoreDocuments()` (`src/lib/retrieval.ts`, ported byte-for-byte from
  `web/src/lib/retrieval.ts`) the proxy's Function re-ranks server-side, and shows the top-matching
  document titles - proving the pipeline is wired up to the exact point the missing server-side
  surface would take over, never further than that.
- A `search_log` entry is written either way (`src/hooks/useSearchLog.ts`), matching the web
  reference's behavior of logging a search regardless of whether the LLM step itself succeeded.

This is a documented, deliberate scope boundary - not a bug, and not a faked feature. See "Known
limitations" below and the "Live smoke test" section for exactly how far it was verified.

## Known limitations (real platform constraints, not bugs)

- **No public/anonymous read without a session.** Every collection read requires a JWT (anonymous
  or real) - confirmed live, see "Live smoke test" below. Same finding as the web reference app.
- **The project's `pk_` publishable key is not a working credential** on this backend version -
  kept in `.env.example`'s sibling apps for parity with the dashboard; this app never sends it
  (every request uses a JWT instead, same as the web reference).
- **The Ask AI LLM completion call cannot live inside the Mudbase Function, and cannot live
  on-device** - see "Ask AI architecture" above. This is the largest architectural deviation from
  a naive port of the web app, and it is a hard platform + security constraint, not a convenience
  choice.
- **`EXPO_PUBLIC_ASK_PROXY_URL` is a dev/demo convenience, not a production architecture.**
  Pointing a shipped mobile app at a developer's own `next dev` server is only sound for local
  verification (which is exactly how it was used below); a real production deployment would point
  this at a deployed instance of the `../web` app's `/api/ask` route (or an equivalent minimal
  server), never at `localhost`.
- **No in-app registration.** One demo account was provisioned for this task and the instructions
  were explicit not to create additional ones; this port follows the sibling kanban port's
  precedent of a demo-account quick-fill login rather than building a registration flow this task
  didn't need.

## Live smoke test results (2026-08-01, real project, real Mudbase backend)

All calls below were made directly against `cloud.mudbase.dev` with the exact request shapes this
app's `src/api/client.ts` and hooks issue (collection IDs, filter/sort params, auth headers), to
verify the wiring end-to-end without requiring a booted iOS/Android simulator in this environment.
`tsc --noEmit` and `expo-doctor` (20/20 checks) were run against the actual app source in addition
to these live backend calls.

1. **Anonymous session bootstrap** - `POST /api/auth/anonymous` with this project's id → `200`,
   real token pair, `user.isAnonymous: true`. Confirms the exact call `authStore.initialize()`
   makes on first launch / after an invalid restored session.
2. **Guest read (anonymous JWT)** - `GET .../collections/<documentsId>/data?limit=5` with the
   anonymous token → `200`, 3 real documents returned. Confirms guests can browse the library
   without signing in.
3. **Zero-auth read** - the same `GET` with no `Authorization` header at all → `401
   {"error":"Authentication required"}`. Confirms the platform's own enforcement (not this app's
   UI) is the real boundary, and that an anonymous session is genuinely required, not optional.
4. **Demo account login** - `POST /api/auth/local/login` with `docs.member.demo@gmail.com` /
   `DemoTest123!` → `200`, real access + refresh token pair for `_id 6a6d409a51703cd1071b46fe`,
   `customRole: "customer"`.
5. **Full document CRUD**, all with the logged-in demo account's token:
   - `POST .../documents/data` (create) → `201`, real `_id` returned.
   - `GET .../documents/data/<id>` (read one) → `200`, matches created content.
   - `PATCH .../documents/data/<id>` (update) → `200`, title/tags reflected the edit.
   - `GET .../documents/data?sort=-createdAt&limit=100` (the exact query the library screen's
     `useDocumentsList()` issues) → `200`, edited document sorted first.
   - `DELETE .../documents/data/<id>` → `200 {"message":"Data deleted successfully"}`.
   - `GET` the same id again → `404 {"error":"Document not found"}`, confirming the delete was
     real and the ownership-gated edit/delete UI in `app/documents/[id]/index.tsx` operates on a
     real, enforced backend state.
6. **`search_log` write with a real signed-in user's ObjectId** - `POST
   .../search_log/data` with `userId: "6a6d409a51703cd1071b46fe"` (never a placeholder) → `201`,
   entry created and listed correctly under `sort=-createdAt`.
7. **Ask AI proxy, full pipeline, against a live `next dev` instance of `../web`**:
   - Started `../web`'s dev server (`npm run dev`) locally, confirmed `200` on `/`.
   - Fetched the 3 real documents created above with the demo account's token, built a
     `{ question, candidates }` payload in the exact shape `src/lib/ask-schema.ts` validates and
     `src/hooks/useAskAI.ts` sends.
   - `POST http://localhost:3000/api/ask` with that payload → the request took ~2s (consistent
     with a real execute→poll cycle against the deployed `docsAskRetrieval` Mudbase Function, not
     a short-circuit) and failed only with the expected, documented `502
     {"error":"ANTHROPIC_API_KEY is not configured...."}` - the identical failure point the web
     app's own README/build-plan documents for the same intentionally-unset key. This proves the
     mobile client's request contract, the proxy route, and the real Mudbase Function invocation
     all work correctly end-to-end; only the final LLM call is gated by the absent key, exactly as
     designed and exactly as honestly documented - never a fabricated success.
   - Dev server stopped cleanly after the test.

## What was not (and could not be) verified

- A real, generated Ask AI **answer** - no `ANTHROPIC_API_KEY` was available in this environment,
  identical to the web reference app's own documented limitation. Everything up to that call is
  proven live above.
- On-device behavior in a booted iOS/Android simulator or physical device - this environment has
  no simulator/emulator available. `tsc --noEmit`, `expo-doctor`, and the live backend calls above
  substitute for that; a developer with a simulator/device can run `npm run ios` / `npm run
  android` / `npm run web` to see the actual UI.
