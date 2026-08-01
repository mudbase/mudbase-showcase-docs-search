"""Per-request template context shared across every page: current user (if
any) and a one-shot flash message.
"""

from typing import Any

from fastapi import Request

from app.session import get_session_user, pop_flash


async def build_base_context(request: Request) -> dict[str, Any]:
    return {
        "current_user": get_session_user(request),
        "flash": pop_flash(request),
    }
