package dev.mudbase.showcase.docssearch.domain;

import dev.mudbase.showcase.docssearch.mudbase.DocumentMapper;
import dev.mudbase.showcase.docssearch.support.Formatting;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Mirrors the `documents` collection - see plan/build-plan.md in the reference web app. */
public class DocumentRecord {

  private final String id;
  private final String title;
  private final String content;
  private final String tags;
  private final String authorId;
  private final String authorName;
  private final String createdAt;

  public DocumentRecord(
      String id, String title, String content, String tags, String authorId, String authorName, String createdAt) {
    this.id = id;
    this.title = title;
    this.content = content;
    this.tags = tags;
    this.authorId = authorId;
    this.authorName = authorName;
    this.createdAt = createdAt;
  }

  public static DocumentRecord fromDocument(Map<String, Object> doc) {
    return new DocumentRecord(
        DocumentMapper.getId(doc),
        DocumentMapper.getString(doc, "title"),
        DocumentMapper.getString(doc, "content"),
        DocumentMapper.getString(doc, "tags"),
        DocumentMapper.getString(doc, "authorId"),
        DocumentMapper.getString(doc, "authorName"),
        DocumentMapper.getString(doc, "createdAt"));
  }

  /** A new, unsaved document ready for {@code createDocument} - see DocumentService. */
  public static Map<String, Object> toCreateBody(String title, String content, String tags, String authorId, String authorName) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("title", title);
    body.put("content", content);
    body.put("tags", tags != null ? tags : "");
    body.put("authorId", authorId);
    body.put("authorName", authorName);
    return body;
  }

  /** Fields writable on an existing document via {@code updateDocument} - authorship never changes. */
  public static Map<String, Object> toUpdateBody(String title, String content, String tags) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("title", title);
    body.put("content", content);
    body.put("tags", tags != null ? tags : "");
    return body;
  }

  public String getId() {
    return id;
  }

  public String getTitle() {
    return title;
  }

  public String getContent() {
    return content;
  }

  public String getTags() {
    return tags;
  }

  public String getAuthorId() {
    return authorId;
  }

  public String getAuthorName() {
    return authorName;
  }

  public String getCreatedAt() {
    return createdAt;
  }

  public boolean isOwnedBy(String userId) {
    return userId != null && userId.equals(authorId);
  }

  /** Short plain-text preview for library-card rendering - mirrors {@code snippet()} in utils.ts. */
  public String getSnippet() {
    return Formatting.snippet(content);
  }

  /** Parsed, trimmed tag list for template rendering - mirrors {@code parseTags()} in utils.ts. */
  public List<String> getTagList() {
    return Formatting.parseTags(tags);
  }

  public String getRelativeCreatedAt() {
    return Formatting.formatRelativeTime(createdAt);
  }

  public String getFormattedCreatedAt() {
    return Formatting.formatDateTime(createdAt);
  }
}
