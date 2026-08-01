using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;
using MudbaseShowcase.DocsSearch.Options;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>One document Mudbase's docsAskRetrieval Function scored above zero, with the score it assigned.</summary>
public sealed class FunctionCitation
{
    [JsonPropertyName("documentId")]
    public string DocumentId { get; set; } = string.Empty;

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("score")]
    public double Score { get; set; }
}

/// <summary>The docsAskRetrieval Function's own return value, once its execution status is "success".</summary>
public sealed class RetrievalResult
{
    [JsonPropertyName("contextBlock")]
    public string ContextBlock { get; set; } = string.Empty;

    [JsonPropertyName("citations")]
    public List<FunctionCitation> Citations { get; set; } = new();

    [JsonPropertyName("usedCount")]
    public int UsedCount { get; set; }
}

/// <summary>
/// Invokes the deployed Mudbase Function ("docsAskRetrieval", id in MudbaseOptions.FunctionId) that
/// ranks candidate documents by keyword overlap and assembles a grounded context block - the
/// retrieval-ranking work the Function's isolated-vm sandbox *can* do, since it has zero network
/// access (see plan/build-plan.md "Ask AI architecture"). This app's DataApi/AuthenticationApi
/// calls all go through the generated Mudbase SDK using SessionBearerTokenProvider's per-request
/// JWT - but a Function's /execute route requires an org-scoped `ak_` API key with a "functions"
/// permission grant a project end-user's own JWT (org role always "viewer") can never satisfy. That
/// is a completely different credential and a completely different auth scheme (a static X-API-Key
/// header, not a per-session Bearer token) from every other call in this app, so this service uses
/// a plain, handler-free named HttpClient ("MudbaseRaw") instead of trying to register a second
/// token kind into the SDK's single-token-per-type DI wiring - mirroring the reference web app's
/// own choice to bypass its Mudbase SDK client for this exact call too
/// (web/src/lib/server/functionInvoke.ts uses a raw `fetch`, not its MudbaseClient).
///
/// MudbaseOptions.FunctionsApiKey must never reach a page, a log line, or a client asset.
/// </summary>
public sealed class FunctionInvocationService
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(600);
    private static readonly TimeSpan PollTimeout = TimeSpan.FromSeconds(20);

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly MudbaseOptions _options;

    public FunctionInvocationService(IHttpClientFactory httpClientFactory, IOptions<MudbaseOptions> options)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value;
    }

    public async Task<RetrievalResult> InvokeAsync(
        string question, IReadOnlyList<RetrievalCandidate> candidates, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.FunctionId) || string.IsNullOrWhiteSpace(_options.FunctionsApiKey))
        {
            throw new AskAiException(
                "Missing required server-only configuration: Mudbase:FunctionId / Mudbase:FunctionsApiKey. " +
                "See README.md \"Provisioning\"/\"LLM setup\" and appsettings.Example.json.");
        }

        HttpClient client = _httpClientFactory.CreateClient(HttpClientNames.MudbaseRaw);

        // Built as nested Dictionary<string, object?> (matching this app's other Mudbase write
        // calls) rather than a strongly-typed anonymous object, so a candidate's optional `tags`
        // key is omitted entirely when absent instead of serializing as an explicit JSON null -
        // matching the reference app's own conditional spread in src/lib/retrieval.ts's topCandidates.
        List<Dictionary<string, object?>> candidatePayloads = candidates.Select(candidate =>
        {
            var payload = new Dictionary<string, object?>
            {
                ["documentId"] = candidate.DocumentId,
                ["title"] = candidate.Title,
                ["content"] = candidate.Content,
            };
            if (!string.IsNullOrEmpty(candidate.Tags))
            {
                payload["tags"] = candidate.Tags;
            }

            return payload;
        }).ToList();

        var executeBody = new Dictionary<string, object?>
        {
            ["payload"] = new Dictionary<string, object?>
            {
                ["question"] = question,
                ["candidates"] = candidatePayloads,
            },
        };

        using HttpRequestMessage executeRequest = new(
            HttpMethod.Post, $"/api/functions/projects/{_options.ProjectId}/functions/{_options.FunctionId}/execute")
        {
            Content = JsonContent.Create(executeBody, options: MudbaseJson.Options),
        };
        executeRequest.Headers.Add("X-API-Key", _options.FunctionsApiKey);

        using HttpResponseMessage executeResponse = await client.SendAsync(executeRequest, cancellationToken).ConfigureAwait(false);
        string executeResponseBody = await executeResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        ExecuteResponsePayload? executed = TryParse<ExecuteResponsePayload>(executeResponseBody);

        if (!executeResponse.IsSuccessStatusCode || executed?.Success != true || executed.Data is null)
        {
            throw new AskAiException(
                $"Mudbase Function execute request failed ({(int)executeResponse.StatusCode}): {executed?.Error ?? "unknown error"}");
        }

        string executionId = executed.Data.ExecutionId;
        string pollPath = $"/api/functions/projects/{_options.ProjectId}/functions/{_options.FunctionId}/executions/{executionId}";
        DateTime deadline = DateTime.UtcNow + PollTimeout;

        while (DateTime.UtcNow < deadline)
        {
            using HttpRequestMessage pollRequest = new(HttpMethod.Get, pollPath);
            pollRequest.Headers.Add("X-API-Key", _options.FunctionsApiKey);

            using HttpResponseMessage pollResponse = await client.SendAsync(pollRequest, cancellationToken).ConfigureAwait(false);
            string pollResponseBody = await pollResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            ExecutionStatusPayload? status = TryParse<ExecutionStatusPayload>(pollResponseBody);

            if (!pollResponse.IsSuccessStatusCode || status?.Success != true || status.Data is null)
            {
                throw new AskAiException($"Mudbase Function execution poll failed ({(int)pollResponse.StatusCode})");
            }

            if (status.Data.Status == "success")
            {
                if (status.Data.Result is null)
                {
                    throw new AskAiException("Function execution succeeded but returned no result");
                }

                return status.Data.Result;
            }

            if (status.Data.Status is "failed" or "timeout")
            {
                throw new AskAiException($"Mudbase Function execution {status.Data.Status}: {status.Data.Error ?? "unknown error"}");
            }

            await Task.Delay(PollInterval, cancellationToken).ConfigureAwait(false);
        }

        throw new AskAiException("Timed out waiting for the Mudbase Function execution to complete");
    }

    private static T? TryParse<T>(string json) where T : class
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            return JsonSerializer.Deserialize<T>(json, MudbaseJson.Options);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private sealed class ExecuteResponsePayload
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("data")]
        public ExecuteResponseData? Data { get; set; }

        [JsonPropertyName("error")]
        public string? Error { get; set; }
    }

    private sealed class ExecuteResponseData
    {
        [JsonPropertyName("executionId")]
        public string ExecutionId { get; set; } = string.Empty;

        [JsonPropertyName("status")]
        public string Status { get; set; } = string.Empty;
    }

    private sealed class ExecutionStatusPayload
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("data")]
        public ExecutionStatusData? Data { get; set; }

        [JsonPropertyName("error")]
        public string? Error { get; set; }
    }

    private sealed class ExecutionStatusData
    {
        [JsonPropertyName("status")]
        public string Status { get; set; } = string.Empty;

        [JsonPropertyName("result")]
        public RetrievalResult? Result { get; set; }

        [JsonPropertyName("error")]
        public string? Error { get; set; }
    }
}
