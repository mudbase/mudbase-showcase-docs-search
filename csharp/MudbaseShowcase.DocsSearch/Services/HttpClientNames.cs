namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>Named HttpClient identifiers used outside the Mudbase SDK's own generated typed clients.</summary>
public static class HttpClientNames
{
    /// <summary>
    /// Direct, handler-free HTTP access to the Mudbase base URL - used by
    /// <see cref="TokenRefreshHandler"/>'s POST /api/auth/refresh call (so a refresh can never
    /// recurse through its own 401-retry pipeline) and by
    /// <see cref="FunctionInvocationService"/>'s raw execute/poll calls against the Mudbase
    /// Functions REST API, which authenticate with a completely different credential (an
    /// org-scoped `ak_` API key, not the per-session Bearer JWT the generated SDK's Apis use).
    /// </summary>
    public const string MudbaseRaw = "MudbaseRaw";

    /// <summary>Dedicated named HttpClient for the one third-party call in this app: LlmService's Anthropic Claude completion request.</summary>
    public const string Anthropic = "Anthropic";
}
