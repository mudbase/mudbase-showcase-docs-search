"""The one place in this codebase that calls a third-party LLM API.
`ANTHROPIC_API_KEY` is a server-only setting (see app/config.py) — it is
never rendered into a template or exposed to any client. See
plan/build-plan.md "Ask AI architecture" for why this call happens here
rather than inside the Mudbase Function itself: the Function's `isolated-vm`
sandbox has no network primitives at all (no outbound HTTPS of any kind —
verified against the actual runner source, see the plan doc), so it cannot
call an LLM provider no matter what env var it holds. The Function still
does real work (keyword-overlap retrieval ranking + grounded context
assembly, see app/services/function_invoke.py) — this module only performs
the completion call the sandbox is structurally incapable of making itself.

Since this port is already a server process (unlike the reference Next.js
app, which needed a dedicated Route Handler purely to get *any* real network
stack involved), this call simply lives in the same service layer as
everything else — no separate "route handler" boundary is needed here.
"""

import asyncio

from anthropic import Anthropic

from app.config import get_settings

_DEFAULT_MODEL = "claude-opus-5"

_SYSTEM_PROMPT = (
    "You are a support assistant for a documentation knowledge base. Answer the user's "
    "question using ONLY the document excerpts provided below - never your own outside "
    "knowledge. If the excerpts do not contain enough information to answer, say so plainly "
    "rather than guessing. Keep the answer concise (a few sentences to a short paragraph). "
    "When you use a fact from an excerpt, mention which document it came from by its title."
)

_MAX_TOKENS = 1024


class LlmNotConfiguredError(Exception):
    """Raised when ANTHROPIC_API_KEY is unset — see app/config.py docstring
    for why this is a runtime error rather than a startup failure."""


class LlmResponseError(Exception):
    """Raised when the model refuses, or returns no usable text content."""


async def generate_grounded_answer(question: str, context_block: str) -> str:
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise LlmNotConfiguredError(
            "ANTHROPIC_API_KEY is not configured. This is a server-only setting (see "
            'README.md "LLM setup" and .env.example) - the developer running this app must '
            "supply their own key."
        )
    return await asyncio.to_thread(
        _generate_sync, question, context_block, settings.anthropic_api_key, settings.llm_model
    )


def _generate_sync(question: str, context_block: str, api_key: str, model: str) -> str:
    client = Anthropic(api_key=api_key)

    stripped_context = context_block.strip()
    user_content = (
        f"Question: {question}\n\nDocument excerpts:\n{context_block}"
        if stripped_context
        else f"Question: {question}\n\n"
        "(No document excerpts were retrieved - say you don't have enough information in the "
        "knowledge base to answer.)"
    )

    message = client.messages.create(
        model=model or _DEFAULT_MODEL,
        max_tokens=_MAX_TOKENS,
        system=_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_content}],
    )

    for block in message.content:
        if block.type == "text":
            return block.text

    if message.stop_reason == "refusal":
        raise LlmResponseError("The model declined to answer this question.")
    raise LlmResponseError("The model returned no text content")
