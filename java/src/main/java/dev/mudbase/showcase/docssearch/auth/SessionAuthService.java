package dev.mudbase.showcase.docssearch.auth;

import dev.mudbase.showcase.docssearch.mudbase.AuthResult;
import dev.mudbase.showcase.docssearch.mudbase.MudbaseAuthClient;
import jakarta.servlet.http.HttpSession;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Bridges the Spring {@code HttpSession} to Mudbase auth. The JWT lives here, server-side, for
 * the life of the session - never sent to client JS. Ported verbatim from the sibling
 * ecommerce/social Java showcases, which established this exact "signed-in user, or a lazily
 * created anonymous guest, sharing one HttpSession slot" pattern for public-read/gated-write apps.
 */
@Component
public class SessionAuthService {

  static final String SESSION_KEY = "mudbase.auth";

  private final MudbaseAuthClient authClient;

  public SessionAuthService(MudbaseAuthClient authClient) {
    this.authClient = authClient;
  }

  public Optional<AuthSession> current(HttpSession session) {
    Object attribute = session.getAttribute(SESSION_KEY);
    return attribute instanceof AuthSession auth ? Optional.of(auth) : Optional.empty();
  }

  public Optional<AuthSession> signedInUser(HttpSession session) {
    return current(session).filter(AuthSession::isSignedIn);
  }

  /**
   * A bearer token good enough for the {@code documents}/{@code search_log} collections'
   * authenticated-role, read-permitted access: the signed-in user's own token when there is one,
   * otherwise a lazily-created anonymous guest session cached for the rest of this HttpSession -
   * mirrors the reference web app's "anonymous session on first visit" behavior (see
   * build-plan.md "Auth flow"), just held server-side instead of in the browser.
   */
  public String publicReadToken(HttpSession session) {
    Optional<AuthSession> existing = current(session);
    if (existing.isPresent()) {
      return existing.get().getToken();
    }
    AuthResult anonymous = authClient.createAnonymousSession();
    session.setAttribute(
        SESSION_KEY, AuthSession.anonymous(anonymous.getToken(), anonymous.getUserId(), anonymous.getRefreshToken()));
    return anonymous.getToken();
  }

  public void establish(HttpSession session, AuthResult result) {
    session.setAttribute(
        SESSION_KEY,
        new AuthSession(
            result.getToken(),
            result.getUserId(),
            result.getEmail(),
            result.getFirstName(),
            result.getLastName(),
            result.getCustomRole(),
            false,
            result.getRefreshToken()));
  }

  public void logout(HttpSession session) {
    current(session).filter(AuthSession::isSignedIn).ifPresent(auth -> authClient.logout(auth.getToken()));
    session.removeAttribute(SESSION_KEY);
  }

  /**
   * Recovers from a 401 on an ordinary data/collection call by exchanging the stored refresh
   * token for a new access token, once. Called by {@link
   * dev.mudbase.showcase.docssearch.mudbase.MudbaseDataClient} when a request bearing {@code
   * failedToken} comes back unauthorized - covers both a signed-in customer session and the
   * anonymous guest session used for pre-login browsing, since Mudbase issues a refresh token for
   * both.
   *
   * <p><b>Why a token mismatch does not mean "nothing to do."</b> Several controller methods read
   * the current {@link AuthSession} once and then make two or more sequential {@link
   * dev.mudbase.showcase.docssearch.mudbase.MudbaseDataClient} calls with that same snapshot's
   * token (e.g. the Ask AI flow: list documents, then log the search). If the token was expired,
   * the *first* of those calls lands here, refreshes, and updates the session - but the *second*
   * call still carries the pre-refresh token, so it 401s too and lands here again with a {@code
   * failedToken} that no longer matches {@code current.getToken()} (the first call already moved
   * it forward). Treating that mismatch as "someone else already fixed it, give up" would discard
   * a perfectly good, just-refreshed session and force a spurious "session expired" logout on
   * every multi-call request. The correct read of a mismatch is the opposite: the session already
   * holds a token newer than the one that failed, so hand that back for an immediate retry
   * instead of refreshing again - ported from the sibling ecommerce Java port's own hard-won fix
   * for this exact race.
   *
   * <p>Returns empty (no retry attempted) only when there is truly nothing left to recover with:
   * no session at all, the token that failed is still the one on file but there is no refresh
   * token to exchange it with, or the refresh call itself was rejected.
   */
  public Optional<AuthSession> recoverFromUnauthorized(HttpSession session, String failedToken) {
    Optional<AuthSession> currentOpt = current(session);
    if (currentOpt.isEmpty()) {
      return Optional.empty();
    }
    AuthSession current = currentOpt.get();
    if (!current.getToken().equals(failedToken)) {
      return Optional.of(current);
    }
    if (current.getRefreshToken() == null) {
      return Optional.empty();
    }
    try {
      AuthResult refreshed = authClient.refresh(current.getRefreshToken());
      AuthSession updated = current.withRefreshedToken(refreshed.getToken(), refreshed.getRefreshToken());
      session.setAttribute(SESSION_KEY, updated);
      return Optional.of(updated);
    } catch (RuntimeException refreshFailure) {
      return Optional.empty();
    }
  }
}
