"""Mirrors web/src/types/document.ts `SearchLogRecord`. `user_id`/`user_name`
are only ever populated with a real signed-in user's own ObjectId/name —
never a placeholder string, matching the reference app's own convention."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class SearchLogEntry(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str = Field(alias="_id")
    query_text: str = Field(alias="queryText")
    user_id: str | None = Field(default=None, alias="userId")
    user_name: str | None = Field(default=None, alias="userName")
    result_count: int = Field(default=0, alias="resultCount")
    created_at: datetime | None = Field(default=None, alias="createdAt")
