package dev.mudbase.showcase.docssearch.service;

import dev.mudbase.showcase.docssearch.askai.AnthropicClient;
import dev.mudbase.showcase.docssearch.askai.FunctionInvokeClient;
import dev.mudbase.showcase.docssearch.askai.RetrievalResult;
import dev.mudbase.showcase.docssearch.domain.DocumentRecord;
import dev.mudbase.showcase.docssearch.domain.ScoredDocument;
import dev.mudbase.showcase.docssearch.support.Retrieval;
import jakarta.servlet.http.HttpSession;
import java.util.List;
import org.springframework.stereotype.Service;

/**
 * Orchestrates the full Ask AI request/response flow - see plan/build-plan.md "Ask AI
 * architecture" for the two verified platform constraints that shape this design (a project
 * end-user JWT can never invoke a Function; a Function's sandbox has zero network access), and
 * why the result is: keyword scoring here in this app -> real Mudbase Function does
 * retrieval-ranking -> this service makes the one LLM completion call, since it is itself
 * server-side code (this app IS the "smallest server-side surface" the reference web app's
 * {@code POST /api/ask} route occupies - there is no separate client/server split in a
 * Thymeleaf-rendered app).
 *
 * <p>Full request flow, mirroring the reference web app's {@code AskAIPanel.tsx} +
 * {@code POST /api/ask} exactly:
 *
 * <ol>
 *   <li>Score every document in the library by keyword overlap ({@link Retrieval#scoreDocuments}).
 *   <li>If nothing scores above zero, log the search with {@code resultCount: 0} and stop - never
 *       call the Function or the LLM for a query with no plausible match.
 *   <li>Otherwise take the top 5 candidates ({@link Retrieval#topCandidates}) and invoke the
 *       deployed {@code docsAskRetrieval} Function ({@link FunctionInvokeClient}) for
 *       retrieval-ranking and grounded context assembly.
 *   <li>Pass the Function's {@code contextBlock} to {@link AnthropicClient} for the one grounded
 *       completion call.
 *   <li>Log the search with the real citation count and return the answer.
 * </ol>
 */
@Service
public class AskAiService {

  private static final int MAX_CANDIDATES = 5;

  private final DocumentService documentService;
  private final SearchLogService searchLogService;
  private final FunctionInvokeClient functionInvokeClient;
  private final AnthropicClient anthropicClient;

  public AskAiService(
      DocumentService documentService,
      SearchLogService searchLogService,
      FunctionInvokeClient functionInvokeClient,
      AnthropicClient anthropicClient) {
    this.documentService = documentService;
    this.searchLogService = searchLogService;
    this.functionInvokeClient = functionInvokeClient;
    this.anthropicClient = anthropicClient;
  }

  public AskAiResult ask(HttpSession session, String question) {
    List<DocumentRecord> documents = documentService.listAll(session);
    List<ScoredDocument> scored = Retrieval.scoreDocuments(documents, question);

    if (scored.isEmpty()) {
      searchLogService.log(session, question, 0);
      return AskAiResult.noMatch();
    }

    List<Retrieval.AskCandidate> candidates = Retrieval.topCandidates(scored, MAX_CANDIDATES);
    RetrievalResult retrieval = functionInvokeClient.invoke(question, candidates);

    if (retrieval.usedCount() == 0) {
      searchLogService.log(session, question, 0);
      return AskAiResult.answered(
          "I couldn't find anything in the knowledge base closely related to that question. Try rephrasing, or"
              + " add a document that covers it.",
          List.of());
    }

    String answer = anthropicClient.generateGroundedAnswer(question, retrieval.contextBlock());
    searchLogService.log(session, question, retrieval.citations().size());
    return AskAiResult.answered(answer, retrieval.citations());
  }
}
