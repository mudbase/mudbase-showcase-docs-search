"""Environment configuration.

Mirrors web/src/lib/config.ts and the sibling mudbase-showcase-social/python
port's app/config.py: fail fast at startup if a required collection/project
ID is missing, rather than surfacing a confusing error deep inside a request
handler later.

`anthropic_api_key` is deliberately NOT required at startup — see
app/services/llm.py and plan/build-plan.md "Ask AI architecture": the
reference web app's own build/test environment had no real Anthropic key
available either, and it documented that gap honestly rather than blocking
the rest of the app. Every other Ask AI wiring (retrieval scoring, the real
deployed Mudbase Function, search logging) works with no LLM key at all; only
the final completion call needs one, and it fails there with a clear error
instead of at process startup.
"""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    mudbase_url: str = Field(default="https://cloud.mudbase.dev", alias="MUDBASE_URL")
    mudbase_project_id: str = Field(alias="MUDBASE_PROJECT_ID")
    documents_collection_id: str = Field(alias="DOCUMENTS_COLLECTION_ID")
    search_log_collection_id: str = Field(alias="SEARCH_LOG_COLLECTION_ID")

    # Server-only: Mudbase Function invocation (retrieval ranking). See
    # app/services/function_invoke.py and plan/build-plan.md for exactly why
    # an org-scoped ak_ API key is required here instead of the signed-in
    # user's own JWT (a project end-user's org role can never satisfy the
    # /execute route's rbacCheck("functions","create")).
    mudbase_function_id: str = Field(alias="MUDBASE_FUNCTION_ID")
    mudbase_functions_api_key: str = Field(alias="MUDBASE_FUNCTIONS_API_KEY")

    # Server-only: LLM provider (Anthropic Claude). Optional — see module
    # docstring above.
    anthropic_api_key: str = Field(default="", alias="ANTHROPIC_API_KEY")
    llm_model: str = Field(default="claude-opus-5", alias="LLM_MODEL")

    session_secret_key: str = Field(alias="SESSION_SECRET_KEY")
    session_cookie_name: str = Field(default="mudbase_showcase_docs_search_session", alias="SESSION_COOKIE_NAME")
    session_https_only: bool = Field(default=False, alias="SESSION_HTTPS_ONLY")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached so env parsing/validation happens once per process, not per request."""
    return Settings()  # type: ignore[call-arg]  # values come from the environment/.env file
