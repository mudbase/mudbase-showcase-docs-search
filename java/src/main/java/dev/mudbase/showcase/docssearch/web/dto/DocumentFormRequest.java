package dev.mudbase.showcase.docssearch.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Field limits mirror the reference web app's {@code documentFormSchema} (Zod) exactly. */
public class DocumentFormRequest {

  @NotBlank(message = "Title is required")
  @Size(max = 200, message = "Title is too long")
  private String title = "";

  @NotBlank(message = "Content is required")
  @Size(max = 50_000, message = "Content is too long")
  private String content = "";

  @Size(max = 500, message = "Tags are too long")
  private String tags = "";

  public String getTitle() {
    return title;
  }

  public void setTitle(String title) {
    this.title = title;
  }

  public String getContent() {
    return content;
  }

  public void setContent(String content) {
    this.content = content;
  }

  public String getTags() {
    return tags;
  }

  public void setTags(String tags) {
    this.tags = tags;
  }
}
