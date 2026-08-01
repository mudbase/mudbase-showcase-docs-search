package dev.mudbase.showcase.docssearch.web;

import dev.mudbase.showcase.docssearch.auth.AuthSession;
import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import dev.mudbase.showcase.docssearch.domain.DocumentRecord;
import dev.mudbase.showcase.docssearch.service.DocumentService;
import dev.mudbase.showcase.docssearch.support.ViewModelHelper;
import dev.mudbase.showcase.docssearch.web.dto.DocumentFormRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import java.util.Optional;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;

/**
 * Document CRUD - creation gated to signed-in users ({@code RequireSignInInterceptor} on {@code
 * /documents} and {@code /documents/new}); edit/delete additionally require {@code
 * DocumentService}'s own authorId ownership check (also gated to signed-in via {@code
 * /documents/*}/edit} and {@code /documents/*}/delete}). Detail view stays public.
 */
@Controller
public class DocumentController {

  private final DocumentService documentService;
  private final SessionAuthService sessionAuthService;
  private final ViewModelHelper viewModelHelper;

  public DocumentController(DocumentService documentService, SessionAuthService sessionAuthService, ViewModelHelper viewModelHelper) {
    this.documentService = documentService;
    this.sessionAuthService = sessionAuthService;
    this.viewModelHelper = viewModelHelper;
  }

  @GetMapping("/documents/new")
  public String newForm(Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!model.containsAttribute("documentForm")) {
      model.addAttribute("documentForm", new DocumentFormRequest());
    }
    model.addAttribute("isEdit", false);
    return "documents/form";
  }

  @PostMapping("/documents")
  public String create(
      @Valid @ModelAttribute("documentForm") DocumentFormRequest form, BindingResult bindingResult, Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (bindingResult.hasErrors()) {
      model.addAttribute("isEdit", false);
      return "documents/form";
    }
    AuthSession author = sessionAuthService.signedInUser(session).orElseThrow();
    DocumentRecord created = documentService.create(author, form.getTitle(), form.getContent(), form.getTags());
    return "redirect:/documents/" + created.getId();
  }

  @GetMapping("/documents/{id}")
  public String detail(@PathVariable String id, Model model, HttpSession session) {
    AuthSession current = viewModelHelper.addLayoutAttributes(model, session);
    Optional<DocumentRecord> document = documentService.findById(session, id);
    if (document.isEmpty()) {
      model.addAttribute("errorMessage", "This document isn't available.");
      return "documents/not-found";
    }
    boolean isOwner = current != null && document.get().isOwnedBy(current.getUserId());
    model.addAttribute("document", document.get());
    model.addAttribute("isOwner", isOwner);
    return "documents/detail";
  }

  @GetMapping("/documents/{id}/edit")
  public String editForm(@PathVariable String id, Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    AuthSession author = sessionAuthService.signedInUser(session).orElseThrow();
    DocumentRecord document = documentService.requireOwnedDocument(author, id);
    model.addAttribute("documentForm", toForm(document));
    model.addAttribute("isEdit", true);
    model.addAttribute("documentId", id);
    return "documents/form";
  }

  @PostMapping("/documents/{id}/edit")
  public String update(
      @PathVariable String id,
      @Valid @ModelAttribute("documentForm") DocumentFormRequest form,
      BindingResult bindingResult,
      Model model,
      HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (bindingResult.hasErrors()) {
      model.addAttribute("isEdit", true);
      model.addAttribute("documentId", id);
      return "documents/form";
    }
    AuthSession author = sessionAuthService.signedInUser(session).orElseThrow();
    documentService.update(author, id, form.getTitle(), form.getContent(), form.getTags());
    return "redirect:/documents/" + id;
  }

  @PostMapping("/documents/{id}/delete")
  public String delete(@PathVariable String id, HttpSession session) {
    AuthSession author = sessionAuthService.signedInUser(session).orElseThrow();
    documentService.delete(author, id);
    return "redirect:/";
  }

  private DocumentFormRequest toForm(DocumentRecord document) {
    DocumentFormRequest form = new DocumentFormRequest();
    form.setTitle(document.getTitle());
    form.setContent(document.getContent());
    form.setTags(document.getTags() != null ? document.getTags() : "");
    return form;
  }
}
