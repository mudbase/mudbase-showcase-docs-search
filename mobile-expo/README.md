# Mudbase Showcase - Docs Search (mobile-expo)

A knowledge-base search app built **entirely on [Mudbase](https://www.mudbase.dev)** for its data
layer - auth, database, and search retrieval - with **no custom backend of its own for anything
except one optional, reused proxy call** (see "Ask AI" below). This is the Expo/React Native port
of the reference [`../web`](../web) Next.js app: same Mudbase project, same two collections, same
data model, same Ask AI request/response contract.

## Stack

Expo Router (SDK 57) + TypeScript (strict) + NativeWind + TanStack Query + Zustand + Zod +
react-hook-form, talking directly to `cloud.mudbase.dev` via the real generated
[`mudbase-sdk`](https://github.com/mudbase/mudbase-sdk) (`AuthenticationApi` + `DataApi`). Every
document/search-log request is made with the signed-in (or anonymous guest) user's own JWT.

Architecture mirrors the sibling [`mudbase-showcase-kanban/mobile-expo`](../../mudbase-showcase-kanban/mobile-expo)
and [`mudbase-showcase-social/mobile-expo`](../../../mudbase-showcase-social/mobile-expo) ports:
same file layout (`src/api`, `src/config`, `src/lib`, `src/stores`, `src/providers`, `src/hooks`,
`src/components/{ui,auth,documents,ask,layout}`), same SecureStore token pattern, same
single-retry-on-401 refresh.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Guest browsing via anonymous session, real login for authors | `POST /api/auth/anonymous` / `POST /api/auth/local/login` | `src/api/client.ts`, `src/stores/authStore.ts` |
| Document library with client-side keyword search (title/content/tags) | Collection read, `documents` | `app/(tabs)/index.tsx`, `src/lib/retrieval.ts` |
| Document CRUD, ownership-scoped edit/delete | Collection CRUD, `documents` | `src/hooks/useDocuments.ts`, `app/documents/**` |
| Recent search log | Collection read/write, `search_log`, `sort: "-createdAt"` | `src/hooks/useSearchLog.ts` |
| Ask AI: retrieval always live; LLM step via an optional shared proxy | Mudbase Function (`docsAskRetrieval`) + a reused Next.js Route Handler | `src/components/ask/AskAIPanel.tsx`, `src/hooks/useAskAI.ts` |

## Auth model

Every collection read requires *some* JWT - verified live against this exact project (every read
401s with zero auth, even with the project's own `pk_` key). An anonymous session
(`createAnonymousSession()`) lets guests browse and search without a login screen; publishing,
editing, deleting a document, and attributing a search log entry to a real user still require
signing in. There is no in-app registration - sign in with the provisioned demo account via the
login screen's "Use demo account" button, or manual email/password entry.

## Ask AI - the one feature that needs something this app doesn't have

This mobile app has no server of its own. The Ask AI feature's LLM completion call **cannot**
happen on-device (no LLM API key may ever ship in a mobile bundle) and **cannot** happen inside the
Mudbase Function that ranks candidate documents (its `isolated-vm` sandbox has zero network
access - see `../web/plan/build-plan.md` for the verified platform source backing that). See
`plan/build-plan.md` "Ask AI architecture" for the full reasoning; short version:

- **Retrieval always runs for real**, live, whether or not anything below is configured - the
  library's search box and Ask AI's candidate-scoring both call the same client-side
  `scoreDocuments()`/`matchesSearchTerm()` (`src/lib/retrieval.ts`).
- **The LLM completion step is reached through an optional, configurable proxy** -
  `EXPO_PUBLIC_ASK_PROXY_URL` - pointed at the sibling `../web` app's already-built, already-live-
  verified `POST /api/ask` Route Handler (or a real deployment of it). That route is the one place
  in this whole showcase with a genuine server-side network stack, so it's reused rather than
  duplicated.
- **Leave it unset and the app stays fully honest about the gap**: the Ask screen shows a "Known
  limitation" card and still displays the top keyword-matched document titles, instead of a
  spinner that never resolves or a fabricated answer.

To try the full pipeline locally:

```bash
cd ../web && npm install && npm run dev   # starts the reference app's dev server on :3000
```

Then set `EXPO_PUBLIC_ASK_PROXY_URL=http://localhost:3000/api/ask` in this app's `.env` (already
set that way by default) and restart Expo. Without a real `ANTHROPIC_API_KEY` in `../web/.env.local`,
the request will succeed through retrieval and fail only at the documented, expected
`"ANTHROPIC_API_KEY is not configured"` step - see `plan/build-plan.md` "Live smoke test results"
for the exact verified request/response trace.

## Getting started

```bash
npm install
cp .env.example .env   # already points at the shared demo project below; edit if you provision your own
npm run start           # or: npm run ios / npm run android / npm run web
```

Demo account: `docs.member.demo@gmail.com` / `DemoTest123!` (already provisioned - do not create
new ones).

## Provisioning (already exists on Mudbase, not in this repo)

This app expects a Mudbase project already set up with:

1. Local auth enabled, plus anonymous sessions, on the platform's single default `customer` role
   with full CRUD on both collections below.
2. Two collections - `documents` (`title`, `content`, `tags?`, `authorId`, `authorName`) and
   `search_log` (`queryText`, `userId?`, `userName?`, `resultCount`).
3. A deployed Mudbase Function named `docsAskRetrieval` and an org-scoped API key permissioned for
   `functions` - both provisioned once for the whole showcase (shared with `../web`), never
   through this app's own UI.

`.env.example` lists every id and optional var this app needs.

## Known limitations (real platform constraints, not bugs - see plan/build-plan.md for detail)

- Ask AI's LLM completion step requires the optional proxy described above; without it, the
  screen honestly shows retrieval-only results and explains why.
- No `ANTHROPIC_API_KEY` was available in the build/test environment, so a real generated answer
  was not observed - only the documented, expected failure at that exact step.
- `EXPO_PUBLIC_ASK_PROXY_URL` pointed at a `localhost` dev server is a local-verification
  convenience, not a production architecture.
- No in-app registration flow (see "Auth model" above for why).

## Live smoke test

See `plan/build-plan.md` → "Live smoke test results" for the full request-by-request verification
against the real project: anonymous session bootstrap, guest read, zero-auth 401, demo login, full
document CRUD (create/read/update/delete with a confirmed 404 afterward), a `search_log` write with
a real user's ObjectId, and the Ask AI proxy pipeline running end-to-end against a live `../web`
dev server up to the documented LLM-key gap.
