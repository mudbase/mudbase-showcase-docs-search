"""Document library: search box (server-side substring match across
title/content/tags, mirroring the reference SPA's client-side filter) plus
the document grid. Mirrors web/src/app/page.tsx.
"""

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.context import build_base_context
from app.mudbase_client import MudbaseApiError
from app.schemas.document import Document
from app.services import retrieval
from app.services import documents as documents_service
from app.session import call_with_reauth, ensure_anonymous_session, get_valid_access_token
from app.templates_env import templates

router = APIRouter()

_LOAD_ERROR_MESSAGE = "Failed to load documents. Please try again."


@router.get("/", response_class=HTMLResponse, response_model=None)
async def library_page(request: Request, q: str | None = None) -> HTMLResponse:
    await ensure_anonymous_session(request)
    token = await get_valid_access_token(request)

    documents: list[Document] = []
    load_error: str | None = None
    if token:
        try:
            documents, _token = await call_with_reauth(
                request, token, lambda t: documents_service.list_documents(access_token=t)
            )
        except MudbaseApiError:
            load_error = _LOAD_ERROR_MESSAGE
    else:
        load_error = _LOAD_ERROR_MESSAGE

    query = (q or "").strip()
    filtered = [document for document in documents if retrieval.matches_search_term(document, query)]

    context = await build_base_context(request)
    context.update({"documents": filtered, "query": query, "load_error": load_error})
    return templates.TemplateResponse(request=request, name="library.html", context=context)
