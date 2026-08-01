# Mudbase Showcase — Docs Search

An AI-powered knowledge-base search app built almost entirely on **[Mudbase](https://www.mudbase.dev)**
— auth, database, and a serverless Function for retrieval ranking. The same app, reimplemented
once per official Mudbase SDK, so every supported language has a real, runnable reference app
rather than a toy snippet.

Every version talks to the same Mudbase project shape (see `web/plan/build-plan.md` for the
collection/permission schema) and demonstrates the same feature set: a document knowledge base,
keyword search, and an "Ask AI" feature that retrieves the most relevant documents and asks an LLM
to answer grounded in them.

The LLM API key never touches the client, but it does **not** live inside the Function itself —
Mudbase Functions run in a sandbox with zero network access (verified against the platform's own
`isolated-vm` runner source), so a Function cannot make the outbound call to an LLM provider no
matter what env var it holds. Each port's Function does the retrieval-ranking work the sandbox
*can* do; the LLM completion call happens in the smallest possible server-side surface the host
language provides (e.g. a single Next.js Route Handler for the web port), authorized by a
Mudbase API key scoped only to invoking that Function. See `web/plan/build-plan.md` "Ask AI
architecture" for the full reasoning, source citations, and live verification.

## Versions in this repo

| Directory | Platform | SDK |
|---|---|---|
| [`web/`](./web) | Next.js 15 (App Router) web app | JavaScript/TypeScript |
| [`mobile-expo/`](./mobile-expo) | Expo / React Native mobile app | JavaScript/TypeScript |
| [`mobile-flutter/`](./mobile-flutter) | Flutter mobile app | Dart |
| [`python/`](./python) | Server-rendered web app | Python |
| [`go/`](./go) | Server-rendered web app | Go |
| [`ruby/`](./ruby) | Server-rendered web app | Ruby |
| [`java/`](./java) | Server-rendered web app (Spring Boot) | Java |
| [`csharp/`](./csharp) | Server-rendered web app (ASP.NET Core) | C# |
| [`php/`](./php) | Server-rendered web app | PHP |
| [`swift/`](./swift) | iOS app (SwiftUI) | Swift |

Each directory is self-contained with its own README, dependency manifest, and `.env.example` —
clone this repo and only set up the language you care about.

## Prerequisite: clone the SDK repo as a sibling

Most versions here (everything except `python/`, `go/`, and `ruby/`, whose package managers can
install straight from a git subdirectory) reference the [mudbase-sdk](https://github.com/mudbase/mudbase-sdk)
repo by relative path, since none of the 9 SDKs are published to a public registry yet. Clone it
next to this repo, at the same parent directory level, before building any version besides `web/`:

```
some-folder/
├── mudbase-sdk/                      # git clone https://github.com/mudbase/mudbase-sdk
└── mudbase-showcase-docs-search/     # this repo
```

## Data model & AI architecture

- **documents** — `title`, `content`, `tags?`, `authorId`, `authorName`
- **search_log** — `queryText`, `userId?`, `userName?`, `resultCount`

Retrieval is simple keyword/substring matching across `title`+`content`+`tags` (no vector DB
dependency, to keep this achievable entirely on Mudbase's own primitives). A real, deployed
Mudbase Function re-ranks the shortlisted candidates and assembles a grounded context block; the
actual LLM completion call (Anthropic Claude by default — you supply your own API key) happens in
each port's smallest possible server-side surface, since the Function's own sandbox has no
network access to call an LLM provider directly — see `web/plan/build-plan.md` "Ask AI
architecture" for the full reasoning and source citations.

## License

MIT — see [LICENSE](./LICENSE).
