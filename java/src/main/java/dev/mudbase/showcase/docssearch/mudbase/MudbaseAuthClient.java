package dev.mudbase.showcase.docssearch.mudbase;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.mudbase.showcase.docssearch.config.MudbaseClientFactory;
import dev.mudbase.sdk.ApiException;
import dev.mudbase.sdk.api.AuthenticationApi;
import dev.mudbase.sdk.model.CreateAnonymousSession200Response;
import dev.mudbase.sdk.model.CreateAnonymousSessionRequest;
import dev.mudbase.sdk.model.RefreshToken200Response;
import dev.mudbase.sdk.model.RefreshTokenRequest;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import org.springframework.stereotype.Component;

/**
 * Auth calls against a provisioned Mudbase project: register (this project's single default
 * "customer" role), login, logout, and the anonymous guest session used for pre-login library
 * browsing and search - see plan/build-plan.md "Auth model".
 *
 * <p><b>Why registration bypasses the generated SDK method.</b> {@code
 * MultiRoleFeatureApi.registerWithRole} posts a {@code RegisterWithRoleRequest} that only has
 * {@code email}/{@code password}/{@code firstName}/{@code lastName}/{@code projectId} - the live
 * endpoint's validator additionally requires {@code agreedToTerms} (a direct API call without it
 * is rejected - confirmed by the reference Next.js app's own client, {@code src/lib/mudbase.ts}).
 * The generated request model has no field for it, and the generated method's return type is
 * {@code void} (the response body isn't modeled for this endpoint either). Rather than force a
 * mismatched typed call, this one endpoint is invoked directly over the SDK's own shared OkHttp
 * client and base path, with a hand-written response shape - the exact same fix the sibling
 * {@code mudbase-showcase-ecommerce/java} port already found and applied against this same
 * backend, reused here rather than rediscovered.
 *
 * <p><b>Why login also bypasses the generated SDK method.</b> {@code
 * AuthenticationApi.loginLocalUser} deserializes its response with the generated {@code
 * LoginLocalUser200ResponseUser} model via Gson, which hard-fails with an {@code
 * IllegalArgumentException} the instant the response JSON contains any property the model doesn't
 * declare. Every account created through this project's Multi-Role feature - including the demo
 * account {@code docs.member.demo@gmail.com} - gets a login response whose {@code user} object
 * carries both {@code role} and {@code customRole}; the generated model only declares {@code
 * role}. Same finding, same fix, ported from the sibling ports' {@code MudbaseAuthClient}: a raw
 * call over the SDK's own shared {@code OkHttpClient}, parsed leniently with Jackson's {@code
 * ignoreUnknown} instead of the strict generated Gson model.
 */
@Component
public class MudbaseAuthClient {

  /**
   * This project ships Mudbase's single default starter application role - slug "customer",
   * signup endpoint "customer" (same convention documented in the reference web app's {@code
   * src/lib/mudbase.ts}: signup against "user" 404s with "Role not found", signup against
   * "customer" succeeds). There is only one role in this app, so it is hardcoded here rather than
   * exposed as a caller-supplied parameter.
   */
  private static final String APP_ROLE = "customer";

  private static final ObjectMapper MAPPER = new ObjectMapper();

  private final MudbaseClientFactory clientFactory;

  public MudbaseAuthClient(MudbaseClientFactory clientFactory) {
    this.clientFactory = clientFactory;
  }

  public AuthResult register(String email, String password, String firstName, String lastName, boolean agreedToTerms) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("email", email);
    body.put("password", password);
    body.put("firstName", firstName);
    body.put("lastName", lastName);
    body.put("agreedToTerms", agreedToTerms);
    body.put("projectId", clientFactory.projectId());

    String requestJson = writeJson(body, "registration");

    Request request =
        new Request.Builder()
            .url(clientFactory.baseUrl() + "/api/auth/local/signup/" + APP_ROLE)
            .post(RequestBody.create(requestJson, MediaType.parse("application/json")))
            .build();

    try (Response response = clientFactory.rawHttpClient().newCall(request).execute()) {
      String responseBody = response.body() != null ? response.body().string() : "";
      if (!response.isSuccessful()) {
        throw MudbaseApiException.fromRawBody(response.code(), responseBody);
      }
      RegisterPayload payload = MAPPER.readValue(responseBody, RegisterPayload.class);
      RegisterPayload.User user = payload.user;
      return new AuthResult(
          payload.token,
          user != null ? user.id : null,
          user != null ? user.email : email,
          user != null ? user.firstName : firstName,
          user != null ? user.lastName : lastName,
          user != null && user.customRole != null ? user.customRole : APP_ROLE,
          payload.refreshToken);
    } catch (IOException e) {
      throw new MudbaseApiException("Could not reach Mudbase to register", 502, null, e);
    }
  }

  public AuthResult login(String email, String password) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("email", email);
    body.put("password", password);
    body.put("projectId", clientFactory.projectId());

    String requestJson = writeJson(body, "login");

    OkHttpClient httpClient = clientFactory.rawHttpClient();
    Request request =
        new Request.Builder()
            .url(clientFactory.baseUrl() + "/api/auth/local/login")
            .post(RequestBody.create(requestJson, MediaType.parse("application/json")))
            .build();

    try (Response response = httpClient.newCall(request).execute()) {
      String responseBody = response.body() != null ? response.body().string() : "";
      if (!response.isSuccessful()) {
        throw MudbaseApiException.fromRawBody(response.code(), responseBody);
      }
      LoginPayload payload = MAPPER.readValue(responseBody, LoginPayload.class);
      LoginPayload.User user = payload.user;
      return new AuthResult(
          payload.token,
          user != null ? user.id : null,
          user != null ? user.email : email,
          user != null ? user.firstName : null,
          user != null ? user.lastName : null,
          user != null && user.customRole != null ? user.customRole : (user != null ? user.role : null),
          payload.refreshToken);
    } catch (IOException e) {
      throw new MudbaseApiException("Could not reach Mudbase to log in", 502, null, e);
    }
  }

  public void logout(String bearerToken) {
    AuthenticationApi authApi = clientFactory.authApi(bearerToken);
    try {
      authApi.logoutLocalUser();
    } catch (ApiException e) {
      // Best-effort revoke: a failed server-side revoke must never block the user from being
      // signed out locally.
    }
  }

  /**
   * Verified live against this project: every collection read 401s with zero auth at all, even
   * with the project's own {@code pk_} key sent as {@code X-API-Key} (see plan/build-plan.md
   * "Data model"). An anonymous session lets guests browse and search the document library
   * without a real account.
   */
  public AuthResult createAnonymousSession() {
    AuthenticationApi authApi = clientFactory.authApi(null);
    CreateAnonymousSessionRequest request = new CreateAnonymousSessionRequest().projectId(clientFactory.projectId());
    try {
      CreateAnonymousSession200Response response = authApi.createAnonymousSession(request);
      var user = response.getUser();
      return new AuthResult(
          response.getToken(), user != null ? user.getId() : null, null, null, null, null, response.getRefreshToken());
    } catch (ApiException e) {
      throw MudbaseApiException.from(e);
    }
  }

  /**
   * Exchanges a stored refresh token for a new access/refresh token pair. Used by {@link
   * dev.mudbase.showcase.docssearch.auth.SessionAuthService#recoverFromUnauthorized} to
   * transparently recover from a 401 caused by an expired access token. Mudbase rotates the
   * refresh token on every use (the previous one is invalidated - reuse is treated as a
   * stolen-token signal), so the caller must persist the {@code refreshToken} on this result, not
   * just the {@code token}.
   */
  public AuthResult refresh(String refreshToken) {
    AuthenticationApi authApi = clientFactory.authApi(null);
    RefreshTokenRequest request = new RefreshTokenRequest().refreshToken(refreshToken);
    try {
      RefreshToken200Response response = authApi.refreshToken(request);
      return new AuthResult(
          response.getToken(),
          null,
          null,
          null,
          null,
          null,
          response.getRefreshToken() != null ? response.getRefreshToken() : refreshToken);
    } catch (ApiException e) {
      throw MudbaseApiException.from(e);
    }
  }

  private static String writeJson(Map<String, Object> body, String what) {
    try {
      return MAPPER.writeValueAsString(body);
    } catch (Exception e) {
      throw new IllegalStateException("Could not serialize " + what + " request", e);
    }
  }

  /** Hand-written mirror of RegisterLocalUser201Response - see class javadoc for why. */
  @JsonIgnoreProperties(ignoreUnknown = true)
  private static class RegisterPayload {
    public String message;
    public Boolean requireVerification;
    public String token;
    public String refreshToken;
    public Integer expiresIn;
    public User user;

    @JsonIgnoreProperties(ignoreUnknown = true)
    static class User {
      public String id;
      public String email;
      public String firstName;
      public String lastName;
      public Boolean emailVerified;
      public String customRole;
    }
  }

  /**
   * Hand-written mirror of LoginLocalUser200Response, deliberately Jackson-lenient ({@code
   * ignoreUnknown}) rather than the generated Gson model's strict field validation - see class
   * javadoc. Declares both {@code role} and {@code customRole} since real Multi-Role accounts'
   * login responses carry both.
   */
  @JsonIgnoreProperties(ignoreUnknown = true)
  private static class LoginPayload {
    public String message;
    public String token;
    public String refreshToken;
    public Integer expiresIn;
    public User user;

    @JsonIgnoreProperties(ignoreUnknown = true)
    static class User {
      public String id;
      public String email;
      public String firstName;
      public String lastName;
      public String role;
      public String customRole;
      public Boolean emailVerified;
      public Boolean twoFactorEnabled;
    }
  }
}
