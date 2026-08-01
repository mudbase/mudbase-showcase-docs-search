"""Auth flows: register (always the `customer` role — this app has only one
role), login, logout, and email-verification completion. This project
requires email verification (verified live against the real backend — see
plan/build-plan.md): registration returns 201 with no token; login 403s with
`EMAIL_VERIFICATION_REQUIRED` until the emailed link is followed. The shared
demo account (`docs.member.demo@gmail.com`) is already verified.
"""

import asyncio
from typing import Any

from app.mudbase_client import login_sync, logout_sync, register_with_role_sync, verify_email_sync

_ROLE = "customer"


async def register(
    email: str,
    password: str,
    first_name: str,
    last_name: str,
    agreed_to_terms: bool,
) -> dict[str, Any]:
    return await asyncio.to_thread(
        register_with_role_sync,
        _ROLE,
        email,
        password,
        first_name,
        last_name,
        agreed_to_terms,
    )


async def login(email: str, password: str) -> dict[str, Any]:
    return await asyncio.to_thread(login_sync, email, password)


async def logout(access_token: str) -> None:
    await asyncio.to_thread(logout_sync, access_token)


async def verify_email(token: str) -> dict[str, Any]:
    return await asyncio.to_thread(verify_email_sync, token)
