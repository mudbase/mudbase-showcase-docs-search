package dev.mudbase.showcase.docssearch.web;

import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import dev.mudbase.showcase.docssearch.mudbase.MudbaseApiException;
import dev.mudbase.showcase.docssearch.support.ForbiddenActionException;
import dev.mudbase.showcase.docssearch.support.ViewModelHelper;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.servlet.ModelAndView;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

/**
 * Every unhandled Mudbase call failure, and every {@link ForbiddenActionException} raised by
 * {@code DocumentService}'s ownership check, lands here instead of a raw stack trace. {@link
 * dev.mudbase.showcase.docssearch.mudbase.MudbaseDataClient} already retries a 401 once via a
 * silent refresh-token exchange (see {@link SessionAuthService#recoverFromUnauthorized}), so by
 * the time a 401 reaches this handler the refresh path has already been tried and failed - this
 * clears the session and bounces to /login as the terminal "session expired" behavior; everything
 * else renders a plain error page with a descriptive message.
 */
@ControllerAdvice
public class GlobalExceptionHandler {

  private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

  private final SessionAuthService sessionAuthService;
  private final ViewModelHelper viewModelHelper;

  public GlobalExceptionHandler(SessionAuthService sessionAuthService, ViewModelHelper viewModelHelper) {
    this.sessionAuthService = sessionAuthService;
    this.viewModelHelper = viewModelHelper;
  }

  @ExceptionHandler(ForbiddenActionException.class)
  public ModelAndView handleForbidden(ForbiddenActionException exception, HttpServletRequest request, Model model) {
    log.warn("Forbidden action on {} {}: {}", request.getMethod(), request.getRequestURI(), exception.getMessage());
    viewModelHelper.addLayoutAttributes(model, request.getSession());
    model.addAttribute("errorMessage", exception.getMessage());
    model.addAttribute("statusCode", 403);
    ModelAndView mav = new ModelAndView("error");
    mav.setStatus(HttpStatus.FORBIDDEN);
    return mav;
  }

  @ExceptionHandler(MudbaseApiException.class)
  public ModelAndView handleMudbaseError(
      MudbaseApiException exception, HttpServletRequest request, Model model, RedirectAttributes redirectAttributes) {
    if (exception.isUnauthorized()) {
      log.info("Session expired on {} {}, logging out and redirecting to /login", request.getMethod(), request.getRequestURI());
      sessionAuthService.logout(request.getSession());
      redirectAttributes.addFlashAttribute("errorMessage", "Your session expired - please sign in again.");
      return new ModelAndView("redirect:/login");
    }
    log.warn(
        "Mudbase call failed on {} {}: status={} message={}",
        request.getMethod(),
        request.getRequestURI(),
        exception.getStatusCode(),
        exception.getMessage());
    viewModelHelper.addLayoutAttributes(model, request.getSession());
    model.addAttribute("errorMessage", exception.getMessage());
    model.addAttribute("statusCode", exception.getStatusCode());
    ModelAndView mav = new ModelAndView("error");
    mav.setStatus(HttpStatus.valueOf(exception.getStatusCode() >= 400 ? exception.getStatusCode() : 500));
    return mav;
  }

  @ExceptionHandler(Exception.class)
  public ModelAndView handleUnexpected(Exception exception, HttpServletRequest request, Model model) {
    log.error("Unexpected error on {} {}", request.getMethod(), request.getRequestURI(), exception);
    viewModelHelper.addLayoutAttributes(model, request.getSession());
    model.addAttribute("errorMessage", "Something went wrong. Please try again.");
    model.addAttribute("statusCode", 500);
    ModelAndView mav = new ModelAndView("error");
    mav.setStatus(HttpStatus.INTERNAL_SERVER_ERROR);
    return mav;
  }
}
