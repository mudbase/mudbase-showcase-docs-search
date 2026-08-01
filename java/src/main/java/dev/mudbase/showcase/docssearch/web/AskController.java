package dev.mudbase.showcase.docssearch.web;

import dev.mudbase.showcase.docssearch.service.AskAiResult;
import dev.mudbase.showcase.docssearch.service.AskAiService;
import dev.mudbase.showcase.docssearch.service.SearchLogService;
import dev.mudbase.showcase.docssearch.support.ViewModelHelper;
import dev.mudbase.showcase.docssearch.web.dto.AskFormRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;

/**
 * Ask AI - public (works for guests too; {@code search_log.userId} is only set when signed in).
 * Since this app is itself server-rendered, the whole request/response cycle described in
 * plan/build-plan.md "Ask AI architecture" runs synchronously inside {@link
 * AskAiService#ask}: keyword scoring, Mudbase Function invoke+poll, then the Anthropic completion
 * call, all before this controller method returns and Thymeleaf renders the result.
 */
@Controller
public class AskController {

  private final AskAiService askAiService;
  private final SearchLogService searchLogService;
  private final ViewModelHelper viewModelHelper;

  public AskController(AskAiService askAiService, SearchLogService searchLogService, ViewModelHelper viewModelHelper) {
    this.askAiService = askAiService;
    this.searchLogService = searchLogService;
    this.viewModelHelper = viewModelHelper;
  }

  @GetMapping("/ask")
  public String panel(Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!model.containsAttribute("askForm")) {
      model.addAttribute("askForm", new AskFormRequest());
    }
    model.addAttribute("recentSearches", searchLogService.recent(session));
    return "ask/panel";
  }

  @PostMapping("/ask")
  public String ask(@Valid @ModelAttribute("askForm") AskFormRequest form, BindingResult bindingResult, Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!bindingResult.hasErrors()) {
      try {
        AskAiResult result = askAiService.ask(session, form.getQuestion());
        model.addAttribute("askResult", result);
      } catch (RuntimeException e) {
        model.addAttribute("askError", e.getMessage());
      }
    }
    model.addAttribute("recentSearches", searchLogService.recent(session));
    return "ask/panel";
  }
}
