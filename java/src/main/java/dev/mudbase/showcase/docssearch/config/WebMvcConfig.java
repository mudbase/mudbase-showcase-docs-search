package dev.mudbase.showcase.docssearch.config;

import dev.mudbase.showcase.docssearch.auth.RequireSignInInterceptor;
import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Registers {@link RequireSignInInterceptor} on the document-authoring routes only - the library
 * ({@code /}), document detail ({@code /documents/{id}}), and Ask AI ({@code /ask}) all remain
 * public per plan/build-plan.md "Auth model" (anonymous/guest browsing+search is allowed
 * read-only). Per-document edit/delete ownership is enforced separately in {@code
 * DocumentService}, since the interceptor has no way to know which document a path segment
 * refers to.
 */
@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

  private final SessionAuthService sessionAuthService;

  public WebMvcConfig(SessionAuthService sessionAuthService) {
    this.sessionAuthService = sessionAuthService;
  }

  @Override
  public void addInterceptors(InterceptorRegistry registry) {
    registry
        .addInterceptor(new RequireSignInInterceptor(sessionAuthService))
        .addPathPatterns("/documents", "/documents/new", "/documents/*/edit", "/documents/*/delete");
  }
}
