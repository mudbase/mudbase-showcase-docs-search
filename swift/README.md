# Mudbase Showcase - Docs Search (SwiftUI / iOS)

A production-shaped SwiftUI iOS knowledge-base app built entirely on top of
[Mudbase](https://www.mudbase.dev) - auth, database, and (for retrieval ranking) a real
serverless Function - reimplementing the same reference app as the companion Next.js app in
`../web/`: same two collections (`documents`, `search_log`), same permissions model, same auth
flow. Auth, the document library, document detail/CRUD, and search all talk directly to
`cloud.mudbase.dev` through the real generated Mudbase Swift SDK.

**Read "Ask AI architecture" below before anything else in this file.** It's the actual point of
this showcase, and this port makes a different, deliberate call than the web reference app for a
reason specific to mobile apps - not a missed feature.

## Why SPM, not an `.xcodeproj`

This package is deliberately `.xcodeproj`-free - same rationale as the sibling
`../../mudbase-showcase-ecommerce/swift` and `../../mudbase-showcase-social/swift` ports this
app's architecture is ported from. Since Xcode 14, you can open a `Package.swift` directly and run
an `executableTarget` that defines a SwiftUI `App` (`@main`) as a real iOS app on a Simulator or
device - Xcode synthesizes the Info.plist/bundle at build time, no project file needed. `swift
build` from the CLI also succeeds on plain macOS - the `platforms` list in `Package.swift`
includes `.macOS(.v14)` purely so this can be verified without Xcode; no UIKit-only symbols are
used anywhere in this target.

## Setup

1. **Clone the SDK as a sibling directory.** From the same parent directory that contains this
   monorepo (`mudbase-showcase-docs-search/`):
   ```bash
   git clone https://github.com/mudbase/mudbase-sdk.git
   ```
   You should end up with:
   ```
   parent/
     mudbase-showcase-docs-search/
       swift/            <- this package (Package.swift lives here)
       web/
       ...
     mudbase-sdk/
       swift/            <- the SDK package Package.swift references
       ...
   ```

2. **The SwiftPM identity-collision workaround symlink is already committed.** This app's own SPM
   package directory is named `swift` (see the monorepo layout above) and the SDK's own Swift
   subdirectory is *also* named `swift`. SwiftPM computes a local path dependency's package
   "identity" from the last path component of the path you give it, with no way to override that -
   so a plain `.package(path: "../../mudbase-sdk/swift")` would give this app's own package and its
   SDK dependency the *same* identity ("swift"), and dependency resolution would silently conflate
   them. `mudbase-showcase-docs-search/mudbase-sdk-swift` is a relative symlink
   (`-> ../mudbase-sdk/swift`) that already exists at this monorepo's root for exactly this reason
   - the same workaround the ecommerce and social Swift ports established first.
   `Package.swift` references `../mudbase-sdk-swift`, not `../../mudbase-sdk/swift`.

3. **Configure.** Copy `Config.example.plist` to `Config.plist` (same directory) - it already has
   this showcase's real, already-provisioned project and collection IDs filled in, so no values
   need to be looked up:
   ```bash
   cp Config.example.plist Config.plist
   ```
   | Key | Value |
   |---|---|
   | `MudbaseProjectId` | `6a6d3faad07caabbbdfc5698` |
   | `MudbaseBaseURL` | `https://cloud.mudbase.dev` (default, rarely needs changing) |
   | `DocumentsCollectionId` | `6a6d3fcdd07caabbbdfc5842` |
   | `SearchLogCollectionId` | `6a6d3fcdd07caabbbdfc5857` |

   None of these are secrets - a project/collection ID isn't sensitive (same rationale as
   `../web/.env.example`). `Config.plist` is still gitignored to keep this out of history as a
   matter of convention. `AppConfig.load` also reads `MUDBASE_PROJECT_ID` /
   `MUDBASE_DOCUMENTS_COLLECTION_ID` / etc. environment variables as a fallback, convenient for
   `swift run` during development; if neither source resolves every required key, the app renders
   a "Configuration required" screen instead of crashing (see `ConfigurationRequiredView.swift`).

4. **Open and run.**
   ```bash
   open Package.swift
   ```
   In Xcode: pick an iOS Simulator (or a physical device) as the run destination from the scheme
   selector, then Run. If you add `Config.plist` to the project navigator, make sure it's added to
   the `MudbaseShowcaseDocsSearch` target's "Copy Bundle Resources" build phase (Xcode does this
   automatically when you drag the file in with "Add to target" checked).

## What's implemented

- **Auth** - email/password login and self-signup (always `customer`, this project's one role),
  plus an **anonymous guest session** so the library is publicly browsable before signing in.
  Session bootstrap from Keychain on launch, sign-out. Token pair stored in the Keychain via
  `Support/KeychainTokenStore.swift` - never `UserDefaults`. A 401 from an expired access token is
  transparently refreshed and retried once, for *every* authenticated call in the app (reads under
  the guest session included) - see `Networking/AccessTokenCoordinator.swift`.
- **Library** - document list (newest first) with a client-side search box (substring match across
  title/content/tags, `Retrieval.matchesSearchTerm`), a "New document" action gated to signed-in
  users.
- **Document detail** - full content, author, tags, and Edit/Delete actions gated to
  `user.id == document.authorId` (`DocumentDetailViewModel.isOwner`).
- **Document form** - shared create/edit form (`DocumentFormView`), plain client-side validation
  mirroring the web app's zod schema (title/content required, length caps, tags optional).
- **Ask AI** - real, on-device keyword retrieval against the live document set, with a clearly
  labeled, honest gap where the web app's LLM-synthesized answer would be. **This is the actual
  point of this showcase - see the next section.**
- **Recent searches** - the 10 most recent `search_log` entries, written by both the Ask AI screen
  and read back on the same screen (`RecentSearchesView`).
- **Auth-gated writes, public reads** - every collection read works under the anonymous guest
  session (verified live: every read 401s with zero auth, even the project's own `pk_`
  publishable key - see "Live verification" below); creating/editing/deleting a document is gated
  server-side by this project's own Mudbase collection permissions, and this app's own
  `AppUser.isGuest`/`isOwner` checks are UX routing, not the security boundary.

## Ask AI architecture - the actual point of this showcase

### What the web reference app does, and why an iOS app can't do the same thing

`../web/plan/build-plan.md` "Ask AI architecture" documents two independently-verified platform
constraints (against the real `mudbase-backend` source, not inferred from behavior):

1. **A project end-user JWT can never invoke a Mudbase Function.** The `/execute` route requires
   org role `owner`/`admin`/`developer`; every project end-user - including a real, signed-in
   `customer` account - always carries org role `viewer`, which only grants `functions:read`.
2. **A Mudbase Function's own sandbox (`isolated-vm`) has zero network access** - no `fetch`, no
   `http`/`https` module, no way to reach an external API. This is a deliberate security boundary
   (the platform's prior sandbox had a real, exploitable realm-escape bug), not an oversight.

The web app's answer to both: a real, deployed Mudbase Function (`docsAskRetrieval`,
`_id 6a6d431ef09e238c3e62b2f4`) does the retrieval-ranking work the sandbox *can* do (re-score
candidate documents by query-term overlap, build a grounded context block); an org-scoped `ak_`
Mudbase API key (server-only) authorizes invoking it; and the one call the sandbox structurally
cannot make - the outbound HTTPS request to the Anthropic Claude API - happens in the web app's
own `POST /api/ask` Next.js Route Handler, the smallest possible server-side surface the
constraints force out of an otherwise-Mudbase-only client.

**A SwiftUI iOS app has no equivalent of that Route Handler.** There is no server process this app
owns - only the binary running on the user's device. Both of the constraints above still apply
(a signed-in `customer` on iOS carries the exact same org role `viewer` as on web; the Function's
sandbox has the same zero network access regardless of which client called it), and this port has
no third option a Route Handler would give it: embedding either secret - the `ak_` Function
invocation key or the LLM provider's own API key - directly in the app bundle is the one thing
explicitly ruled out for this build. A distributed mobile binary can be unpacked and its strings
extracted trivially; this project's own security rules require secrets to live in environment
variables only, never in a client bundle, no exceptions. (See the sibling
`../../mudbase-showcase-ecommerce/swift` port's `Networking/PayLinkGateway.swift` for the
established precedent this monorepo already uses when a mobile port genuinely needs a privileged
operation: delegate to an *already-deployed* web app's own server-side proxy route. This port
deliberately does not assume such a deployed proxy exists - see "What was actually built instead"
below for why.)

### What was actually built instead

`AskAIViewModel` performs **only the retrieval step**, for real, on-device, against the real
documents just fetched from the live Mudbase project - using `Support/Retrieval.swift`, a Swift
port of `../web/src/lib/retrieval.ts`'s `scoreDocuments` with the *exact same* weights the
deployed Function itself uses: title ×3, tags ×2, content ×1. Because the weights match exactly,
this on-device scoring is not a lesser stand-in for the Function's ranking - it produces the same
relative ordering the Function would for the same inputs. This was independently confirmed twice
for this port:

1. **A direct `curl` against the live, deployed Function** (using the `ak_` key already
   provisioned for the web app's own build, reused here strictly for this port's own verification -
   never embedded in any Swift source), reproducing the exact same request/response the web app's
   own smoke test used:
   ```
   POST /api/functions/projects/6a6d3faad07caabbbdfc5698/functions/6a6d431ef09e238c3e62b2f4/execute
     payload: { question: "How do I reset my password?", candidates: [Password Reset Guide, Billing FAQ] }
   → 202 { executionId, status: "queued" }
   → poll → status: "success", durationMs: 40
   → result: { citations: [{ title: "Password Reset Guide", score: 12 }], usedCount: 1,
               contextBlock: "## Password Reset Guide\nTo reset your password, go to account
               settings and click reset password. You will receive an email link.\n\n" }
   ```
   "Billing FAQ" scored 0 and was filtered out entirely - the Function correctly ranked only the
   relevant document.
2. **`Tests/ManualLiveFlowTests/RetrievalTests.swift`** (always-on, offline, no network - runs on
   every plain `swift test`) feeds the identical two documents and question into
   `Retrieval.scoreDocuments` and asserts the same outcome: exactly one document scores above
   zero, and it's "Password Reset Guide." This test is what should catch it first if these weights
   ever drift from the Function's own.

What this port does **not** do is synthesize a natural-language answer from that ranking - the
actual "AI" in "Ask AI." That step needs the LLM provider's API key, which cannot live on-device
under any circumstance, and this app has no server-side surface to make that call from instead.
Rather than fabricate a fake answer string (which would misrepresent what genuinely happened),
`AskAIView` shows the ranked, cited source documents directly - a real, useful, fully-working
search result - with an explicit, visible notice (`architectureNotice` in `AskAIView.swift`)
explaining exactly why there's no written answer and pointing back to this section. `search_log`
is still written with the real result count, exactly as the web app does (never a placeholder
`userId` - see `SearchLogService.log`).

This is the single largest, and most deliberate, architectural deviation from the web reference
app in this entire port. It is not a bug, not a missing feature, and not a corner cut for time -
it is the honest answer to "what does Ask AI look like on a platform with literally no
server-side surface at all."

### If you want the full LLM-synthesized answer on iOS

The only way to add it without violating the "never embed a secret in the client" rule is to point
this app at a small server-side proxy - either the web app's own `POST /api/ask` route (once
deployed somewhere reachable, e.g. Vercel) or a purpose-built endpoint with the same contract. That
would be a `Networking/AskGateway.swift` making a plain `URLSession` call to
`{proxyBaseURL}/api/ask`, exactly mirroring the ecommerce Swift port's `PayLinkGateway` pattern -
intentionally not built here, since this port makes no assumption that such a deployment exists.

## Architecture

```
Sources/MudbaseShowcaseDocsSearch/
  App/            @main entry point
  Config/         AppConfig (Config.plist + env var loader)
  Support/        Keychain, API error mapping, platform shims, navigation reference types,
                  formatting helpers, and Retrieval.swift (the client-side scoring engine)
  Networking/     Thin wrappers over the generated SDK's async calls (auth, generic collection CRUD)
  Models/         DocumentRecord, SearchLogRecord, AppUser - decoded from Mudbase JSON
  Services/       SessionStore, TabRouter (both @MainActor ObservableObject),
                  DocumentsService, SearchLogService
  ViewModels/     One @MainActor ObservableObject per screen
  Views/          SwiftUI views, grouped by feature area (Auth, Library, DocumentDetail,
                  DocumentForm, Ask, Account, Shared)
```

`SessionStore` and `TabRouter` are the two app-wide stores (created once in the `App` struct and
injected via `.environmentObject`); every other view model is constructed explicitly by its owning
view (passed `config` and, where relevant, the current user) rather than reached for via
`@EnvironmentObject`, so each screen's real dependencies stay visible at its call site - same
convention the ecommerce and social Swift ports use.

Three tabs: **Library** and **Ask AI** are both always browsable (real user or guest); **Account**
shows the sign-in/sign-up screen while the session is still the anonymous guest, or account info +
sign out once signed in - the same "the tab that gates sign-in also shows account state once
signed in" convention the social Swift port uses for its Profile tab. The web reference app has no
dedicated account page (`Header.tsx` puts a bare sign-out button in the nav) - this tab is the
natural native-app home for that action.

## The Mudbase Swift SDK, exactly as generated

Every Mudbase call in this app goes through the real generated `MudbaseSDK` async/await methods -
none of the signatures below were guessed; each was confirmed by grepping
`../mudbase-sdk/swift/Sources/MudbaseSDK/APIs/*.swift` before being used:

- `AuthenticationAPI.createAnonymousSession`, `.loginLocalUser`, `.getLocalSession(projectId:)`,
  `.refreshToken`, `.logoutLocalUser`
- `MultiRoleFeatureAPI.registerWithRole(role:registerWithRoleRequest:)`
- `DataAPI.listData` / `.getData` / `.createData` / `.updateData` / `.deleteData`

`AuthGateway.currentUser()` reads `AuthenticationAPI.getLocalSession(projectId:)` rather than
`getCurrentSession()` - deliberately: the latter takes no `projectId` and returns the org-level
`User` model (`owner`/`admin`/`member`/`viewer` roles only), which can never surface this
project's `customer` custom role or an anonymous session's `isAnonymous` flag. `getLocalSession`
is the call that actually round-trips this project's Multi-Role data - the same choice the
sibling ecommerce/social Swift ports made.

## Verification

There is no iOS Simulator in this build environment, so verification took two forms:

1. **`swift build`** succeeds cleanly (zero warnings) on macOS - the `platforms` list in
   `Package.swift` sets a secondary `.macOS(.v14)` target purely for this; the real deployment
   target is `.iOS(.v16)`.
2. **`Tests/ManualLiveFlowTests/RetrievalTests.swift`** - 7 always-on, offline unit tests covering
   the exact scoring weights, tokenization, substring search, and top-N truncation behind both the
   Library search box and Ask AI. Runs on every plain `swift test`, no network, no gating:
   ```bash
   swift test --filter RetrievalTests
   ```
3. **Direct `curl` round-trips against the real, live project** (`6a6d3faad07caabbbdfc5698`),
   reproducing the exact request shapes this app's own `AuthGateway`/`DocumentsService`/
   `SearchLogService` send, confirmed working:
   - `GET` a collection with zero auth → `401` (even with the project's `pk_` key as
     `X-API-Key`) - confirms the guest anonymous-session requirement.
   - `POST /api/auth/anonymous` → real token pair, `user.isAnonymous: true`,
     `user.customRole` absent.
   - `GET` the `documents` collection with the anonymous token → `200`.
   - `POST /api/auth/local/login` with `docs.member.demo@gmail.com` → real access + refresh
     token pair, `user.customRole: "customer"`, `user.emailVerified: true`.
   - `GET /api/auth/local/session` → full session document matching what
     `AuthGateway.currentUser()` decodes.
   - Full document CRUD: `POST` create → `GET` single doc → `PATCH` update → `GET` list
     (`sort=-createdAt&limit=5`, confirms `pagination` shape) → `POST` a `search_log` entry with
     the real signed-in user's ObjectId as `userId` → `DELETE` → confirmed `404` afterward.
   - The `docsAskRetrieval` Function itself, directly - see "Ask AI architecture" above for the
     full transcript.
4. **`Tests/ManualLiveFlowTests/ManualLiveFlowTests.swift`** - a headless Swift Testing suite that
   exercises this app's own `AuthGateway`/`DocumentsService`/`SearchLogService`/
   `AccessTokenCoordinator` types directly (the exact types the SwiftUI views call), against the
   same live project, covering everything item 3 above does plus the 401-refresh-and-retry policy
   under a deliberately invalidated access token. Disabled by default (a plain `swift test` never
   makes network calls or writes real documents); run explicitly with:
   ```bash
   RUN_LIVE_FLOW_TEST=1 swift test --filter ManualLiveFlowTests
   ```
   **Result (2026-08-01, against the live project):** `Test fullDocsSearchFlow() passed after
   6.702 seconds` - zero failures, covering every step above: anonymous read + 403 on
   anonymous create, demo account login with `customRole: "customer"`, full document CRUD
   (create → list → get → update → delete → confirmed 404), a `search_log` write with the real
   signed-in user's ObjectId, and a forced-401 refresh-and-retry that transparently recovered a
   call made with a deliberately invalidated access token. All 7 `RetrievalTests` passed
   alongside it in the same run (8 tests total, 2 suites, 0 failures).

   This project's `/api/auth/anonymous` and `/api/auth/local/login` endpoints are rate-limited per
   IP - a real, shared budget across every sibling language port's own verification runs against
   this same project (and against the direct `curl` calls in item 3 above, run from the same
   machine): the first two attempts at this suite hit `429`s from that shared budget before it
   cleared. `resolveSession` accepts an optional pre-minted access/refresh token pair via
   `DEMO_ACCESS_TOKEN`/`DEMO_REFRESH_TOKEN` environment variables and uses those instead of
   calling `login` when set, the same contingency the sibling social Swift port's own test
   anticipated:
   ```bash
   RUN_LIVE_FLOW_TEST=1 DEMO_ACCESS_TOKEN=... DEMO_REFRESH_TOKEN=... swift test --filter ManualLiveFlowTests
   ```

## Known limitations (real platform/SDK constraints, not bugs)

- **The Ask AI LLM completion step cannot run anywhere in this app** - see "Ask AI architecture"
  above. This is the single largest architectural deviation from the web reference app, and it's a
  hard platform + security constraint (a mobile binary cannot hold either secret the step needs),
  not a shortcut.
- **No `users` collection** - every author name in this data model is denormalized onto the
  document that references them (`authorName`), matching the web app's own schema.
- **No email-verification deep-link screen.** This app has no associated-domain/universal-links
  configuration in scope for this build, so `RegisterView` shows the same "check your inbox, then
  sign in" message the web app shows immediately after registering, but there is no in-app way to
  complete that link - the user finishes verification in their email client, then returns to this
  app and signs in normally. This doesn't block the app's primary path (the pre-verified demo
  account above), only fresh self-registration.
- **The project's `pk_` publishable key is not a working credential** on this backend version
  (same finding as every sibling showcase app) - kept in `Config.example.plist`'s sibling `.env`
  files for parity with the platform dashboard; no request in this app actually uses it.
- **Certificate pinning and biometric auth are out of scope**, same call as every sibling Swift
  port's README for the same reason - a focused reimplementation, not a production hardening pass.
  Keychain-only token storage is implemented as a baseline correctness requirement, not an
  additive hardening feature.
- **The SwiftPM package-identity collision** described in "Setup" step 2 - a genuine SwiftPM
  constraint (identity = last path component, no override), not a bug in this app's manifest.
- **Shared per-IP auth rate limits** on `/api/auth/anonymous` and `/api/auth/local/login` - see
  "Verification" item 4 above - can make `ManualLiveFlowTests` need a retry or pre-minted tokens
  when run alongside other sibling ports' own live verification against the same project.

## License

MIT - see the repo root [LICENSE](../LICENSE).
