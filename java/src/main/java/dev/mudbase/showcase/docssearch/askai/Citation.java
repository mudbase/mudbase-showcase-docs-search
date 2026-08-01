package dev.mudbase.showcase.docssearch.askai;

/**
 * One document the Mudbase Function's retrieval ranking used to build the context block. A plain
 * class with JavaBean getters (not a record) so Thymeleaf's SpringEL property access ({@code
 * ${citation.title}}) resolves reliably regardless of the Spring Framework version's level of
 * record-accessor support.
 */
public class Citation {

  private final String documentId;
  private final String title;
  private final int score;

  public Citation(String documentId, String title, int score) {
    this.documentId = documentId;
    this.title = title;
    this.score = score;
  }

  public String getDocumentId() {
    return documentId;
  }

  public String getTitle() {
    return title;
  }

  public int getScore() {
    return score;
  }
}
