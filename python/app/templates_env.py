"""Shared Jinja2Templates instance + custom filters, importable by every
router without risking a circular import with main.py."""

from pathlib import Path

from fastapi.templating import Jinja2Templates

from app.utils import format_date, parse_tags, relative_time, snippet

TEMPLATES_DIR = Path(__file__).parent / "templates"

templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
templates.env.filters["date"] = format_date
templates.env.filters["relative_time"] = relative_time
templates.env.filters["tags"] = parse_tags
templates.env.filters["snippet"] = snippet
