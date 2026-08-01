package dev.mudbase.showcase.docssearch.domain;

import dev.mudbase.showcase.docssearch.mudbase.DocumentMapper;
import dev.mudbase.showcase.docssearch.support.Formatting;
import java.util.LinkedHashMap;
import java.util.Map;

/** Mirrors the `search_log` collection - see plan/build-plan.md in the reference web app. */
public class SearchLogEntry {

  private final String id;
  private final String queryText;
  private final String userId;
  private final String userName;
  private final int resultCount;
  private final String createdAt;

  public SearchLogEntry(String id, String queryText, String userId, String userName, int resultCount, String createdAt) {
    this.id = id;
    this.queryText = queryText;
    this.userId = userId;
    this.userName = userName;
    this.resultCount = resultCount;
    this.createdAt = createdAt;
  }

  public static SearchLogEntry fromDocument(Map<String, Object> doc) {
    return new SearchLogEntry(
        DocumentMapper.getId(doc),
        DocumentMapper.getString(doc, "queryText"),
        DocumentMapper.getString(doc, "userId"),
        DocumentMapper.getString(doc, "userName"),
        DocumentMapper.getInt(doc, "resultCount", 0),
        DocumentMapper.getString(doc, "createdAt"));
  }

  /**
   * A new, unsaved log entry ready for {@code createDocument}. {@code userId}/{@code userName}
   * are omitted entirely for a guest search - never written as a placeholder string - matching
   * the reference web app's {@code AskAIPanel.tsx} exactly.
   */
  public static Map<String, Object> toCreateBody(String queryText, int resultCount, String userId, String userName) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("queryText", queryText);
    body.put("resultCount", resultCount);
    if (userId != null && !userId.isBlank()) {
      body.put("userId", userId);
    }
    if (userName != null && !userName.isBlank()) {
      body.put("userName", userName);
    }
    return body;
  }

  public String getId() {
    return id;
  }

  public String getQueryText() {
    return queryText;
  }

  public String getUserId() {
    return userId;
  }

  public String getUserName() {
    return userName;
  }

  public int getResultCount() {
    return resultCount;
  }

  public String getCreatedAt() {
    return createdAt;
  }

  public String getRelativeCreatedAt() {
    return Formatting.formatRelativeTime(createdAt);
  }

  public String getResultLabel() {
    return resultCount + (resultCount == 1 ? " source" : " sources");
  }
}
