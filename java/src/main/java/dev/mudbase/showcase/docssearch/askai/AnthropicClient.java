package dev.mudbase.showcase.docssearch.askai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.mudbase.showcase.docssearch.config.LlmProperties;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import org.springframework.stereotype.Component;

/**
 * The one place in this codebase that calls a third-party LLM API. {@link
 * LlmProperties#getApiKey()} is a server-only configuration value (never rendered into any
 * Thymeleaf template, never logged) - it is never sent to, or readable by, the browser, since
 * this app has no client JS runtime to leak it through in the first place.
 *
 * <p>See plan/build-plan.md "Ask AI architecture" for why this call happens here rather than
 * inside the Mudbase Function itself: the Function's {@code isolated-vm} sandbox has no network
 * primitives at all (no {@code fetch}, no {@code http}/{@code https} module - verified against
 * the actual runner source), so it cannot make an outbound HTTPS call to any LLM provider. The
 * Function still does real work (keyword-overlap retrieval ranking + grounded context assembly,
 * see {@link FunctionInvokeClient}) - this class only performs the completion call the sandbox is
 * structurally incapable of making itself.
 *
 * <p>No official Anthropic Java SDK is used here - this app already carries an OkHttp client
 * (transitively, via the Mudbase SDK) that is reused directly for a single, narrowly-scoped raw
 * HTTPS call, exactly mirroring the reference web app's use of {@code @anthropic-ai/sdk} in
 * {@code src/lib/server/llm.ts} but without adding a new dependency for one endpoint.
 */
@Component
public class AnthropicClient {

  private static final String API_URL = "https://api.anthropic.com/v1/messages";
  private static final String ANTHROPIC_VERSION = "2023-06-01";
  private static final int MAX_TOKENS = 1024;

  private static final String SYSTEM_PROMPT =
      "You are a support assistant for a documentation knowledge base. Answer the user's "
          + "question using ONLY the document excerpts provided below - never your own outside knowledge. If the "
          + "excerpts do not contain enough information to answer, say so plainly rather than guessing. Keep the "
          + "answer concise (a few sentences to a short paragraph). When you use a fact from an excerpt, mention "
          + "which document it came from by its title.";

  private static final ObjectMapper MAPPER = new ObjectMapper();

  private final LlmProperties properties;
  private final OkHttpClient httpClient;

  public AnthropicClient(LlmProperties properties) {
    this.properties = properties;
    this.httpClient = new OkHttpClient.Builder().build();
  }

  public String generateGroundedAnswer(String question, String contextBlock) {
    if (!properties.hasApiKey()) {
      throw new IllegalStateException(
          "ANTHROPIC_API_KEY is not configured. This is a server-only environment variable (see "
              + "java/README.md \"LLM setup\" and .env.example) - the developer running this app must supply "
              + "their own key.");
    }

    String userContent =
        contextBlock != null && !contextBlock.isBlank()
            ? "Question: " + question + "\n\nDocument excerpts:\n" + contextBlock
            : "Question: "
                + question
                + "\n\n(No document excerpts were retrieved - say you don't have enough information in the"
                + " knowledge base to answer.)";

    Map<String, Object> message = new LinkedHashMap<>();
    message.put("role", "user");
    message.put("content", userContent);

    Map<String, Object> body = new LinkedHashMap<>();
    body.put("model", properties.getModel());
    body.put("max_tokens", MAX_TOKENS);
    body.put("system", SYSTEM_PROMPT);
    body.put("messages", List.of(message));

    String requestJson;
    try {
      requestJson = MAPPER.writeValueAsString(body);
    } catch (Exception e) {
      throw new IllegalStateException("Could not serialize Anthropic request", e);
    }

    Request request =
        new Request.Builder()
            .url(API_URL)
            .header("x-api-key", properties.getApiKey())
            .header("anthropic-version", ANTHROPIC_VERSION)
            .header("content-type", "application/json")
            .post(RequestBody.create(requestJson, MediaType.parse("application/json")))
            .build();

    try (Response response = httpClient.newCall(request).execute()) {
      String responseBody = response.body() != null ? response.body().string() : "";
      if (!response.isSuccessful()) {
        JsonNode errorNode = safeParse(responseBody);
        String errorMessage = errorNode != null ? errorNode.path("error").path("message").asText(responseBody) : responseBody;
        throw new IllegalStateException("Anthropic API request failed (" + response.code() + "): " + errorMessage);
      }
      JsonNode root = MAPPER.readTree(responseBody.isBlank() ? "{}" : responseBody);
      JsonNode content = root.get("content");
      if (content != null && content.isArray()) {
        for (JsonNode block : content) {
          if ("text".equals(block.path("type").asText())) {
            return block.path("text").asText("");
          }
        }
      }
      String stopReason = root.path("stop_reason").asText("");
      if ("refusal".equals(stopReason)) {
        throw new IllegalStateException("The model declined to answer this question.");
      }
      throw new IllegalStateException("The model returned no text content");
    } catch (IOException e) {
      throw new IllegalStateException("Could not reach the Anthropic API", e);
    }
  }

  private static JsonNode safeParse(String body) {
    try {
      return MAPPER.readTree(body);
    } catch (Exception e) {
      return null;
    }
  }
}
