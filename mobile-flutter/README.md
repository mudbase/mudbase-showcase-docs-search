# Mudbase Showcase - Docs Search (Flutter)

A Flutter reimplementation of the [Mudbase Showcase Docs Search knowledge-base app](../web) -
guest browsing, document CRUD, client-side keyword search, and Ask AI - talking directly to
`cloud.mudbase.dev` through the real, generated **Mudbase Dart SDK** (`mudbase_sdk`,
[github.com/mudbase/mudbase-sdk](https://github.com/mudbase/mudbase-sdk), `dart/` subdirectory),
with **zero custom backend of its own**.

## Stack

Flutter + Dart, Riverpod (`flutter_riverpod`, no code generation) for state, go_router for
navigation, `flutter_secure_storage` for the auth token. Same architecture as the sibling
`mudbase-showcase-kanban`/`mudbase-showcase-social` Flutter ports - see "Architecture decisions"
below for why plain Riverpod rather than `riverpod_generator`/`freezed`.

## Setup

The Mudbase Dart SDK is **not published to pub.dev** - `pubspec.yaml` references it as a relative
path dependency assuming a sibling-clone layout:

```yaml
mudbase_sdk:
  path: ../../mudbase-sdk/dart
```

`mobile-flutter/` sits one level inside the `mudbase-showcase-docs-search` repo, so reaching a
flat sibling of that repo takes exactly two `../` segments (`mobile-flutter/` →
`mudbase-showcase-docs-search/` → parent → `mudbase-sdk/dart`).

Before anything else, clone `mudbase-sdk` as a sibling of `mudbase-showcase-docs-search` itself
(same parent directory):

```bash
# from the directory that contains mudbase-showcase-docs-search/
git clone https://github.com/mudbase/mudbase-sdk.git
```

So the layout looks like:

```
some-parent-dir/
├── mudbase-sdk/
│   └── dart/                  ← the SDK pubspec.yaml lives here
└── mudbase-showcase-docs-search/
    └── mobile-flutter/        ← this app
```

Then:

```bash
cd mobile-flutter

# First time only (or after upgrading Flutter) - generates/refreshes the
# android/, ios/, etc. platform folders. Safe to re-run.
flutter create .

flutter pub get

cp dart_define.example.json dart_define.json
# dart_define.example.json already contains this showcase's real,
# already-provisioned project/collection ids (they're public, not secrets -
# see "Security" below). Override only if pointing at your own project.

flutter run --dart-define-from-file=dart_define.json
```

### Config (`--dart-define-from-file`, this project's Flutter convention)

Never a runtime `.env` file - every value is read via `String.fromEnvironment` in
`lib/config/env_config.dart`, which also defaults every key to this showcase's real,
already-provisioned project. `dart_define.example.json` documents every key:

| Key | Notes |
|---|---|
| `MUDBASE_PROJECT_ID` | Not a secret - same as the web app's `NEXT_PUBLIC_MUDBASE_PROJECT_ID`. |
| `DOCUMENTS_COLLECTION_ID` | |
| `SEARCH_LOG_COLLECTION_ID` | |
| `MUDBASE_BASE_URL` | Defaults to `https://cloud.mudbase.dev`. |

`main()` calls `EnvConfig.assertConfigured()` before `runApp` and fails fast with a clear message
if any required key is somehow left empty.

**There is no secret of any kind in this app** - every value above is safe to ship in a mobile
bundle. This is a deliberate architectural property, not an incidental one: see "Ask AI" below.

## Demo account

Sign in from the library screen's "Sign in" button, or from the Ask AI screen after asking a
question as a guest:

| Role | Email | Password |
|---|---|---|
| Member (`customer`) | `docs.member.demo@gmail.com` | `DemoTest123!` |

Guests can browse the library and use Ask AI's retrieval ranking with no signup at all - an
anonymous session is established automatically on first launch. Registration is also available
(`Sign up`) for a new `customer` account, which requires email verification before its first login.

## What it demonstrates

| Feature | Mudbase capability | Where |
|---|---|---|
| Guest browsing, no signup required | `POST /api/auth/anonymous` | `lib/features/auth/auth_controller.dart` |
| Email/password accounts | `POST /api/auth/local/signup/customer` | `lib/features/auth/register_screen.dart` |
| Document library, client-side keyword search | Collection read + on-device substring match | `lib/features/library/` |
| Document CRUD, ownership-scoped edit/delete | Collection CRUD, `documents` | `lib/data/repositories/document_repository.dart`, `lib/features/document_detail/`, `lib/features/document_form/` |
| **Ask AI** - on-device keyword retrieval ranking, honestly-scoped | On-device Dart port of the reference platform Function's own scoring algorithm | `lib/features/ask/` - see `plan/build-plan.md` "Ask AI architecture" |
| Recent searches | Collection read, `search_log` | `lib/features/ask/widgets/recent_searches.dart` |

## Ask AI: what's real and what isn't (read this before judging the feature incomplete)

This is the actual point of this showcase, not an oversight. Full reasoning, source citations, and
a live-verified proof the underlying algorithm is correct: `plan/build-plan.md` → "Ask AI
architecture".

**Short version:** an LLM API key can never be embedded in a mobile binary - this project's own
security rules and this app's own task brief are both explicit and absolute about that. The less
obvious finding this build made: the *same* is true of the org-scoped API key the web reference
app uses to invoke its deployed Mudbase Function, because that key is provisioned with broad
`functions` CRUD permissions on the whole org, not narrowly scoped to "run this one Function" - a
mobile binary embedding it would be exactly the same class of exposure as embedding an LLM key,
just with a different blast radius. Since this app ships no server of its own to hold either
secret, it makes one deliberate, documented choice rather than two separate workarounds:

- **The retrieval-ranking algorithm runs entirely on-device**, in pure Dart
  (`lib/core/retrieval.dart`) - the identical title×3/tags×2/content×1 weighting the deployed
  Mudbase Function itself uses server-side, verified by directly invoking that Function once
  during this build (see `plan/build-plan.md`) and confirming its output. This needs no secret at
  all, and it is real, live computation against real documents - not a mock.
- **There is no synthesized natural-language answer.** The Ask AI screen shows the ranked source
  documents (tap to open), followed by a clearly labeled card explaining why there's no paragraph
  of prose above them. No fake "AI answer", no hardcoded response.

## RBAC / ownership model

There is a single default customer role with full CRUD on both collections for a signed-in
account. Document create/edit/delete is gated to signed-in users in the UI, and edit/delete is
further gated to `document.authorId == user.id`. This build's own live smoke test directly probed
whether the platform enforces this server-side (not just via this app's UI) by attempting raw
writes from a different identity than the document's author - both a guest write attempt and a
cross-identity edit attempt were **rejected with a real HTTP 403** - see
`plan/build-plan.md` → "Live Smoke Test Results".

## Realtime

None - this app polls/refetches on mutation and pull-to-refresh, same as the reference web app
(no Socket.IO usage in either the web reference or this port; unlike the sibling kanban port,
which does have a realtime board).

## Known limitations (real platform/architecture constraints, not bugs)

See `plan/build-plan.md` → "Known Limitations" - Ask AI's answer-synthesis gap (the actual point of
this showcase, not an oversight), the shared demo project's login/anonymous-session rate limit
(5 requests/15 min per IP, shared across every language/platform port's own smoke test), and no
offline cache/push notifications (out of scope for this showcase).

## Architecture decisions

- **Riverpod without code generation**, same reason as the sibling `mudbase-showcase-kanban`/
  `mudbase-showcase-social` ports: this environment has no Flutter SDK installed to iteratively
  verify `build_runner` output locally - every provider and model here is verifiable by
  `dart analyze` alone (and, for the Flutter-free layer, actually was - see
  `plan/build-plan.md` "Testing Note").
- **Always-available session, never a hard sign-in wall** - a deliberate difference from the
  kanban port's auth model; see `plan/build-plan.md` "Stack Decisions" for the full reasoning.
- **No secret of any kind ships in this app** - not by omission, but because this build concluded
  that the org-scoped Functions API key the web reference relies on is exactly as unsafe to embed
  client-side as an LLM key would be. See "Ask AI" above.

## Testing

`test/core/` and `test/models/` use plain `package:test` (not `flutter_test`) specifically so they
run with **plain `dart test`, independent of the Flutter SDK** - and they were: **42/42 passed**
in this build (see `plan/build-plan.md` "Testing Note" for exactly how, since this project's own
`pubspec.yaml` can't `pub get` without Flutter installed either).

```bash
dart test test/core test/models   # runs today, no Flutter SDK needed
flutter test                      # once Flutter is installed
```

`tool/manual_test.dart` is a standalone live smoke-test script against the real project - see
`plan/build-plan.md` → "Live Smoke Test Results"; it was executed for real during this build via
the scratch-package technique documented there, and will run directly with `dart run` (or
`flutter pub get` first) once Flutter is installed in a given environment.

## Verification

```bash
dart format --set-exit-if-changed .
dart analyze     # requires `flutter pub get` first once Flutter is installed
flutter test
```

## License

MIT - see the repo root [LICENSE](../LICENSE).
