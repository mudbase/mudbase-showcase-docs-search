package dev.mudbase.showcase.docssearch.service;

import dev.mudbase.showcase.docssearch.auth.AuthSession;
import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import dev.mudbase.showcase.docssearch.config.MudbaseProperties;
import dev.mudbase.showcase.docssearch.domain.SearchLogEntry;
import dev.mudbase.showcase.docssearch.mudbase.MudbaseDataClient;
import jakarta.servlet.http.HttpSession;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

/**
 * Reads and writes the `search_log` collection - every Ask AI question gets logged here, whether
 * asked by a guest or a signed-in customer, exactly matching the reference web app's {@code
 * AskAIPanel.tsx}.
 */
@Service
public class SearchLogService {

  private static final int RECENT_SEARCHES_LIMIT = 10;

  private final MudbaseDataClient dataClient;
  private final MudbaseProperties properties;
  private final SessionAuthService sessionAuthService;

  public SearchLogService(MudbaseDataClient dataClient, MudbaseProperties properties, SessionAuthService sessionAuthService) {
    this.dataClient = dataClient;
    this.properties = properties;
    this.sessionAuthService = sessionAuthService;
  }

  /** Most recent searches across all users, newest first - mirrors {@code RecentSearches.tsx}. */
  public List<SearchLogEntry> recent(HttpSession session) {
    String token = sessionAuthService.publicReadToken(session);
    return dataClient
        .list(token, properties.getSearchLogCollectionId(), Map.of(), "-createdAt", 1, RECENT_SEARCHES_LIMIT)
        .stream()
        .map(SearchLogEntry::fromDocument)
        .toList();
  }

  /**
   * Logs one Ask AI query. {@code userId}/{@code userName} are included only for a real signed-in
   * user - never a placeholder - see {@link SearchLogEntry#toCreateBody}. Uses {@link
   * SessionAuthService#publicReadToken} so a guest's search is logged too (the `customer` role's
   * unconditional CRUD grant on this collection covers both, exactly as the reference app's own
   * anonymous-session writes do).
   */
  public void log(HttpSession session, String queryText, int resultCount) {
    String token = sessionAuthService.publicReadToken(session);
    AuthSession signedIn = sessionAuthService.signedInUser(session).orElse(null);
    Map<String, Object> body =
        SearchLogEntry.toCreateBody(
            queryText,
            resultCount,
            signedIn != null ? signedIn.getUserId() : null,
            signedIn != null ? signedIn.getDisplayName() : null);
    dataClient.create(token, properties.getSearchLogCollectionId(), body);
  }
}
