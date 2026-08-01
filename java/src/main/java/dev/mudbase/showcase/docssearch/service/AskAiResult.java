package dev.mudbase.showcase.docssearch.service;

import dev.mudbase.showcase.docssearch.askai.Citation;
import java.util.List;

/**
 * Outcome of one Ask AI question, rendered by {@code ask/panel.html}. A plain class with
 * JavaBean getters (not a record) so Thymeleaf's SpringEL property access ({@code
 * ${askResult.noMatch}}) resolves reliably. {@code noMatch} mirrors the reference web app's
 * {@code AskAIPanel.tsx}: when keyword scoring finds zero candidate documents, the question is
 * logged with {@code resultCount: 0} and neither the Mudbase Function nor the Anthropic API is
 * ever called.
 */
public class AskAiResult {

  private final boolean noMatch;
  private final String answer;
  private final List<Citation> citations;

  private AskAiResult(boolean noMatch, String answer, List<Citation> citations) {
    this.noMatch = noMatch;
    this.answer = answer;
    this.citations = citations;
  }

  public static AskAiResult noMatch() {
    return new AskAiResult(true, null, List.of());
  }

  public static AskAiResult answered(String answer, List<Citation> citations) {
    return new AskAiResult(false, answer, citations);
  }

  public boolean isNoMatch() {
    return noMatch;
  }

  public String getAnswer() {
    return answer;
  }

  public List<Citation> getCitations() {
    return citations;
  }
}
