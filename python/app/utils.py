"""Small formatting/parsing helpers. Mirrors web/src/lib/utils.ts, trimmed to
what this app needs, plus the ValidationError -> field-error-dict helper
shared by every form-posting router (mirrors the private `_field_errors`
helper duplicated across the sibling social port's routers — centralized
here instead since three routers in this app need it: auth, documents, ask).
"""

from datetime import datetime

from pydantic import ValidationError


def format_date(value: datetime | str | None) -> str:
    """Formats an ISO timestamp (or already-parsed datetime) for display."""
    if value is None:
        return ""
    parsed: datetime
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
    else:
        parsed = value
    return parsed.strftime("%b %-d, %Y, %-I:%M %p")


def relative_time(value: datetime | str | None) -> str:
    """A short "2h ago"-style label, falling back to `format_date` for
    anything older than a week (where a relative label stops being useful)."""
    if value is None:
        return ""
    parsed: datetime
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
    else:
        parsed = value

    now = datetime.now(parsed.tzinfo) if parsed.tzinfo else datetime.now()
    delta_seconds = (now - parsed).total_seconds()
    if delta_seconds < 60:
        return "just now"
    if delta_seconds < 3600:
        minutes = int(delta_seconds // 60)
        return f"{minutes}m ago"
    if delta_seconds < 86400:
        hours = int(delta_seconds // 3600)
        return f"{hours}h ago"
    if delta_seconds < 604800:
        days = int(delta_seconds // 86400)
        return f"{days}d ago"
    return format_date(parsed)


def parse_tags(tags: str | None) -> list[str]:
    """Parses the documents.tags field (comma-separated string) into a clean list."""
    if not tags:
        return []
    return [t.strip() for t in tags.split(",") if t.strip()]


def snippet(text: str, max_length: int = 160) -> str:
    """Builds a short plain-text preview from document content, for library-card cards."""
    collapsed = " ".join(text.strip().split())
    if len(collapsed) <= max_length:
        return collapsed
    return collapsed[:max_length].rstrip() + "…"


def field_errors(exc: ValidationError) -> dict[str, str]:
    errors: dict[str, str] = {}
    for error in exc.errors():
        field = str(error["loc"][0]) if error["loc"] else "form"
        errors[field] = str(error["msg"])
    return errors
