package dev.mudbase.showcase.docssearch.auth;

import java.io.Serializable;

/**
 * The signed-in user's Mudbase identity, held server-side in the Spring {@code HttpSession} - the
 * JWT never reaches client JS (this app renders plain HTML/CSS, no token ever enters browser
 * scope). One instance covers both a real "customer" account and the lazily-created anonymous
 * guest session used only to satisfy the {@code documents}/{@code search_log} collections'
 * authenticated-role permission while browsing/searching before sign-in.
 */
public class AuthSession implements Serializable {

  private static final long serialVersionUID = 1L;

  private final String token;
  private final String userId;
  private final String email;
  private final String firstName;
  private final String lastName;
  private final String customRole;
  private final boolean anonymous;
  private final String refreshToken;

  public AuthSession(
      String token,
      String userId,
      String email,
      String firstName,
      String lastName,
      String customRole,
      boolean anonymous,
      String refreshToken) {
    this.token = token;
    this.userId = userId;
    this.email = email;
    this.firstName = firstName;
    this.lastName = lastName;
    this.customRole = customRole;
    this.anonymous = anonymous;
    this.refreshToken = refreshToken;
  }

  public static AuthSession anonymous(String token, String userId, String refreshToken) {
    return new AuthSession(token, userId, null, null, null, null, true, refreshToken);
  }

  /**
   * Immutable copy carrying a rotated access/refresh token pair after a successful refresh -
   * every other field (identity, role, anonymous flag) is preserved since a token refresh never
   * changes who the caller is.
   */
  public AuthSession withRefreshedToken(String newToken, String newRefreshToken) {
    return new AuthSession(newToken, userId, email, firstName, lastName, customRole, anonymous, newRefreshToken);
  }

  public String getToken() {
    return token;
  }

  public String getUserId() {
    return userId;
  }

  public String getEmail() {
    return email;
  }

  public String getFirstName() {
    return firstName;
  }

  public String getLastName() {
    return lastName;
  }

  public String getDisplayName() {
    if (firstName == null && lastName == null) {
      return email != null ? email : "Guest";
    }
    return String.join(" ", firstName != null ? firstName : "", lastName != null ? lastName : "").trim();
  }

  public String getCustomRole() {
    return customRole;
  }

  public boolean isAnonymous() {
    return anonymous;
  }

  public String getRefreshToken() {
    return refreshToken;
  }

  public boolean isSignedIn() {
    return !anonymous && userId != null;
  }
}
