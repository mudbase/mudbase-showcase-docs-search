namespace MudbaseShowcase.DocsSearch.Options;

/// <summary>
/// Every config value this app needs to talk to a provisioned Mudbase project, plus the two
/// server-only credentials the Ask AI flow needs (see plan/build-plan.md "Ask AI architecture").
/// Bound from the "Mudbase" section of appsettings.json / environment variables - see
/// appsettings.Example.json at the repo root for the full list with descriptions.
/// </summary>
public sealed class MudbaseOptions
{
    public const string SectionName = "Mudbase";

    /// <summary>Mudbase API base URL. Defaults to the public cloud endpoint.</summary>
    public string BaseUrl { get; set; } = "https://cloud.mudbase.dev";

    /// <summary>The Mudbase project ID this app is provisioned against.</summary>
    public string ProjectId { get; set; } = string.Empty;

    /// <summary>Collection ID for the "documents" collection.</summary>
    public string DocumentsCollectionId { get; set; } = string.Empty;

    /// <summary>Collection ID for the "search_log" collection.</summary>
    public string SearchLogCollectionId { get; set; } = string.Empty;

    /// <summary>The _id of the deployed "docsAskRetrieval" Function in this project. Not a secret by itself, but validated lazily (see below) rather than at startup, since Ask AI is one feature among several.</summary>
    public string FunctionId { get; set; } = string.Empty;

    /// <summary>
    /// SECRET. An org-scoped `ak_` API key permissioned only for "functions" (create+read),
    /// authorizing <see cref="Services.FunctionInvocationService"/>'s calls - a project end-user
    /// JWT can never invoke a Function (org role is always "viewer" for a project end-user, which
    /// only satisfies functions:read, not the functions:create the /execute route requires - see
    /// plan/build-plan.md). Deliberately NOT required by <see cref="Validate"/>: mirrors the
    /// reference web app's functionInvoke.ts, which checks this lazily, at call time, only when an
    /// Ask AI request actually reaches this step - so a deployment missing it can still serve
    /// every other page. Never logged, never rendered to a page, never committed to source control.
    /// </summary>
    public string FunctionsApiKey { get; set; } = string.Empty;

    /// <summary>
    /// SECRET. Anthropic Claude API key, used only by <see cref="Services.LlmService"/> - the one
    /// third-party network call in this app, made here because the Mudbase Function's own sandbox
    /// has zero network access (see plan/build-plan.md). Deliberately NOT required by
    /// <see cref="Validate"/> for the same lazy-check reason as <see cref="FunctionsApiKey"/> -
    /// LlmService throws a clear "ANTHROPIC_API_KEY is not configured" error only when an Ask AI
    /// request actually reaches the completion step, matching web/src/lib/server/llm.ts exactly.
    /// </summary>
    public string AnthropicApiKey { get; set; } = string.Empty;

    /// <summary>Anthropic model id. Defaults to claude-opus-5 if unset - same default as the reference web app.</summary>
    public string LlmModel { get; set; } = "claude-opus-5";

    /// <summary>
    /// Throws with a clear, specific message if any *required-to-boot* value was left unset, so a
    /// misconfigured deployment fails at startup instead of surfacing confusing errors deep inside
    /// a request handler. FunctionsApiKey/FunctionId/AnthropicApiKey are intentionally excluded -
    /// see their doc comments above.
    /// </summary>
    public void Validate()
    {
        var missing = new List<string>();

        if (string.IsNullOrWhiteSpace(BaseUrl)) missing.Add(nameof(BaseUrl));
        if (string.IsNullOrWhiteSpace(ProjectId)) missing.Add(nameof(ProjectId));
        if (string.IsNullOrWhiteSpace(DocumentsCollectionId)) missing.Add(nameof(DocumentsCollectionId));
        if (string.IsNullOrWhiteSpace(SearchLogCollectionId)) missing.Add(nameof(SearchLogCollectionId));

        if (missing.Count > 0)
        {
            throw new InvalidOperationException(
                $"Missing required Mudbase configuration values: {string.Join(", ", missing)}. " +
                "Set them under the \"Mudbase\" section of appsettings.json, appsettings.Development.json, " +
                "or the corresponding Mudbase__<Key> environment variables. See appsettings.Example.json. " +
                "(FunctionsApiKey/FunctionId/AnthropicApiKey are validated lazily, only when Ask AI is actually used.)");
        }
    }
}
