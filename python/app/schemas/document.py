"""Mirrors web/src/types/document.ts `DocumentRecord`. Field aliases match
the raw Mudbase document shape (camelCase, `_id`) so `Document.model_validate(doc)`
works directly off a `DataApi` response dict — no separate mapping layer."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

_MAX_TITLE_LENGTH = 200
_MAX_CONTENT_LENGTH = 50_000
_MAX_TAGS_LENGTH = 500


class Document(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    title: str
    content: str
    tags: str | None = None
    author_id: str = Field(alias="authorId")
    author_name: str = Field(alias="authorName")
    created_at: datetime | None = Field(default=None, alias="createdAt")
    updated_at: datetime | None = Field(default=None, alias="updatedAt")


class DocumentFormValues(BaseModel):
    """Validated shape of the document composer/editor. Mirrors the zod
    schema in web/src/components/documents/DocumentForm.tsx."""

    title: str = Field(min_length=1, max_length=_MAX_TITLE_LENGTH)
    content: str = Field(min_length=1, max_length=_MAX_CONTENT_LENGTH)
    tags: str = Field(default="", max_length=_MAX_TAGS_LENGTH)

    @field_validator("title")
    @classmethod
    def _strip_title(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Title is required")
        return stripped

    @field_validator("content")
    @classmethod
    def _strip_content(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Content is required")
        return stripped

    @field_validator("tags")
    @classmethod
    def _strip_tags(cls, value: str) -> str:
        return value.strip()
