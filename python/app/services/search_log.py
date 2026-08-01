"""search_log collection: written after every Ask AI question (successful or
not), read back for the "Recent searches" panel on /ask. Mirrors
web/src/components/ask/RecentSearches.tsx and the logSearch mutation in
web/src/components/ask/AskAIPanel.tsx.
"""

import asyncio
import logging
from typing import Any

from app.config import get_settings
from app.mudbase_client import MudbaseApiError, create_data_sync, list_data_sync
from app.schemas.search_log import SearchLogEntry

logger = logging.getLogger(__name__)

_RECENT_SEARCHES_LIMIT = 10


async def list_recent_searches(*, access_token: str | None = None) -> list[SearchLogEntry]:
    settings = get_settings()
    result = await asyncio.to_thread(
        list_data_sync,
        settings.search_log_collection_id,
        sort="-createdAt",
        limit=_RECENT_SEARCHES_LIMIT,
        access_token=access_token,
    )
    return [SearchLogEntry.model_validate(doc) for doc in result["data"]]


async def log_search(
    query_text: str,
    result_count: int,
    *,
    user_id: str | None,
    user_name: str | None,
    access_token: str,
) -> None:
    """Best-effort: a failed write here should never block the Ask AI answer
    the visitor already received (mirrors the reference app's own fire-and-
    forget `logSearch.mutateAsync` call, which is not on the critical path
    for displaying the answer)."""
    settings = get_settings()
    body: dict[str, Any] = {"queryText": query_text, "resultCount": result_count}
    # userId/userName must be a real ObjectId/name or omitted entirely — never a placeholder string.
    if user_id:
        body["userId"] = user_id
    if user_name:
        body["userName"] = user_name
    try:
        await asyncio.to_thread(create_data_sync, settings.search_log_collection_id, body, access_token=access_token)
    except MudbaseApiError as exc:
        logger.warning("search_log write failed (non-fatal): %s", exc.message)
