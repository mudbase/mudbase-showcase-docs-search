"""Login / register / logout / verify-email. Mirrors web/src/app/login,
/register, /verify-email and web/src/hooks/useAuth.ts. Self-signup role is
always `customer` — there is no role selector, matching the reference app's
single-role register form. This project requires email verification
(verified live against the real backend): registration returns 201 with no
token; login 403s with `EMAIL_VERIFICATION_REQUIRED` until the emailed link
is followed.
"""

import logging
from typing import Annotated

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import ValidationError

from app.context import build_base_context
from app.mudbase_client import MudbaseApiError
from app.schemas.auth import LoginFormValues, RegisterFormValues
from app.services import auth_service
from app.session import clear_session, get_session_user, get_valid_access_token, set_flash, store_session
from app.templates_env import templates
from app.utils import field_errors

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/login", response_class=HTMLResponse, response_model=None)
async def login_page(request: Request, next: str | None = None) -> HTMLResponse | RedirectResponse:
    if get_session_user(request) is not None:
        return RedirectResponse(next or "/", status_code=303)
    context = await build_base_context(request)
    context.update({"errors": {}, "form_error": None, "next": next})
    return templates.TemplateResponse(request=request, name="login.html", context=context)


@router.post("/login", response_class=HTMLResponse, response_model=None)
async def login_submit(
    request: Request,
    email: Annotated[str, Form()],
    password: Annotated[str, Form()],
    next: Annotated[str | None, Form()] = None,
) -> HTMLResponse | RedirectResponse:
    try:
        values = LoginFormValues(email=email, password=password)
    except ValidationError as exc:
        context = await build_base_context(request)
        context.update({"errors": field_errors(exc), "form_error": None, "next": next})
        return templates.TemplateResponse(request=request, name="login.html", context=context, status_code=422)

    try:
        result = await auth_service.login(values.email, values.password)
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update({"errors": {}, "form_error": exc.message, "next": next})
        return templates.TemplateResponse(request=request, name="login.html", context=context, status_code=401)

    user = result.get("user") or {}
    store_session(
        request,
        user=user,
        token=result["token"],
        refresh_token=result["refreshToken"],
        expires_in=result.get("expiresIn"),
    )
    set_flash(request, "Welcome back!", "success")
    return RedirectResponse(next or "/", status_code=303)


@router.get("/register", response_class=HTMLResponse, response_model=None)
async def register_page(request: Request) -> HTMLResponse | RedirectResponse:
    if get_session_user(request) is not None:
        return RedirectResponse("/", status_code=303)
    context = await build_base_context(request)
    context.update({"errors": {}, "form_error": None})
    return templates.TemplateResponse(request=request, name="register.html", context=context)


@router.post("/register", response_class=HTMLResponse, response_model=None)
async def register_submit(
    request: Request,
    first_name: Annotated[str, Form()],
    last_name: Annotated[str, Form()],
    email: Annotated[str, Form()],
    password: Annotated[str, Form()],
    agreed_to_terms: Annotated[bool, Form()] = False,
) -> HTMLResponse | RedirectResponse:
    try:
        values = RegisterFormValues(
            first_name=first_name,
            last_name=last_name,
            email=email,
            password=password,
            agreed_to_terms=agreed_to_terms,
        )
    except ValidationError as exc:
        context = await build_base_context(request)
        context.update({"errors": field_errors(exc), "form_error": None})
        return templates.TemplateResponse(request=request, name="register.html", context=context, status_code=422)

    try:
        result = await auth_service.register(
            values.email, values.password, values.first_name, values.last_name, values.agreed_to_terms
        )
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update({"errors": {}, "form_error": exc.message})
        return templates.TemplateResponse(request=request, name="register.html", context=context, status_code=400)

    token = result.get("token")
    if not token:
        # This project requires email verification (verified live) —
        # register() never returns a session token.
        set_flash(
            request,
            result.get("message") or "Check your inbox for a verification link, then sign in.",
            "info",
        )
        return RedirectResponse("/login", status_code=303)

    store_session(
        request,
        user=result.get("user") or {},
        token=token,
        refresh_token=result["refreshToken"],
        expires_in=result.get("expiresIn"),
    )
    set_flash(request, "Welcome to the knowledge base!", "success")
    return RedirectResponse("/", status_code=303)


@router.get("/verify-email", response_class=HTMLResponse, response_model=None)
async def verify_email_page(request: Request, token: str | None = None) -> HTMLResponse:
    """Completes the emailed verification link. Runs the verification as a
    side effect of the GET itself (the token is a single-use secret from the
    email, and this is a server-rendered app with no client-side JS to make
    the follow-up POST from a separate confirmation page) — same pattern the
    reference SPA's /verify-email page uses, just executed server-side here."""
    context = await build_base_context(request)
    if not token:
        context.update({"success": False, "message": "This verification link is missing its token."})
        return templates.TemplateResponse(request=request, name="verify_email.html", context=context)

    try:
        result = await auth_service.verify_email(token)
        context.update(
            {"success": True, "message": result.get("message") or "Your email is verified — you can sign in now."}
        )
    except MudbaseApiError as exc:
        context.update({"success": False, "message": exc.message})
    return templates.TemplateResponse(request=request, name="verify_email.html", context=context)


@router.post("/logout", response_model=None)
async def logout_submit(request: Request) -> RedirectResponse:
    token = await get_valid_access_token(request)
    if token:
        try:
            await auth_service.logout(token)
        except MudbaseApiError as exc:
            # Session is cleared locally regardless of the remote logout outcome (an
            # already-expired token, for instance, shouldn't strand the user signed in).
            logger.warning("Remote logout failed for a local session teardown: %s", exc.message)
    clear_session(request)
    return RedirectResponse("/", status_code=303)
