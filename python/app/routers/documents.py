"""Document detail, create, edit, delete. Mirrors web/src/app/documents/[id]/page.tsx,
web/src/app/documents/new/page.tsx and web/src/app/documents/[id]/edit/page.tsx.

Ownership (`user.id == document.authorId`) gates edit/delete in the UI here
exactly like the reference app — but since this is a server-rendered app
where the form POST itself performs the mutation (rather than the browser
calling Mudbase directly with the signed-in user's own JWT), every
mutating route re-checks ownership server-side before calling the service
layer. The reference SPA relies on Mudbase's own collection permission rules
to reject an unauthorized PATCH/DELETE at the API layer; this port adds the
same check here too, defense-in-depth, before ever sending the request.
"""

from typing import Annotated

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import ValidationError

from app.context import build_base_context
from app.mudbase_client import MudbaseApiError
from app.schemas.document import DocumentFormValues
from app.services import documents as documents_service
from app.session import ensure_anonymous_session, get_session_user, get_valid_access_token, set_flash
from app.templates_env import templates
from app.utils import field_errors

router = APIRouter()


@router.get("/documents/new", response_class=HTMLResponse, response_model=None)
async def new_document_page(request: Request) -> HTMLResponse | RedirectResponse:
    user = get_session_user(request)
    if user is None or not user.is_customer:
        return RedirectResponse("/login?next=/documents/new", status_code=303)
    context = await build_base_context(request)
    context.update({"errors": {}, "form_error": None, "values": None})
    return templates.TemplateResponse(request=request, name="document_new.html", context=context)


@router.post("/documents", response_model=None)
async def create_document_submit(
    request: Request,
    title: Annotated[str, Form()],
    content: Annotated[str, Form()],
    tags: Annotated[str, Form()] = "",
) -> HTMLResponse | RedirectResponse:
    user = get_session_user(request)
    if user is None or not user.is_customer:
        return RedirectResponse("/login?next=/documents/new", status_code=303)

    token = await get_valid_access_token(request)
    if not token:
        return RedirectResponse("/login?next=/documents/new", status_code=303)

    submitted = {"title": title, "content": content, "tags": tags}
    try:
        values = DocumentFormValues(title=title, content=content, tags=tags)
    except ValidationError as exc:
        context = await build_base_context(request)
        context.update({"errors": field_errors(exc), "form_error": None, "values": submitted})
        return templates.TemplateResponse(request=request, name="document_new.html", context=context, status_code=422)

    try:
        created = await documents_service.create_document(
            values, author_id=user.id, author_name=user.display_name, access_token=token
        )
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update({"errors": {}, "form_error": exc.message, "values": submitted})
        return templates.TemplateResponse(request=request, name="document_new.html", context=context, status_code=400)

    set_flash(request, "Document published.", "success")
    return RedirectResponse(f"/documents/{created.id}", status_code=303)


@router.get("/documents/{document_id}", response_class=HTMLResponse, response_model=None)
async def document_detail_page(request: Request, document_id: str) -> HTMLResponse:
    await ensure_anonymous_session(request)
    token = await get_valid_access_token(request)
    user = get_session_user(request)

    document = await documents_service.get_document(document_id, access_token=token)

    is_owner = bool(user and document and user.id == document.author_id)

    context = await build_base_context(request)
    context.update({"document": document, "is_owner": is_owner})
    status_code = 200 if document is not None else 404
    return templates.TemplateResponse(request=request, name="document_detail.html", context=context, status_code=status_code)


@router.get("/documents/{document_id}/edit", response_class=HTMLResponse, response_model=None)
async def edit_document_page(request: Request, document_id: str) -> HTMLResponse | RedirectResponse:
    user = get_session_user(request)
    if user is None:
        return RedirectResponse(f"/login?next=/documents/{document_id}/edit", status_code=303)

    token = await get_valid_access_token(request)
    document = await documents_service.get_document(document_id, access_token=token)

    if document is None:
        context = await build_base_context(request)
        context.update({"not_found": True})
        return templates.TemplateResponse(request=request, name="document_edit.html", context=context, status_code=404)

    if document.author_id != user.id:
        context = await build_base_context(request)
        context.update({"not_found": False, "forbidden": True})
        return templates.TemplateResponse(request=request, name="document_edit.html", context=context, status_code=403)

    context = await build_base_context(request)
    context.update(
        {
            "not_found": False,
            "forbidden": False,
            "document": document,
            "errors": {},
            "form_error": None,
            "values": None,
        }
    )
    return templates.TemplateResponse(request=request, name="document_edit.html", context=context)


@router.post("/documents/{document_id}/edit", response_model=None)
async def update_document_submit(
    request: Request,
    document_id: str,
    title: Annotated[str, Form()],
    content: Annotated[str, Form()],
    tags: Annotated[str, Form()] = "",
) -> HTMLResponse | RedirectResponse:
    user = get_session_user(request)
    if user is None:
        return RedirectResponse(f"/login?next=/documents/{document_id}/edit", status_code=303)

    token = await get_valid_access_token(request)
    document = await documents_service.get_document(document_id, access_token=token)

    if document is None:
        context = await build_base_context(request)
        context.update({"not_found": True})
        return templates.TemplateResponse(request=request, name="document_edit.html", context=context, status_code=404)

    if document.author_id != user.id or not token:
        context = await build_base_context(request)
        context.update({"not_found": False, "forbidden": True})
        return templates.TemplateResponse(request=request, name="document_edit.html", context=context, status_code=403)

    submitted = {"title": title, "content": content, "tags": tags}
    try:
        values = DocumentFormValues(title=title, content=content, tags=tags)
    except ValidationError as exc:
        context = await build_base_context(request)
        context.update(
            {
                "not_found": False,
                "forbidden": False,
                "document": document,
                "errors": field_errors(exc),
                "form_error": None,
                "values": submitted,
            }
        )
        return templates.TemplateResponse(request=request, name="document_edit.html", context=context, status_code=422)

    try:
        updated = await documents_service.update_document(document_id, values, access_token=token)
    except MudbaseApiError as exc:
        context = await build_base_context(request)
        context.update(
            {
                "not_found": False,
                "forbidden": False,
                "document": document,
                "errors": {},
                "form_error": exc.message,
                "values": submitted,
            }
        )
        return templates.TemplateResponse(request=request, name="document_edit.html", context=context, status_code=400)

    set_flash(request, "Document updated.", "success")
    return RedirectResponse(f"/documents/{updated.id}", status_code=303)


@router.post("/documents/{document_id}/delete", response_model=None)
async def delete_document_submit(request: Request, document_id: str) -> RedirectResponse:
    user = get_session_user(request)
    if user is None:
        return RedirectResponse(f"/login?next=/documents/{document_id}", status_code=303)

    token = await get_valid_access_token(request)
    document = await documents_service.get_document(document_id, access_token=token)

    if document is None:
        return RedirectResponse("/", status_code=303)

    if document.author_id != user.id or not token:
        set_flash(request, "You can only delete documents you authored.", "error")
        return RedirectResponse(f"/documents/{document_id}", status_code=303)

    try:
        await documents_service.delete_document(document_id, access_token=token)
    except MudbaseApiError as exc:
        set_flash(request, f"Couldn't delete that document: {exc.message}", "error")
        return RedirectResponse(f"/documents/{document_id}", status_code=303)

    set_flash(request, "Document deleted.", "success")
    return RedirectResponse("/", status_code=303)
