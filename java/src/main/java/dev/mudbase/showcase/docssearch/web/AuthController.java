package dev.mudbase.showcase.docssearch.web;

import dev.mudbase.showcase.docssearch.mudbase.MudbaseApiException;
import dev.mudbase.showcase.docssearch.service.AuthService;
import dev.mudbase.showcase.docssearch.support.ViewModelHelper;
import dev.mudbase.showcase.docssearch.web.dto.LoginRequest;
import dev.mudbase.showcase.docssearch.web.dto.RegisterRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
public class AuthController {

  private final AuthService authService;
  private final ViewModelHelper viewModelHelper;

  public AuthController(AuthService authService, ViewModelHelper viewModelHelper) {
    this.authService = authService;
    this.viewModelHelper = viewModelHelper;
  }

  @GetMapping("/login")
  public String loginForm(
      @RequestParam(value = "redirect", required = false) String redirect, Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!model.containsAttribute("loginRequest")) {
      model.addAttribute("loginRequest", new LoginRequest());
    }
    model.addAttribute("redirectTo", redirect);
    return "auth/login";
  }

  @PostMapping("/login")
  public String login(
      @Valid @ModelAttribute("loginRequest") LoginRequest form,
      BindingResult bindingResult,
      @RequestParam(value = "redirect", required = false) String redirect,
      Model model,
      HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!bindingResult.hasErrors()) {
      try {
        authService.login(session, form.getEmail(), form.getPassword());
        if (redirect != null && !redirect.isBlank()) {
          return "redirect:" + redirect;
        }
        return "redirect:/";
      } catch (MudbaseApiException e) {
        model.addAttribute("authError", e.getMessage());
      }
    }
    model.addAttribute("redirectTo", redirect);
    return "auth/login";
  }

  @GetMapping("/register")
  public String registerForm(Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!model.containsAttribute("registerRequest")) {
      model.addAttribute("registerRequest", new RegisterRequest());
    }
    return "auth/register";
  }

  @PostMapping("/register")
  public String register(
      @Valid @ModelAttribute("registerRequest") RegisterRequest form, BindingResult bindingResult, Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!bindingResult.hasErrors()) {
      try {
        authService.register(
            session, form.getEmail(), form.getPassword(), form.getFirstName(), form.getLastName(), form.isAgreedToTerms());
        return "redirect:/";
      } catch (MudbaseApiException e) {
        model.addAttribute("authError", e.getMessage());
      }
    }
    return "auth/register";
  }

  @PostMapping("/logout")
  public String logout(HttpSession session) {
    authService.logout(session);
    return "redirect:/";
  }
}
