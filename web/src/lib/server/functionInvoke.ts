import "server-only"
import type { AskRequestCandidate } from "@/lib/ask-schema"

/**
 * Invokes the deployed Mudbase Function (`docsAskRetrieval`) that ranks candidate documents by
 * keyword overlap and assembles a grounded context block. This is server-only code: the
 * MUDBASE_FUNCTIONS_API_KEY below is an org-scoped `ak_` API key with `functions` permission,
 * created specifically for this purpose (see plan/build-plan.md "Ask AI architecture" for why -
 * short version: the project end-user JWT this app otherwise uses can only ever satisfy
 * rbacCheck("functions","read"), never "create", which is what the /execute route requires).
 * This key must never be sent to the browser - it only ever leaves this process as an outbound
 * request to cloud.mudbase.dev.
 */

interface FunctionCitation {
  documentId: string
  title: string
  score: number
}

export interface RetrievalResult {
  contextBlock: string
  citations: FunctionCitation[]
  usedCount: number
  error?: string
}

interface ExecuteResponse {
  success: boolean
  data?: { executionId: string; status: string }
  error?: string
}

interface ExecutionStatusResponse {
  success: boolean
  data?: {
    status: "queued" | "running" | "success" | "failed" | "timeout"
    result?: RetrievalResult
    error?: string | null
  }
  error?: string
}

const POLL_INTERVAL_MS = 600
const POLL_TIMEOUT_MS = 20_000

function requireServerEnv(name: string): string {
  const value = process.env[name]
  if (!value) {
    throw new Error(
      `Missing required server-only environment variable: ${name}. See web/README.md "LLM setup" and .env.example.`,
    )
  }
  return value
}

export async function invokeRetrievalFunction(
  question: string,
  candidates: AskRequestCandidate[],
): Promise<RetrievalResult> {
  const baseUrl = process.env.NEXT_PUBLIC_MUDBASE_URL ?? "https://cloud.mudbase.dev"
  const projectId = requireServerEnv("NEXT_PUBLIC_MUDBASE_PROJECT_ID")
  const functionId = requireServerEnv("MUDBASE_FUNCTION_ID")
  const apiKey = requireServerEnv("MUDBASE_FUNCTIONS_API_KEY")

  const executeRes = await fetch(
    `${baseUrl}/api/functions/projects/${projectId}/functions/${functionId}/execute`,
    {
      method: "POST",
      headers: { "X-API-Key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({ payload: { question, candidates } }),
    },
  )

  const executeBody = (await executeRes.json().catch(() => null)) as ExecuteResponse | null
  if (!executeRes.ok || !executeBody?.success || !executeBody.data) {
    throw new Error(
      `Mudbase Function execute request failed (${executeRes.status}): ${executeBody?.error ?? "unknown error"}`,
    )
  }

  const { executionId } = executeBody.data
  const pollUrl = `${baseUrl}/api/functions/projects/${projectId}/functions/${functionId}/executions/${executionId}`
  const deadline = Date.now() + POLL_TIMEOUT_MS

  while (Date.now() < deadline) {
    const pollRes = await fetch(pollUrl, { headers: { "X-API-Key": apiKey } })
    const pollBody = (await pollRes.json().catch(() => null)) as ExecutionStatusResponse | null
    if (!pollRes.ok || !pollBody?.success || !pollBody.data) {
      throw new Error(`Mudbase Function execution poll failed (${pollRes.status})`)
    }

    const { status } = pollBody.data
    if (status === "success") {
      if (!pollBody.data.result) throw new Error("Function execution succeeded but returned no result")
      return pollBody.data.result
    }
    if (status === "failed" || status === "timeout") {
      throw new Error(`Mudbase Function execution ${status}: ${pollBody.data.error ?? "unknown error"}`)
    }

    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS))
  }

  throw new Error("Timed out waiting for the Mudbase Function execution to complete")
}
