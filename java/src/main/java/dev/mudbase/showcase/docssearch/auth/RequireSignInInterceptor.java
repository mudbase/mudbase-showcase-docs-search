package dev.mudbase.showcase.docssearch.auth;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * Gates the document-authoring routes (new/edit/delete) - guests are sent to /login and back.
 * Per-document ownership (only the author may edit/delete a given document) is a separate check,
 * enforced in {@link dev.mudbase.showcase.docssearch.service.DocumentService} since it depends on
 * which document is being acted on, not just whether someone is signed in at all.
 */
public class RequireSignInInterceptor implements HandlerInterceptor {

  private final SessionAuthService sessionAuthService;

  public RequireSignInInterceptor(SessionAuthService sessionAuthService) {
    this.sessionAuthService = sessionAuthService;
  }

  @Override
  public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
    if (sessionAuthService.signedInUser(request.getSession()).isPresent()) {
      return true;
    }
    String redirectTo = request.getRequestURI()
        + (request.getQueryString() != null ? "?" + request.getQueryString() : "");
    String encoded = URLEncoder.encode(redirectTo, StandardCharsets.UTF_8);
    response.setStatus(HttpServletResponse.SC_FOUND);
    response.setHeader("Location", request.getContextPath() + "/login?redirect=" + encoded);
    return false;
  }
}
