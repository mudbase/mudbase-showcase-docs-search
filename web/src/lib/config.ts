function requireEnv(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Missing required environment variable: ${name}`)
  return value
}

export const MUDBASE_PROJECT_ID = requireEnv(
  "NEXT_PUBLIC_MUDBASE_PROJECT_ID",
  process.env.NEXT_PUBLIC_MUDBASE_PROJECT_ID,
)
export const MUDBASE_URL = process.env.NEXT_PUBLIC_MUDBASE_URL ?? "https://cloud.mudbase.dev"

// Project publishable key - not currently sent on any request (see src/lib/mudbase.ts and
// plan/build-plan.md "Known limitations" for why: this backend's authOrApiKey middleware only
// recognizes ak_-prefixed org API keys, not this project-level pk_ field). Kept for parity with
// the platform dashboard.
export const MUDBASE_API_KEY = process.env.NEXT_PUBLIC_MUDBASE_API_KEY ?? ""

export const DOCUMENTS_COLLECTION_ID = requireEnv(
  "NEXT_PUBLIC_DOCUMENTS_COLLECTION_ID",
  process.env.NEXT_PUBLIC_DOCUMENTS_COLLECTION_ID,
)
export const SEARCH_LOG_COLLECTION_ID = requireEnv(
  "NEXT_PUBLIC_SEARCH_LOG_COLLECTION_ID",
  process.env.NEXT_PUBLIC_SEARCH_LOG_COLLECTION_ID,
)
