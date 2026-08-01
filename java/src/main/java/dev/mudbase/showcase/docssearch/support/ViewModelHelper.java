package dev.mudbase.showcase.docssearch.support;

import dev.mudbase.showcase.docssearch.auth.AuthSession;
import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Component;
import org.springframework.ui.Model;

/**
 * Populates the header/nav attributes every Thymeleaf page needs (current user, sign-in state).
 * Deliberately called explicitly per template-rendering controller method rather than wired as a
 * global {@code @ControllerAdvice @ModelAttribute} - matches the sibling kanban/ecommerce/social
 * ports' own reasoning: keeps every controller's data needs explicit at the call site.
 */
@Component
public class ViewModelHelper {

  private final SessionAuthService sessionAuthService;

  public ViewModelHelper(SessionAuthService sessionAuthService) {
    this.sessionAuthService = sessionAuthService;
  }

  public AuthSession addLayoutAttributes(Model model, HttpSession session) {
    AuthSession auth = sessionAuthService.current(session).filter(AuthSession::isSignedIn).orElse(null);
    model.addAttribute("currentUser", auth);
    model.addAttribute("isSignedIn", auth != null);
    return auth;
  }
}
