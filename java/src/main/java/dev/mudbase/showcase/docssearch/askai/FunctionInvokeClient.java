package dev.mudbase.showcase.docssearch.askai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.mudbase.showcase.docssearch.config.MudbaseClientFactory;
import dev.mudbase.showcase.docssearch.config.MudbaseProperties;
import dev.mudbase.showcase.docssearch.support.Retrieval;
import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import okhttp3.MediaType;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import org.springframework.stereotype.Component;

/**
 * Invokes the deployed Mudbase Function ({@code docsAskRetrieval}, id {@code
 * 6a6d431ef09e238c3e62b2f4}) that ranks candidate documents by keyword overlap and assembles a
 * grounded context block. This is a server-only client: {@link MudbaseProperties#getFunctionsApiKey()}
 * is an org-scoped {@code ak_} API key with {@code functions} permission, created specifically
 * for this purpose - see plan/build-plan.md "Ask AI architecture" for why. Short version: the
 * signed-in customer JWT this app otherwise uses can only ever satisfy {@code
 * rbacCheck("functions","read")}, never {@code "create")}, which the {@code /execute} route
 * requires. This key must never be sent to a browser - it only ever leaves this process as an
 * outbound request to cloud.mudbase.dev, exactly mirroring the reference web app's
 * server-only {@code src/lib/server/functionInvoke.ts}.
 *
 * <p>Ported logic-for-logic from that TypeScript module: POST {@code .../execute} with {@code
 * {payload: {question, candidates}}}, get back {@code {executionId, status: "queued"}}, then poll
 * {@code GET .../executions/:executionId} every 600ms (20s timeout) until {@code status} is
 * {@code success}/{@code failed}/{@code timeout}.
 */
@Component
public class FunctionInvokeClient {

  private static final ObjectMapper MAPPER = new ObjectMapper();
  private static final long POLL_INTERVAL_MS = 600;
  private static final long POLL_TIMEOUT_MS = 20_000;
  private static final int MAX_RATE_LIMIT_RETRIES = 3;
  private static final long RATE_LIMIT_BACKOFF_MS = 2_000;

  private final MudbaseClientFactory clientFactory;
  private final MudbaseProperties properties;

  public FunctionInvokeClient(MudbaseClientFactory clientFactory, MudbaseProperties properties) {
    this.clientFactory = clientFactory;
    this.properties = properties;
  }

  public RetrievalResult invoke(String question, List<Retrieval.AskCandidate> candidates) {
    Map<String, Object> payload = new LinkedHashMap<>();
    payload.put("question", question);
    payload.put("candidates", candidates);
    Map<String, Object> requestBody = Map.of("payload", payload);

    String requestJson;
    try {
      requestJson = MAPPER.writeValueAsString(requestBody);
    } catch (Exception e) {
      throw new IllegalStateException("Could not serialize Function execute request", e);
    }

    String executeUrl =
        clientFactory.baseUrl()
            + "/api/functions/projects/"
            + properties.getProjectId()
            + "/functions/"
            + properties.getFunctionId()
            + "/execute";
    Request executeRequest =
        new Request.Builder()
            .url(executeUrl)
            .header("X-API-Key", properties.getFunctionsApiKey())
            .post(RequestBody.create(requestJson, MediaType.parse("application/json")))
            .build();

    JsonNode executeBody = executeWithRateLimitRetry(executeRequest, "Function execute");
    JsonNode executeData = executeBody.get("data");
    if (!executeBody.path("success").asBoolean(false) || executeData == null) {
      throw new IllegalStateException(
          "Mudbase Function execute request failed: " + executeBody.path("error").asText("unknown error"));
    }
    String executionId = executeData.path("executionId").asText(null);
    if (executionId == null || executionId.isBlank()) {
      throw new IllegalStateException("Mudbase Function execute response carried no executionId");
    }

    String pollUrl =
        clientFactory.baseUrl()
            + "/api/functions/projects/"
            + properties.getProjectId()
            + "/functions/"
            + properties.getFunctionId()
            + "/executions/"
            + executionId;

    long deadline = System.currentTimeMillis() + POLL_TIMEOUT_MS;
    while (System.currentTimeMillis() < deadline) {
      Request pollRequest = new Request.Builder().url(pollUrl).header("X-API-Key", properties.getFunctionsApiKey()).get().build();
      JsonNode pollBody = executeWithRateLimitRetry(pollRequest, "Function execution poll");
      JsonNode pollData = pollBody.get("data");
      if (!pollBody.path("success").asBoolean(false) || pollData == null) {
        throw new IllegalStateException("Mudbase Function execution poll failed: " + pollBody.path("error").asText("unknown error"));
      }
      String status = pollData.path("status").asText("");
      if ("success".equals(status)) {
        JsonNode result = pollData.get("result");
        if (result == null) {
          throw new IllegalStateException("Function execution succeeded but returned no result");
        }
        return parseResult(result);
      }
      if ("failed".equals(status) || "timeout".equals(status)) {
        throw new IllegalStateException("Mudbase Function execution " + status + ": " + pollData.path("error").asText("unknown error"));
      }
      sleep(POLL_INTERVAL_MS);
    }
    throw new IllegalStateException("Timed out waiting for the Mudbase Function execution to complete");
  }

  private RetrievalResult parseResult(JsonNode result) {
    String contextBlock = result.path("contextBlock").asText("");
    int usedCount = result.path("usedCount").asInt(0);
    List<Citation> citations = new ArrayList<>();
    JsonNode citationsNode = result.get("citations");
    if (citationsNode != null && citationsNode.isArray()) {
      for (JsonNode citation : citationsNode) {
        citations.add(new Citation(citation.path("documentId").asText(""), citation.path("title").asText(""), citation.path("score").asInt(0)));
      }
    }
    return new RetrievalResult(contextBlock, citations, usedCount);
  }

  /**
   * Retries exactly {@link #MAX_RATE_LIMIT_RETRIES} times, with a fixed backoff sleep, on a 429
   * response - a bounded, synchronous wait rather than surfacing a transient rate limit as a hard
   * failure, since nothing outside this process would ever resume a retry for us.
   */
  private JsonNode executeWithRateLimitRetry(Request request, String what) {
    RuntimeException lastFailure = null;
    for (int attempt = 0; attempt <= MAX_RATE_LIMIT_RETRIES; attempt++) {
      try (Response response = clientFactory.rawHttpClient().newCall(request).execute()) {
        String bodyText = response.body() != null ? response.body().string() : "";
        if (response.code() == 429 && attempt < MAX_RATE_LIMIT_RETRIES) {
          sleep(RATE_LIMIT_BACKOFF_MS * (attempt + 1));
          continue;
        }
        if (!response.isSuccessful()) {
          throw new IllegalStateException(what + " failed (" + response.code() + "): " + bodyText);
        }
        return MAPPER.readTree(bodyText.isBlank() ? "{}" : bodyText);
      } catch (IOException e) {
        lastFailure = new IllegalStateException("Could not reach Mudbase to perform " + what, e);
      }
    }
    throw lastFailure != null ? lastFailure : new IllegalStateException(what + " failed after rate-limit retries");
  }

  private static void sleep(long millis) {
    try {
      Thread.sleep(millis);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new IllegalStateException("Interrupted while waiting on the Mudbase Function", e);
    }
  }
}
