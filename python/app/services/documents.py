"""documents collection: public (authenticated, including the anonymous
guest session) read, `customer`-role-only create/update/delete — enforced
server-side by Mudbase collection permissions (see plan/build-plan.md), not
re-checked here beyond the ownership check routers apply for edit/delete.
"""

import asyncio
from typing import Any

from app.config import get_settings
from app.mudbase_client import create_data_sync, delete_data_sync, get_data_sync, list_data_sync, update_data_sync
from app.schemas.document import Document, DocumentFormValues

# The Python SDK's DataApi.list_data validates `limit` client-side with
# `Field(le=100, strict=True)` — passing anything above 100 raises a
# ValidationError before the request is even sent, unlike the reference web
# app's direct-fetch client which isn't bound by that constraint (it uses
# limit=200 for the Ask AI candidate pool). 100 is the effective ceiling for
# every list read in this app.
_LIBRARY_LIMIT = 100


async def list_documents(*, access_token: str | None = None) -> list[Document]:
    settings = get_settings()
    result = await asyncio.to_thread(
        list_data_sync,
        settings.documents_collection_id,
        sort="-createdAt",
        limit=_LIBRARY_LIMIT,
        access_token=access_token,
    )
    return [Document.model_validate(doc) for doc in result["data"]]


async def get_document(document_id: str, *, access_token: str | None = None) -> Document | None:
    settings = get_settings()
    doc = await asyncio.to_thread(get_data_sync, settings.documents_collection_id, document_id, access_token=access_token)
    return Document.model_validate(doc) if doc else None


async def create_document(
    values: DocumentFormValues,
    *,
    author_id: str,
    author_name: str,
    access_token: str,
) -> Document:
    settings = get_settings()
    body: dict[str, Any] = {
        "title": values.title,
        "content": values.content,
        "tags": values.tags or None,
        "authorId": author_id,
        "authorName": author_name,
    }
    doc = await asyncio.to_thread(create_data_sync, settings.documents_collection_id, body, access_token=access_token)
    return Document.model_validate(doc)


async def update_document(
    document_id: str,
    values: DocumentFormValues,
    *,
    access_token: str,
) -> Document:
    settings = get_settings()
    body: dict[str, Any] = {
        "title": values.title,
        "content": values.content,
        "tags": values.tags or None,
    }
    doc = await asyncio.to_thread(
        update_data_sync, settings.documents_collection_id, document_id, body, access_token=access_token
    )
    return Document.model_validate(doc)


async def delete_document(document_id: str, *, access_token: str) -> None:
    settings = get_settings()
    await asyncio.to_thread(delete_data_sync, settings.documents_collection_id, document_id, access_token=access_token)
