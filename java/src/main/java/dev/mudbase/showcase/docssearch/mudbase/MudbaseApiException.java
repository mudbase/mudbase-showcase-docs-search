package dev.mudbase.showcase.docssearch.mudbase;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.mudbase.sdk.ApiException;

/**
 * Unchecked wrapper around the SDK's checked {@link ApiException}, carrying the HTTP status and
 * a message extracted from Mudbase's standard error body ({@code {"error": "...", "code": "..."}}
 * - see the generated {@code Error} model) so callers get something displayable without having to
 * re-parse JSON at every call site. Ported verbatim from the sibling kanban/ecommerce/social
 * showcases.
 */
public class MudbaseApiException extends RuntimeException {

  private static final long serialVersionUID = 1L;
  private static final ObjectMapper MAPPER = new ObjectMapper();

  private final int statusCode;
  private final String errorCode;

  public MudbaseApiException(String message, int statusCode, String errorCode, Throwable cause) {
    super(message, cause);
    this.statusCode = statusCode;
    this.errorCode = errorCode;
  }

  public static MudbaseApiException from(ApiException e) {
    String body = e.getResponseBody();
    String message = null;
    String code = null;
    if (body != null && !body.isBlank()) {
      try {
        JsonNode node = MAPPER.readTree(body);
        if (node.hasNonNull("error")) {
          message = node.get("error").asText();
        }
        if (node.hasNonNull("code")) {
          code = node.get("code").asText();
        }
      } catch (Exception parseFailure) {
        // Body wasn't the expected JSON error shape - fall through to the generic message below.
      }
    }
    if (message == null || message.isBlank()) {
      message = "Mudbase request failed (" + e.getCode() + ")";
    }
    return new MudbaseApiException(message, e.getCode(), code, e);
  }

  public static MudbaseApiException fromRawBody(int statusCode, String body) {
    String message = null;
    String code = null;
    if (body != null && !body.isBlank()) {
      try {
        JsonNode node = MAPPER.readTree(body);
        if (node.hasNonNull("error")) {
          message = node.get("error").asText();
        }
        if (node.hasNonNull("code")) {
          code = node.get("code").asText();
        }
      } catch (Exception parseFailure) {
        // Not JSON - use the generic message below.
      }
    }
    if (message == null || message.isBlank()) {
      message = "Mudbase request failed (" + statusCode + ")";
    }
    return new MudbaseApiException(message, statusCode, code, null);
  }

  public int getStatusCode() {
    return statusCode;
  }

  public String getErrorCode() {
    return errorCode;
  }

  public boolean isUnauthorized() {
    return statusCode == 401;
  }

  public boolean isForbidden() {
    return statusCode == 403;
  }
}
