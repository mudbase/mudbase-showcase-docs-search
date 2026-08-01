package dev.mudbase.showcase.docssearch.mudbase;

/** Normalized result of any Mudbase auth call (register, login, anonymous session, refresh). */
public class AuthResult {

  private final String token;
  private final String userId;
  private final String email;
  private final String firstName;
  private final String lastName;
  private final String customRole;
  private final String refreshToken;

  public AuthResult(
      String token,
      String userId,
      String email,
      String firstName,
      String lastName,
      String customRole,
      String refreshToken) {
    this.token = token;
    this.userId = userId;
    this.email = email;
    this.firstName = firstName;
    this.lastName = lastName;
    this.customRole = customRole;
    this.refreshToken = refreshToken;
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

  public String getCustomRole() {
    return customRole;
  }

  public String getRefreshToken() {
    return refreshToken;
  }
}
