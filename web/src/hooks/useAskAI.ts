"use client"

import { useMutation } from "@tanstack/react-query"
import { AskResponseSchema, AskErrorResponseSchema, type AskRequest, type AskResponse } from "@/lib/ask-schema"

export class AskAIError extends Error {}

async function postAsk(payload: AskRequest): Promise<AskResponse> {
  const res = await fetch("/api/ask", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  })

  const json: unknown = await res.json().catch(() => null)

  if (!res.ok) {
    const parsedError = AskErrorResponseSchema.safeParse(json)
    throw new AskAIError(parsedError.success ? parsedError.data.error : `Ask AI request failed (${res.status})`)
  }

  const parsed = AskResponseSchema.safeParse(json)
  if (!parsed.success) {
    throw new AskAIError("Ask AI returned an unexpected response shape")
  }
  return parsed.data
}

export function useAskAI() {
  return useMutation<AskResponse, AskAIError, AskRequest>({
    mutationFn: postAsk,
  })
}
