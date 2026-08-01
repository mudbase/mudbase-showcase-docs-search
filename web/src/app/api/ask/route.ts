import { NextResponse } from "next/server"
import { AskRequestSchema } from "@/lib/ask-schema"
import { invokeRetrievalFunction } from "@/lib/server/functionInvoke"
import { generateGroundedAnswer } from "@/lib/server/llm"

export const runtime = "nodejs"

/**
 * The only server-side route in this app. It exists purely because of two verified platform
 * constraints documented in plan/build-plan.md "Ask AI architecture":
 *
 * 1. The Mudbase Function execute endpoint requires rbacCheck("functions","create"), which a
 *    project end-user JWT (org role always "viewer") can never satisfy - only an org-scoped
 *    ak_ API key can invoke it. That key must stay server-side.
 * 2. The Function's own sandbox (isolated-vm) has zero network access, so it cannot make the
 *    outbound HTTPS call to the LLM provider itself - that call has to happen somewhere with a
 *    real network stack, which is this route.
 *
 * The retrieval-ranking work is real, deployed Mudbase Function code (see functionInvoke.ts);
 * this route's own job is limited to: validate the request, invoke that Function, then make a
 * single grounded completion call. No business logic lives here beyond what those two
 * constraints force out of the client.
 */
export async function POST(request: Request): Promise<Response> {
  let rawBody: unknown
  try {
    rawBody = await request.json()
  } catch {
    return NextResponse.json({ error: "Request body must be valid JSON" }, { status: 400 })
  }

  const parsed = AskRequestSchema.safeParse(rawBody)
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0]
    return NextResponse.json({ error: firstIssue?.message ?? "Invalid request body" }, { status: 400 })
  }

  const { question, candidates } = parsed.data

  try {
    const retrieval = await invokeRetrievalFunction(question, candidates)

    if (retrieval.usedCount === 0) {
      return NextResponse.json({
        answer:
          "I couldn't find anything in the knowledge base closely related to that question. Try rephrasing, or add a document that covers it.",
        citations: [],
        usedCount: 0,
      })
    }

    const answer = await generateGroundedAnswer(question, retrieval.contextBlock)

    return NextResponse.json({
      answer,
      citations: retrieval.citations.map((citation) => ({
        documentId: citation.documentId,
        title: citation.title,
      })),
      usedCount: retrieval.usedCount,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Ask AI request failed"
    // Server-side only - never includes the ANTHROPIC_API_KEY or MUDBASE_FUNCTIONS_API_KEY
    // values themselves, only the error text a failed fetch/SDK call produces.
    console.error("[api/ask] request failed:", message)
    return NextResponse.json({ error: message }, { status: 502 })
  }
}
