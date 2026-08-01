package dev.mudbase.showcase.docssearch.service;

import dev.mudbase.showcase.docssearch.auth.AuthSession;
import dev.mudbase.showcase.docssearch.auth.SessionAuthService;
import dev.mudbase.showcase.docssearch.config.MudbaseProperties;
import dev.mudbase.showcase.docssearch.domain.DocumentRecord;
import dev.mudbase.showcase.docssearch.mudbase.MudbaseApiException;
import dev.mudbase.showcase.docssearch.mudbase.MudbaseDataClient;
import dev.mudbase.showcase.docssearch.support.ForbiddenActionException;
import jakarta.servlet.http.HttpSession;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;

/**
 * Reads and writes the `documents` collection. Library/detail browsing and Ask AI retrieval need
 * "some" Mudbase-issued bearer token to satisfy the collection's authenticated-role read
 * permission even before sign-in - {@link SessionAuthService#publicReadToken} supplies that (the
 * signed-in user's own token, or a lazily-created anonymous guest token). Creation always uses the
 * acting user's own JWT (gated to signed-in users by {@code RequireSignInInterceptor}); edit and
 * delete additionally require this service's own authorId ownership check - see {@link
 * dev.mudbase.showcase.docssearch.support.ForbiddenActionException}.
 */
@Service
public class DocumentService {

  private static final int LIBRARY_PAGE_SIZE = 100;

  private final MudbaseDataClient dataClient;
  private final MudbaseProperties properties;
  private final SessionAuthService sessionAuthService;

  public DocumentService(MudbaseDataClient dataClient, MudbaseProperties properties, SessionAuthService sessionAuthService) {
    this.dataClient = dataClient;
    this.properties = properties;
    this.sessionAuthService = sessionAuthService;
  }

  /** Newest first - mirrors the reference web app's library page (`sort: "-createdAt", limit: 100`). */
  public List<DocumentRecord> listAll(HttpSession session) {
    String token = sessionAuthService.publicReadToken(session);
    return dataClient
        .list(token, properties.getDocumentsCollectionId(), Map.of(), "-createdAt", 1, LIBRARY_PAGE_SIZE)
        .stream()
        .map(DocumentRecord::fromDocument)
        .toList();
  }

  public Optional<DocumentRecord> findById(HttpSession session, String id) {
    String token = sessionAuthService.publicReadToken(session);
    try {
      return Optional.of(DocumentRecord.fromDocument(dataClient.get(token, properties.getDocumentsCollectionId(), id)));
    } catch (MudbaseApiException e) {
      return Optional.empty();
    }
  }

  public DocumentRecord create(AuthSession author, String title, String content, String tags) {
    Map<String, Object> body = DocumentRecord.toCreateBody(title, content, tags, author.getUserId(), author.getDisplayName());
    return DocumentRecord.fromDocument(dataClient.create(author.getToken(), properties.getDocumentsCollectionId(), body));
  }

  /**
   * Loads the document by id using the author's own token, then verifies {@code author.userId}
   * matches {@code document.authorId} before returning it - callers use this result to render the
   * edit form and must never reach it for a document they don't own.
   */
  public DocumentRecord requireOwnedDocument(AuthSession author, String id) {
    DocumentRecord document;
    try {
      document = DocumentRecord.fromDocument(dataClient.get(author.getToken(), properties.getDocumentsCollectionId(), id));
    } catch (MudbaseApiException e) {
      throw e;
    }
    if (!document.isOwnedBy(author.getUserId())) {
      throw new ForbiddenActionException("You can only edit or delete documents you authored.");
    }
    return document;
  }

  public DocumentRecord update(AuthSession author, String id, String title, String content, String tags) {
    requireOwnedDocument(author, id);
    Map<String, Object> body = DocumentRecord.toUpdateBody(title, content, tags);
    return DocumentRecord.fromDocument(dataClient.update(author.getToken(), properties.getDocumentsCollectionId(), id, body));
  }

  public void delete(AuthSession author, String id) {
    requireOwnedDocument(author, id);
    dataClient.delete(author.getToken(), properties.getDocumentsCollectionId(), id);
  }
}
