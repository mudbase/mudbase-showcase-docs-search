package dev.mudbase.showcase.docssearch.domain;

/** One document's keyword-overlap score against a query - see {@code support.Retrieval}. */
public record ScoredDocument(DocumentRecord document, int score) {}
