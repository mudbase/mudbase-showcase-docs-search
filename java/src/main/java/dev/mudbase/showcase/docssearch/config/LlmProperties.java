package dev.mudbase.showcase.docssearch.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuration for the one third-party LLM call this app makes - see {@link
 * dev.mudbase.showcase.docssearch.askai.AnthropicClient} and plan/build-plan.md "Ask AI
 * architecture" for why this call cannot happen inside the Mudbase Function itself.
 *
 * <p>Deliberately NOT validated at startup with {@code @PostConstruct} the way {@link
 * MudbaseProperties} is: {@code apiKey} is allowed to be blank so this app can start and serve
 * every other page (library, search, document CRUD) without a real Anthropic key configured -
 * only the Ask AI completion call itself fails, with a clear "ANTHROPIC_API_KEY is not
 * configured" error, exactly mirroring the reference web app's {@code
 * src/lib/server/llm.ts} behavior and its own honestly-documented "no real key available in this
 * build/test environment" limitation.
 */
@ConfigurationProperties(prefix = "llm")
public class LlmProperties {

  private static final String DEFAULT_MODEL = "claude-opus-5";

  private String apiKey;
  private String model = DEFAULT_MODEL;

  public String getApiKey() {
    return apiKey;
  }

  public void setApiKey(String apiKey) {
    this.apiKey = apiKey;
  }

  public boolean hasApiKey() {
    return apiKey != null && !apiKey.isBlank();
  }

  public String getModel() {
    return model == null || model.isBlank() ? DEFAULT_MODEL : model;
  }

  public void setModel(String model) {
    this.model = model;
  }
}
