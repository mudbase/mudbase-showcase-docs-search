"""Ask AI — the actual point of this showcase. Mirrors web/src/app/ask/page.tsx,
web/src/components/ask/AskAIPanel.tsx and web/src/app/api/ask/route.ts, all
collapsed into one server-rendered flow since this process already has a
real network stack (see app/services/llm.py docstring for exactly why the
reference Next.js app needed a dedicated Route Handler for this and this
port doesn't need an equivalent internal boundary).

Full request flow on POST /ask, matching the reference app's contract:
1. Fetch the document library (same collection read the library page uses).
2. Score every document against the question by keyword overlap
   (app/services/retrieval.py, ported from web/src/lib/retrieval.ts).
3. If nothing scores above zero: show "no match", log a zero-result search,
   skip the Function/LLM calls entirely (no point asking either to work with
   zero candidates).
4. Otherwise take the top 5 candidates (content truncated to bound payload
   size) and invoke the real deployed Mudbase Function `docsAskRetrieval`
   (app/services/function_invoke.py) for retrieval-ranking + grounded
   context assembly.
5. If the Function itself finds nothing worth citing (`used_count == 0`),
   short-circuit with the same "couldn't find anything closely related"
   message the reference app returns — again, skip the LLM call.
6. Otherwise call the LLM (app/services/llm.py) for the actual grounded
   completion, using the Function's context block.
7. Log the search (query, result count, and — only for a real signed-in
   user — their own id/name, never a placeholder) regardless of how far the
   pipeline got, mirroring the reference app's own always-log behavior.
"""

import logging
from typing import Annotated

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse
from pydantic import ValidationError

from app.context import build_base_context
from app.mudbase_client import MudbaseApiError
from app.schemas.ask import AskFormValues
from app.schemas.document import Document
from app.schemas.search_log import SearchLogEntry
from app.services import documents as documents_service
from app.services import retrieval
from app.services import search_log as search_log_service
from app.services.function_invoke import MudbaseFunctionError, invoke_retrieval_function
from app.services.llm import LlmNotConfiguredError, LlmResponseError, generate_grounded_answer
from app.session import call_with_reauth, ensure_anonymous_session, get_session_user, get_valid_access_token
from app.templates_env import templates
from app.utils import field_errors

router = APIRouter()
logger = logging.getLogger(__name__)

_TOP_CANDIDATES_LIMIT = 5
_NO_FUNCTION_MATCH_MESSAGE = (
    "I couldn't find anything in the knowledge base closely related to that question. "
    "Try rephrasing, or add a document that covers it."
)


@router.get("/ask", response_class=HTMLResponse, response_model=None)
async def ask_page(request: Request) -> HTMLResponse:
    await ensure_anonymous_session(request)
    token = await get_valid_access_token(request)

    recent_searches: list[SearchLogEntry] = []
    if token:
        try:
            recent_searches, _token = await call_with_reauth(
                request, token, lambda t: search_log_service.list_recent_searches(access_token=t)
            )
        except MudbaseApiError:
            recent_searches = []

    context = await build_base_context(request)
    context.update(
        {
            "errors": {},
            "question": "",
            "answer": None,
            "citations": [],
            "no_match": False,
            "ask_error": None,
            "recent_searches": recent_searches,
        }
    )
    return templates.TemplateResponse(request=request, name="ask.html", context=context)


@router.post("/ask", response_class=HTMLResponse, response_model=None)
async def ask_submit(request: Request, question: Annotated[str, Form()]) -> HTMLResponse:
    await ensure_anonymous_session(request)
    token = await get_valid_access_token(request)
    user = get_session_user(request)

    try:
        values = AskFormValues(question=question)
    except ValidationError as exc:
        recent_searches = await _safe_recent_searches(request, token)
        context = await build_base_context(request)
        context.update(
            {
                "errors": field_errors(exc),
                "question": question,
                "answer": None,
                "citations": [],
                "no_match": False,
                "ask_error": None,
                "recent_searches": recent_searches,
            }
        )
        return templates.TemplateResponse(request=request, name="ask.html", context=context, status_code=422)

    trimmed_question = values.question

    documents: list[Document] = []
    if token:
        try:
            documents, token = await call_with_reauth(
                request, token, lambda t: documents_service.list_documents(access_token=t)
            )
        except MudbaseApiError:
            documents = []

    scored = retrieval.score_documents(documents, trimmed_question)

    answer: str | None = None
    citations: list[dict[str, str]] = []
    no_match = False
    ask_error: str | None = None
    result_count = 0

    if not scored:
        # Client-side keyword scoring found nothing at all — mirrors the
        # reference app's own early return before ever calling the Function.
        no_match = True
    else:
        candidates = retrieval.top_candidates(scored, _TOP_CANDIDATES_LIMIT)
        try:
            retrieval_result = await invoke_retrieval_function(trimmed_question, candidates)
        except MudbaseFunctionError as exc:
            ask_error = str(exc)
            logger.error("[ask] Function invocation failed: %s", exc)
        else:
            if retrieval_result.used_count == 0:
                # The Function itself found nothing worth citing among the
                # candidates. Mirrors the reference route's own short-circuit:
                # this is rendered as the answer text (no citations), not the
                # "no_match" state above — the client never distinguishes the
                # two either.
                answer = _NO_FUNCTION_MATCH_MESSAGE
            else:
                try:
                    answer = await generate_grounded_answer(trimmed_question, retrieval_result.context_block)
                except (LlmNotConfiguredError, LlmResponseError) as exc:
                    ask_error = str(exc)
                    logger.error("[ask] LLM completion failed: %s", exc)
                else:
                    citations = [
                        {"document_id": citation.document_id, "title": citation.title}
                        for citation in retrieval_result.citations
                    ]
                    result_count = len(citations)

    if token:
        try:
            await search_log_service.log_search(
                trimmed_question,
                result_count,
                user_id=user.id if user else None,
                user_name=user.display_name if user else None,
                access_token=token,
            )
        except MudbaseApiError as exc:
            logger.warning("[ask] search_log write failed (non-fatal): %s", exc.message)

    recent_searches = await _safe_recent_searches(request, token)

    context = await build_base_context(request)
    context.update(
        {
            "errors": {},
            "question": trimmed_question,
            "answer": answer,
            "citations": citations,
            "no_match": no_match,
            "ask_error": ask_error,
            "recent_searches": recent_searches,
        }
    )
    return templates.TemplateResponse(request=request, name="ask.html", context=context)


async def _safe_recent_searches(request: Request, token: str | None) -> list[SearchLogEntry]:
    if not token:
        return []
    try:
        recent_searches, _token = await call_with_reauth(
            request, token, lambda t: search_log_service.list_recent_searches(access_token=t)
        )
    except MudbaseApiError:
        return []
    return recent_searches
