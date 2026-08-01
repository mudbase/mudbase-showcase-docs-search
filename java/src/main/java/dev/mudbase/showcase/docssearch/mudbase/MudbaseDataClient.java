package dev.mudbase.showcase.docssearch.mudbase;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.mudbase.showcase.docssearch.auth.AuthSession;
import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import dev.mudbase.showcase.docssearch.config.MudbaseClientFactory;
import dev.mudbase.sdk.ApiException;
import dev.mudbase.sdk.api.DataApi;
import dev.mudbase.sdk.model.DataResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import okhttp3.HttpUrl;
import okhttp3.Request;
import okhttp3.Response;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * Thin, typed-enough wrapper over the generated {@link DataApi} for this app's two collections
 * (documents, search_log). Every call needs the caller's own bearer token (a real signed-in
 * customer, or an anonymous guest) so Mudbase's own collection permissions are the real security
 * boundary; this app's own ownership check in {@link
 * dev.mudbase.showcase.docssearch.service.DocumentService} (authorId === current user id) is
 * defense-in-depth, not a substitute for it.
 *
 * <p><b>Access-token-expiry recovery.</b> Every method below runs through {@link #execute}, which
 * retries exactly once on a 401: it looks up the current request's {@code HttpSession} (via
 * {@link RequestContextHolder}, always available on a Spring MVC request thread) and asks {@link
 * SessionAuthService#recoverFromUnauthorized} to exchange the stored refresh token for a new
 * access token. If that succeeds, the exact same call is re-issued once with the new token; if
 * there is no session, no refresh token, or the refresh call itself fails, the original 401
 * propagates to {@link dev.mudbase.showcase.docssearch.web.GlobalExceptionHandler}, which owns the
 * terminal "session expired, please sign in again" behavior. Ported verbatim from the sibling
 * kanban/ecommerce/social showcases.
 */
@Component
public class MudbaseDataClient {

  private static final ObjectMapper MAPPER = new ObjectMapper();

  private final MudbaseClientFactory clientFactory;
  private final SessionAuthService sessionAuthService;

  public MudbaseDataClient(MudbaseClientFactory clientFactory, SessionAuthService sessionAuthService) {
    this.clientFactory = clientFactory;
    this.sessionAuthService = sessionAuthService;
  }

  public List<Map<String, Object>> list(
      String bearerToken, String collectionId, Map<String, Object> filter, String sort, int page, int limit) {
    return listPage(bearerToken, collectionId, filter, sort, page, limit).items();
  }

  public PageResult<Map<String, Object>> listPage(
      String bearerToken, String collectionId, Map<String, Object> filter, String sort, int page, int limit) {
    String filterJson = filter == null || filter.isEmpty() ? null : stringifyFilter(filter);
    return execute(bearerToken, (dataApi, token) -> rawList(token, collectionId, filterJson, sort, page, limit));
  }

  /**
   * Bypasses the generated {@code DataApi.listData}. Its Gson-generated {@code Pagination} model
   * hard-fails ({@code IllegalArgumentException}, not even the SDK's own checked {@code
   * ApiException}) the instant the real, live API response includes a {@code hasMore} field this
   * SDK version's OpenAPI spec never declared - the same finding the sibling kanban/ecommerce/
   * social Java ports already made and fixed against this same backend. Same "raw call over the
   * SDK's own shared OkHttpClient, same base path and bearer header, parsed leniently" pattern
   * reused here.
   */
  private PageResult<Map<String, Object>> rawList(
      String bearerToken, String collectionId, String filterJson, String sort, int page, int limit)
      throws ApiException {
    HttpUrl.Builder urlBuilder =
        HttpUrl.get(
                clientFactory.baseUrl()
                    + "/api/data/projects/"
                    + clientFactory.projectId()
                    + "/collections/"
                    + collectionId
                    + "/data")
            .newBuilder()
            .addQueryParameter("page", String.valueOf(page))
            .addQueryParameter("limit", String.valueOf(limit));
    if (sort != null && !sort.isBlank()) {
      urlBuilder.addQueryParameter("sort", sort);
    }
    if (filterJson != null && !filterJson.isBlank()) {
      urlBuilder.addQueryParameter("filter", filterJson);
    }
    Request.Builder requestBuilder = new Request.Builder().url(urlBuilder.build()).get();
    if (bearerToken != null && !bearerToken.isBlank()) {
      requestBuilder.header("Authorization", "Bearer " + bearerToken);
    }
    try (Response response = clientFactory.rawHttpClient().newCall(requestBuilder.build()).execute()) {
      String responseBody = response.body() != null ? response.body().string() : "";
      if (!response.isSuccessful()) {
        throw new ApiException(response.code(), "Mudbase list request failed", Map.of(), responseBody);
      }
      JsonNode root = MAPPER.readTree(responseBody.isBlank() ? "{}" : responseBody);
      List<Map<String, Object>> results = new ArrayList<>();
      JsonNode data = root.get("data");
      if (data != null && data.isArray()) {
        for (JsonNode item : data) {
          results.add(MAPPER.convertValue(item, new TypeReference<LinkedHashMap<String, Object>>() {}));
        }
      }
      JsonNode pagination = root.get("pagination");
      long total = pagination != null && pagination.hasNonNull("total") ? pagination.get("total").asLong() : results.size();
      boolean hasMore = pagination != null && pagination.hasNonNull("hasMore") && pagination.get("hasMore").asBoolean();
      int actualPage = pagination != null && pagination.hasNonNull("page") ? pagination.get("page").asInt() : page;
      return new PageResult<>(results, actualPage, limit, total, hasMore);
    } catch (IOException e) {
      throw new ApiException(502, "Could not reach Mudbase to list " + collectionId, Map.of(), null);
    }
  }

  public Map<String, Object> get(String bearerToken, String collectionId, String documentId) {
    return execute(
        bearerToken,
        (dataApi, token) -> {
          DataResponse response = dataApi.getData(clientFactory.projectId(), collectionId, documentId);
          return DocumentMapper.asMap(response.getData());
        });
  }

  public Map<String, Object> create(String bearerToken, String collectionId, Map<String, Object> body) {
    return execute(
        bearerToken,
        (dataApi, token) -> {
          DataResponse response = dataApi.createData(clientFactory.projectId(), collectionId, body);
          return DocumentMapper.asMap(response.getData());
        });
  }

  public Map<String, Object> update(
      String bearerToken, String collectionId, String documentId, Map<String, Object> body) {
    return execute(
        bearerToken,
        (dataApi, token) -> {
          DataResponse response = dataApi.updateData(clientFactory.projectId(), collectionId, documentId, body);
          return DocumentMapper.asMap(response.getData());
        });
  }

  public void delete(String bearerToken, String collectionId, String documentId) {
    execute(
        bearerToken,
        (dataApi, token) -> {
          dataApi.deleteData(clientFactory.projectId(), collectionId, documentId);
          return null;
        });
  }

  /**
   * Runs {@code call} against a {@link DataApi} built from {@code bearerToken}; on a 401,
   * attempts exactly one silent token refresh + retry before giving up. See class javadoc.
   */
  private <R> R execute(String bearerToken, DataApiCall<R> call) {
    try {
      return call.call(clientFactory.dataApi(bearerToken), bearerToken);
    } catch (ApiException e) {
      MudbaseApiException failure = MudbaseApiException.from(e);
      if (!failure.isUnauthorized()) {
        throw failure;
      }
      Optional<String> refreshedToken = attemptTokenRefresh(bearerToken);
      if (refreshedToken.isEmpty()) {
        throw failure;
      }
      try {
        return call.call(clientFactory.dataApi(refreshedToken.get()), refreshedToken.get());
      } catch (ApiException retryFailure) {
        throw MudbaseApiException.from(retryFailure);
      }
    }
  }

  private Optional<String> attemptTokenRefresh(String failedToken) {
    HttpSession session = currentHttpSession();
    if (session == null) {
      return Optional.empty();
    }
    return sessionAuthService.recoverFromUnauthorized(session, failedToken).map(AuthSession::getToken);
  }

  private HttpSession currentHttpSession() {
    if (!(RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attrs)) {
      return null;
    }
    return attrs.getRequest().getSession(false);
  }

  private static String stringifyFilter(Map<String, Object> value) {
    try {
      return MAPPER.writeValueAsString(value);
    } catch (Exception e) {
      throw new IllegalArgumentException("Could not serialize filter to JSON", e);
    }
  }

  @FunctionalInterface
  private interface DataApiCall<R> {
    R call(DataApi dataApi, String bearerToken) throws ApiException;
  }
}
