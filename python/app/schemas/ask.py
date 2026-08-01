"""Mirrors web/src/lib/ask-schema.ts — the contract this app's own Ask AI
flow uses internally between the retrieval-scoring step, the Mudbase
Function invocation, and the LLM completion step. There is no separate
`POST /api/ask` boundary in this server-rendered port (unlike the reference
Next.js app, whose route handler is a genuine network boundary between the
browser and this process) — the same validation still applies to the
question the visitor typed, and to the candidate documents this process
builds for itself before calling the Function.
"""

import re

from pydantic import BaseModel, Field, field_validator

_OBJECT_ID_RE = re.compile(r"^[0-9a-f]{24}$", re.IGNORECASE)
_MAX_QUESTION_LENGTH = 2000
_MAX_CANDIDATE_TITLE_LENGTH = 300
_MAX_CANDIDATE_CONTENT_LENGTH = 20_000
_MAX_CANDIDATE_TAGS_LENGTH = 500


class AskFormValues(BaseModel):
    question: str = Field(min_length=1, max_length=_MAX_QUESTION_LENGTH)

    @field_validator("question")
    @classmethod
    def _strip_question(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("Question is required")
        return stripped


class AskCandidate(BaseModel):
    document_id: str
    title: str = Field(min_length=1, max_length=_MAX_CANDIDATE_TITLE_LENGTH)
    content: str = Field(min_length=1, max_length=_MAX_CANDIDATE_CONTENT_LENGTH)
    tags: str | None = Field(default=None, max_length=_MAX_CANDIDATE_TAGS_LENGTH)

    @field_validator("document_id")
    @classmethod
    def _validate_object_id(cls, value: str) -> str:
        if not _OBJECT_ID_RE.match(value):
            raise ValueError("document_id must be a 24-character hex ObjectId")
        return value


class AskCitation(BaseModel):
    document_id: str
    title: str
