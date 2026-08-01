"""Client-side keyword retrieval, ported directly from web/src/lib/retrieval.ts
and the `tokenizeQuery`/`countOccurrences` helpers in web/src/lib/utils.ts.
In the reference SPA this scoring runs in the browser (it already holds the
full document list rendered on the page); in this server-rendered port it
runs here, in the same request handler that renders the /ask page, using the
document list this process just fetched from Mudbase — same algorithm,
different execution site, identical output.
"""

import re
from dataclasses import dataclass

from app.schemas.ask import AskCandidate
from app.schemas.document import Document

_TOKEN_SPLIT_RE = re.compile(r"[^a-z0-9]+")
_MIN_TOKEN_LENGTH = 2
_MAX_CANDIDATE_CONTENT_CHARS = 4000


def tokenize_query(text: str) -> list[str]:
    """Splits free text into lowercase alphanumeric tokens of length > 2,
    deduplicated, order preserved."""
    tokens = [t for t in _TOKEN_SPLIT_RE.split(text.lower()) if len(t) > _MIN_TOKEN_LENGTH]
    return list(dict.fromkeys(tokens))


def count_occurrences(text: str, term: str) -> int:
    """Case-insensitive substring count of `term` inside `text`."""
    if not term:
        return 0
    haystack = text.lower()
    needle = term.lower()
    count = 0
    index = haystack.find(needle)
    while index != -1:
        count += 1
        index = haystack.find(needle, index + len(needle))
    return count


@dataclass(frozen=True)
class ScoredDocument:
    document: Document
    score: int


def score_documents(documents: list[Document], query: str) -> list[ScoredDocument]:
    """Scores each document by counting query-term occurrences across title
    (weight 3), tags (weight 2), and content (weight 1). No vector DB, no
    external search service — simple substring matching."""
    terms = tokenize_query(query)
    if not terms:
        return []

    scored: list[ScoredDocument] = []
    for document in documents:
        score = 0
        for term in terms:
            score += count_occurrences(document.title, term) * 3
            score += count_occurrences(document.tags or "", term) * 2
            score += count_occurrences(document.content, term)
        if score > 0:
            scored.append(ScoredDocument(document=document, score=score))

    return sorted(scored, key=lambda entry: entry.score, reverse=True)


def matches_search_term(document: Document, term: str) -> bool:
    """Matches the library page's plain-text search box: substring match
    across title+content+tags."""
    stripped = term.strip()
    if not stripped:
        return True
    needle = stripped.lower()
    return (
        needle in document.title.lower()
        or needle in document.content.lower()
        or needle in (document.tags or "").lower()
    )


def top_candidates(scored: list[ScoredDocument], limit: int = 5) -> list[AskCandidate]:
    """Top-N candidates for the Ask AI request payload, with content
    truncated to bound payload size."""
    candidates: list[AskCandidate] = []
    for entry in scored[:limit]:
        document = entry.document
        candidates.append(
            AskCandidate(
                document_id=document.id,
                title=document.title,
                content=document.content[:_MAX_CANDIDATE_CONTENT_CHARS],
                tags=document.tags or None,
            )
        )
    return candidates
