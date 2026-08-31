import { useMutation } from "@tanstack/react-query";
import { AskResponseSchema, AskErrorResponseSchema, type AskRequest, type AskResponse } from "@/lib/ask-schema";
import { ASK_PROXY_URL } from "@/config/env";

export class AskAIError extends Error {}

/**
 * See plan/build-plan.md "Ask AI architecture" for the full reasoning. Short version: this app has
 * no server of its own, and the Ask AI completion step structurally cannot happen anywhere else -
 * not on-device (no LLM key may ever ship in a mobile bundle) and not inside the Mudbase Function
 * (its isolated-vm sandbox has zero network access, verified against the runner source). The one
 * real fix that doesn't invent new backend infrastructure: point `EXPO_PUBLIC_ASK_PROXY_URL` at
 * the sibling `../web` reference app's already-built, already-verified `POST /api/ask` Route
 * Handler (or a deployment of it) - that route already does both required steps (invoke the
 * org-keyed Mudbase Function for retrieval ranking, then call the LLM) behind a real network
 * stack. This hook is a thin, honest client for that contract; it never holds or sends any LLM
 * or Function API key itself.
 */
async function postAsk(payload: AskRequest): Promise<AskResponse> {
  if (!ASK_PROXY_URL) {
    throw new AskAIError(
      "Ask AI has no proxy configured (EXPO_PUBLIC_ASK_PROXY_URL is unset) - this is a documented " +
        "architectural gap, not a bug. See plan/build-plan.md \"Ask AI architecture\".",
    );
  }

  let res: Response;
  try {
    res = await fetch(ASK_PROXY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Network request failed";
    throw new AskAIError(`Could not reach the Ask AI proxy at ${ASK_PROXY_URL}: ${message}`);
  }

  const json: unknown = await res.json().catch(() => null);

  if (!res.ok) {
    const parsedError = AskErrorResponseSchema.safeParse(json);
    throw new AskAIError(parsedError.success ? parsedError.data.error : `Ask AI request failed (${res.status})`);
  }

  const parsed = AskResponseSchema.safeParse(json);
  if (!parsed.success) {
    throw new AskAIError("Ask AI proxy returned an unexpected response shape");
  }
  return parsed.data;
}

export function useAskAI() {
  return useMutation<AskResponse, AskAIError, AskRequest>({
    mutationFn: postAsk,
  });
}
