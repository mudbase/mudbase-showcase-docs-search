"""FastAPI application factory. Run with:
    uvicorn app.main:app --reload
"""

import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware

from app.config import get_settings
from app.routers import ask, auth, documents, library

STATIC_DIR = Path(__file__).parent / "static"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title="Mudbase Showcase — Docs Search (Python)",
        description=(
            "Server-rendered FastAPI + Jinja2 reimplementation of the Mudbase showcase "
            "docs-search knowledge base, backed entirely by the real Mudbase Python SDK, "
            "with an Ask AI flow that invokes a real deployed Mudbase Function for "
            "retrieval ranking and this process's own server-side code for the grounded "
            "LLM completion call."
        ),
    )

    app.add_middleware(
        SessionMiddleware,
        secret_key=settings.session_secret_key,
        session_cookie=settings.session_cookie_name,
        https_only=settings.session_https_only,
        same_site="lax",
    )

    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

    app.include_router(library.router)
    app.include_router(documents.router)
    app.include_router(ask.router)
    app.include_router(auth.router)

    return app


app = create_app()
