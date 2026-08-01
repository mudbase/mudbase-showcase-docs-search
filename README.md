# Mudbase Showcase — Docs Search

An AI-powered knowledge-base search app built **entirely on [Mudbase](https://www.mudbase.dev)** —
auth, database, and serverless Functions — with **zero custom backend**. The same app,
reimplemented once per official Mudbase SDK, so every supported language has a real, runnable
reference app rather than a toy snippet.

Every version talks to the same Mudbase project shape (see `web/plan/build-plan.md` for the
collection/permission schema) and demonstrates the same feature set: a document knowledge base,
keyword search, and an "Ask AI" feature that retrieves the most relevant documents and asks an LLM
to answer grounded in them — via a Mudbase Function, so the LLM API key never touches the client.

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

Retrieval is simple keyword/substring matching across `title`+`content` (no vector DB dependency,
to keep this achievable entirely on Mudbase's own primitives). The "Ask AI" call runs inside a
Mudbase Function — you supply your own LLM API key (OpenAI/Anthropic/etc.) as a Function
environment variable, which Mudbase masks in every API response regardless of role. This also
demonstrates that masking guarantee directly.

## License

MIT — see [LICENSE](./LICENSE).
