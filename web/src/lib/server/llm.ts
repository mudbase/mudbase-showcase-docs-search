import "server-only"
import Anthropic from "@anthropic-ai/sdk"

/**
 * The one place in this codebase that calls a third-party LLM API. ANTHROPIC_API_KEY is a
 * server-only environment variable (never NEXT_PUBLIC_) - it is never sent to, or readable by,
 * the browser. See plan/build-plan.md "Ask AI architecture" for why this call happens here
 * rather than inside the Mudbase Function itself: the Function's isolated-vm sandbox has no
 * network primitives at all (no fetch, no http/https module - verified against the actual
 * runner source, see the plan doc), so it cannot make an outbound HTTPS call to any LLM
 * provider. The Function still does real work (keyword-overlap retrieval ranking + grounded
 * context assembly, see functionInvoke.ts) - this module only performs the completion call the
 * sandbox is structurally incapable of making itself.
 */

const DEFAULT_MODEL = "claude-opus-5"

const SYSTEM_PROMPT = `You are a support assistant for a documentation knowledge base. Answer the user's
question using ONLY the document excerpts provided below - never your own outside knowledge. If the
excerpts do not contain enough information to answer, say so plainly rather than guessing. Keep the
answer concise (a few sentences to a short paragraph). When you use a fact from an excerpt, mention
which document it came from by its title.`

export async function generateGroundedAnswer(question: string, contextBlock: string): Promise<string> {
  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    throw new Error(
      "ANTHROPIC_API_KEY is not configured. This is a server-only env var (see web/README.md " +
        '"LLM setup" and .env.example) - the developer running this app must supply their own key.',
    )
  }

  const client = new Anthropic({ apiKey })
  const model = process.env.LLM_MODEL || DEFAULT_MODEL

  const userContent = contextBlock.trim()
    ? `Question: ${question}\n\nDocument excerpts:\n${contextBlock}`
    : `Question: ${question}\n\n(No document excerpts were retrieved - say you don't have enough information in the knowledge base to answer.)`

  const message = await client.messages.create({
    model,
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content: userContent }],
  })

  const textBlock = message.content.find(
    (block): block is Anthropic.TextBlock => block.type === "text",
  )
  if (!textBlock) {
    if (message.stop_reason === "refusal") {
      throw new Error("The model declined to answer this question.")
    }
    throw new Error("The model returned no text content")
  }
  return textBlock.text
}
