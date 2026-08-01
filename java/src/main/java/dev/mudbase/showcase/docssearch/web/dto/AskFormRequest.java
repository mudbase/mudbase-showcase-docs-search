package dev.mudbase.showcase.docssearch.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Field limits mirror the reference web app's {@code AskRequestSchema} (Zod) exactly. */
public class AskFormRequest {

  @NotBlank(message = "Question is required")
  @Size(max = 2000, message = "Question is too long")
  private String question = "";

  public String getQuestion() {
    return question;
  }

  public void setQuestion(String question) {
    this.question = question;
  }
}
