package dev.mudbase.showcase.docssearch.config;

import jakarta.annotation.PostConstruct;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Every Mudbase-side identifier this app needs: the project itself, its two collections
 * (documents/search_log), and the deployed {@code docsAskRetrieval} Function's id plus the
 * org-scoped {@code ak_} API key that authorizes invoking it. See java/.env.example for the full
 * list and where each value comes from, and plan/build-plan.md "Ask AI architecture" for why the
 * Function needs its own separate API key rather than reusing the project's {@code pk_} key - a
 * project end-user JWT (org role always "viewer") can never satisfy {@code
 * rbacCheck("functions","create")}, which the {@code /execute} route requires.
 *
 * <p>None of these five values are secret in the sense of granting account takeover, but {@code
 * functionsApiKey} specifically must never be sent to a browser (see {@link
 * dev.mudbase.showcase.docssearch.askai.FunctionInvokeClient}) - kept here as a server-only Spring
 * property, same as every other value in this class.
 */
@ConfigurationProperties(prefix = "mudbase")
public class MudbaseProperties {

  private String baseUrl;
  private String projectId;
  private String documentsCollectionId;
  private String searchLogCollectionId;
  private String functionId;
  private String functionsApiKey;

  @PostConstruct
  void validate() {
    requireNonBlank(projectId, "mudbase.project-id (MUDBASE_PROJECT_ID)");
    requireNonBlank(documentsCollectionId, "mudbase.documents-collection-id (MUDBASE_DOCUMENTS_COLLECTION_ID)");
    requireNonBlank(searchLogCollectionId, "mudbase.search-log-collection-id (MUDBASE_SEARCH_LOG_COLLECTION_ID)");
    requireNonBlank(functionId, "mudbase.function-id (MUDBASE_FUNCTION_ID)");
    requireNonBlank(functionsApiKey, "mudbase.functions-api-key (MUDBASE_FUNCTIONS_API_KEY)");
  }

  private static void requireNonBlank(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalStateException("Missing required configuration value: " + name);
    }
  }

  public String getBaseUrl() {
    return baseUrl;
  }

  public void setBaseUrl(String baseUrl) {
    this.baseUrl = baseUrl;
  }

  public String getProjectId() {
    return projectId;
  }

  public void setProjectId(String projectId) {
    this.projectId = projectId;
  }

  public String getDocumentsCollectionId() {
    return documentsCollectionId;
  }

  public void setDocumentsCollectionId(String documentsCollectionId) {
    this.documentsCollectionId = documentsCollectionId;
  }

  public String getSearchLogCollectionId() {
    return searchLogCollectionId;
  }

  public void setSearchLogCollectionId(String searchLogCollectionId) {
    this.searchLogCollectionId = searchLogCollectionId;
  }

  public String getFunctionId() {
    return functionId;
  }

  public void setFunctionId(String functionId) {
    this.functionId = functionId;
  }

  public String getFunctionsApiKey() {
    return functionsApiKey;
  }

  public void setFunctionsApiKey(String functionsApiKey) {
    this.functionsApiKey = functionsApiKey;
  }
}
