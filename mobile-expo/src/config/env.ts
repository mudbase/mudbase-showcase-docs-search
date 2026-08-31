/**
 * All values here are read from EXPO_PUBLIC_* env vars - Expo's convention for anything safe to
 * bundle into the client binary. A project/collection id is not a secret (see .env.example) -
 * every request this app makes to Mudbase authenticates with a real JWT (anonymous session for
 * guests, a real signed-in user's session after login), never a static key.
 */
function requireEnv(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(
      `Missing required environment variable: ${name}. Copy .env.example to .env and fill in your provisioned Mudbase project's IDs.`,
    );
  }
  return value;
}

export const MUDBASE_URL = process.env.EXPO_PUBLIC_MUDBASE_URL ?? "https://cloud.mudbase.dev";

export const MUDBASE_PROJECT_ID = requireEnv(
  "EXPO_PUBLIC_MUDBASE_PROJECT_ID",
  process.env.EXPO_PUBLIC_MUDBASE_PROJECT_ID,
);

export const DOCUMENTS_COLLECTION_ID = requireEnv(
  "EXPO_PUBLIC_DOCUMENTS_COLLECTION_ID",
  process.env.EXPO_PUBLIC_DOCUMENTS_COLLECTION_ID,
);

export const SEARCH_LOG_COLLECTION_ID = requireEnv(
  "EXPO_PUBLIC_SEARCH_LOG_COLLECTION_ID",
  process.env.EXPO_PUBLIC_SEARCH_LOG_COLLECTION_ID,
);

/**
 * Deliberately NOT validated with requireEnv - Ask AI is allowed to run in a "retrieval wired,
 * LLM step architecturally unavailable" state when this is unset (see plan/build-plan.md "Ask AI
 * architecture"). `null` (not undefined) makes the "unconfigured" state an explicit, checkable
 * value for the UI rather than an empty string silently reaching fetch().
 */
export const ASK_PROXY_URL: string | null = process.env.EXPO_PUBLIC_ASK_PROXY_URL || null;
