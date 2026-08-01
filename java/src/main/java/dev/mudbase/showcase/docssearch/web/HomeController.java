package dev.mudbase.showcase.docssearch.web;

import dev.mudbase.showcase.docssearch.domain.DocumentRecord;
import dev.mudbase.showcase.docssearch.service.DocumentService;
import dev.mudbase.showcase.docssearch.support.Retrieval;
import dev.mudbase.showcase.docssearch.support.ViewModelHelper;
import jakarta.servlet.http.HttpSession;
import java.util.List;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

/**
 * The document library - public (anonymous session), server-rendered substring search across
 * title/content/tags. This app has no client JS framework, so the exact same filtering the
 * reference web app runs client-side over an already-fetched document list runs here server-side
 * on every request instead - same behavior, same {@link Retrieval#matchesSearchTerm} logic.
 */
@Controller
public class HomeController {

  private final DocumentService documentService;
  private final ViewModelHelper viewModelHelper;

  public HomeController(DocumentService documentService, ViewModelHelper viewModelHelper) {
    this.documentService = documentService;
    this.viewModelHelper = viewModelHelper;
  }

  @GetMapping("/")
  public String library(@RequestParam(value = "q", required = false) String query, Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    List<DocumentRecord> documents = documentService.listAll(session);
    List<DocumentRecord> filtered = documents.stream().filter(document -> Retrieval.matchesSearchTerm(document, query)).toList();
    model.addAttribute("documents", filtered);
    model.addAttribute("searchTerm", query != null ? query : "");
    return "index";
  }
}
