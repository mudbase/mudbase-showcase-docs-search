package dev.mudbase.showcase.docssearch.service;

import dev.mudbase.showcase.docssearch.auth.AuthSession;
import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import dev.mudbase.showcase.docssearch.mudbase.AuthResult;
import dev.mudbase.showcase.docssearch.mudbase.MudbaseAuthClient;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Service;

/** Registration is always the project's single default "customer" role - see MudbaseAuthClient. */
@Service
public class AuthService {

  private final MudbaseAuthClient authClient;
  private final SessionAuthService sessionAuthService;

  public AuthService(MudbaseAuthClient authClient, SessionAuthService sessionAuthService) {
    this.authClient = authClient;
    this.sessionAuthService = sessionAuthService;
  }

  public AuthSession register(
      HttpSession session, String email, String password, String firstName, String lastName, boolean agreedToTerms) {
    AuthResult result = authClient.register(email, password, firstName, lastName, agreedToTerms);
    sessionAuthService.establish(session, result);
    return sessionAuthService.current(session).orElseThrow();
  }

  public AuthSession login(HttpSession session, String email, String password) {
    AuthResult result = authClient.login(email, password);
    sessionAuthService.establish(session, result);
    return sessionAuthService.current(session).orElseThrow();
  }

  public void logout(HttpSession session) {
    sessionAuthService.logout(session);
  }
}
