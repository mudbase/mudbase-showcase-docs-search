"""Invokes the deployed Mudbase Function (`docsAskRetrieval`) that ranks
candidate documents by keyword overlap and assembles a grounded context
block. See plan/build-plan.md "Ask AI architecture" for the two independently
verified platform constraints this exists to work around — short version: a
project end-user JWT can never invoke a Function (org role is always
`viewer`, satisfying only `functions:read`), so an org-scoped `ak_` API key
is required, and that key must never be exposed to any template or client —
it is only ever used from `app.mudbase_client`'s server-side SDK calls.

## Discovered platform bug, worked around here (not in the Function itself)

Live-tested against the real deployed Function during this port's build: its
code reads `doc._id` when building each citation (`citations.push({
documentId: doc._id, title: doc.title, score: ... })`), but the payload
contract this app (and the reference web app) sends uses `documentId`, not
`_id`, for each candidate. Sent as originally specified, every citation came
back with `documentId: undefined` — confirmed live via a direct
execute/poll round trip against the real Function
(`_id 6a6d431ef09e238c3e62b2f4`) before this was noticed. Since the deployed
Function is shared, already-provisioned infrastructure this port does not
own or redeploy, the fix lives entirely on the caller's side: every candidate
sent in the payload below includes its document ID under both `documentId`
AND `_id`, so the Function's own field lookup succeeds too. Re-verified live
after the fix — citations now come back with a real, matching `documentId`.
This is an honest, documented workaround, not a silent patch.
"""

import asyncio
import time
from dataclasses import dataclass

from app.config import get_settings
from app.mudbase_client import MudbaseApiError, execute_function_sync, get_function_execution_sync
from app.schemas.ask import AskCandidate, AskCitation

_POLL_INTERVAL_SECONDS = 0.6
_POLL_TIMEOUT_SECONDS = 20.0
_TERMINAL_STATUSES = {"success", "failed", "timeout"}


class MudbaseFunctionError(Exception):
    """Raised when the Function execute/poll round trip fails or times out."""


@dataclass(frozen=True)
class RetrievalResult:
    context_block: str
    citations: list[AskCitation]
    used_count: int


async def invoke_retrieval_function(question: str, candidates: list[AskCandidate]) -> RetrievalResult:
    settings = get_settings()
    payload = {
        "question": question,
        "candidates": [
            {
                "documentId": candidate.document_id,
                # See module docstring: works around the deployed Function's
                # own `doc._id` field lookup.
                "_id": candidate.document_id,
                "title": candidate.title,
                "content": candidate.content,
                **({"tags": candidate.tags} if candidate.tags else {}),
            }
            for candidate in candidates
        ],
    }

    try:
        execute_result = await asyncio.to_thread(execute_function_sync, settings.mudbase_function_id, payload)
    except MudbaseApiError as exc:
        raise MudbaseFunctionError(f"Mudbase Function execute request failed ({exc.status_code}): {exc.message}") from exc

    execution_id = execute_result.get("executionId")
    if not execution_id:
        raise MudbaseFunctionError("Mudbase Function execute request returned no executionId")

    deadline = time.monotonic() + _POLL_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        try:
            status_result = await asyncio.to_thread(
                get_function_execution_sync, settings.mudbase_function_id, execution_id
            )
        except MudbaseApiError as exc:
            raise MudbaseFunctionError(f"Mudbase Function execution poll failed ({exc.status_code}): {exc.message}") from exc

        status = status_result.get("status")
        if status == "success":
            result = status_result.get("result") or {}
            citations = [
                AskCitation(document_id=citation.get("documentId") or "", title=citation.get("title") or "")
                for citation in result.get("citations", [])
            ]
            return RetrievalResult(
                context_block=str(result.get("contextBlock") or ""),
                citations=citations,
                used_count=int(result.get("usedCount") or 0),
            )
        if status in ("failed", "timeout"):
            error_message = status_result.get("error") or "unknown error"
            raise MudbaseFunctionError(f"Mudbase Function execution {status}: {error_message}")

        await asyncio.sleep(_POLL_INTERVAL_SECONDS)

    raise MudbaseFunctionError("Timed out waiting for the Mudbase Function execution to complete")
