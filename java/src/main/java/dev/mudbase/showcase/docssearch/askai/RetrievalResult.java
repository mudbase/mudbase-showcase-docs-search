package dev.mudbase.showcase.docssearch.askai;

import java.util.List;

/** The deployed Mudbase Function's ({@code docsAskRetrieval}) execution result. */
public record RetrievalResult(String contextBlock, List<Citation> citations, int usedCount) {}
