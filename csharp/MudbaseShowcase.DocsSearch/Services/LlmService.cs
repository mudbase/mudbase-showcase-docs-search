using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;
using MudbaseShowcase.DocsSearch.Options;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// The one place in this codebase that calls a third-party LLM API. MudbaseOptions.AnthropicApiKey
/// is a server-only config value - it is never rendered to a page, never logged, never committed.
/// See plan/build-plan.md "Ask AI architecture" for why this call happens in a plain service class
/// rather than inside the Mudbase Function itself: the Function's isolated-vm sandbox has zero
/// network primitives (no outbound HTTP of any kind), so it structurally cannot reach an LLM
/// provider. This app is itself entirely server-rendered - every Razor Page handler already runs
/// server-side - so this service call from Pages/Ask.cshtml.cs's OnPostAskAsync already *is* the
/// smallest possible server-side surface; unlike the Next.js reference, no separate API route
/// needs to be carved out for it.
///
/// Calls the Anthropic Messages API directly over HTTP (no unofficial third-party NuGet package -
/// Anthropic does not publish an official C# SDK) - the same request/response contract as the
/// reference app's @anthropic-ai/sdk usage in web/src/lib/server/llm.ts, including its exact system
/// prompt, default model, and refusal handling.
/// </summary>
public sealed class LlmService
{
    private const string AnthropicMessagesUrl = "https://api.anthropic.com/v1/messages";
    private const string AnthropicVersion = "2023-06-01";
    private const string DefaultModel = "claude-opus-5";
    private const int MaxTokens = 1024;

    private const string SystemPrompt =
        "You are a support assistant for a documentation knowledge base. Answer the user's " +
        "question using ONLY the document excerpts provided below - never your own outside knowledge. If the " +
        "excerpts do not contain enough information to answer, say so plainly rather than guessing. Keep the " +
        "answer concise (a few sentences to a short paragraph). When you use a fact from an excerpt, mention " +
        "which document it came from by its title.";

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly MudbaseOptions _options;

    public LlmService(IHttpClientFactory httpClientFactory, IOptions<MudbaseOptions> options)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value;
    }

    public async Task<string> GenerateGroundedAnswerAsync(string question, string contextBlock, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.AnthropicApiKey))
        {
            throw new AskAiException(
                "ANTHROPIC_API_KEY is not configured. This is a server-only config value (see README.md " +
                "\"LLM setup\" and appsettings.Example.json) - the developer running this app must supply their own key.");
        }

        string model = string.IsNullOrWhiteSpace(_options.LlmModel) ? DefaultModel : _options.LlmModel;

        string userContent = contextBlock.Trim().Length > 0
            ? $"Question: {question}\n\nDocument excerpts:\n{contextBlock}"
            : $"Question: {question}\n\n(No document excerpts were retrieved - say you don't have enough information in the knowledge base to answer.)";

        var requestBody = new Dictionary<string, object?>
        {
            ["model"] = model,
            ["max_tokens"] = MaxTokens,
            ["system"] = SystemPrompt,
            ["messages"] = new[]
            {
                new Dictionary<string, object?> { ["role"] = "user", ["content"] = userContent },
            },
        };

        HttpClient client = _httpClientFactory.CreateClient(HttpClientNames.Anthropic);

        using HttpRequestMessage request = new(HttpMethod.Post, AnthropicMessagesUrl)
        {
            Content = JsonContent.Create(requestBody, options: MudbaseJson.Options),
        };
        request.Headers.Add("x-api-key", _options.AnthropicApiKey);
        request.Headers.Add("anthropic-version", AnthropicVersion);

        using HttpResponseMessage response = await client.SendAsync(request, cancellationToken).ConfigureAwait(false);
        string body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);

        if (!response.IsSuccessStatusCode)
        {
            throw new AskAiException($"Anthropic API request failed ({(int)response.StatusCode}): {ExtractErrorMessage(body)}");
        }

        AnthropicMessageResponse? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<AnthropicMessageResponse>(body, MudbaseJson.Options);
        }
        catch (JsonException ex)
        {
            throw new AskAiException("The model returned a response that couldn't be parsed", ex);
        }

        AnthropicContentBlock? textBlock = parsed?.Content?.FirstOrDefault(block => block.Type == "text");
        if (textBlock?.Text is not { Length: > 0 } text)
        {
            if (parsed?.StopReason == "refusal")
            {
                throw new AskAiException("The model declined to answer this question.");
            }

            throw new AskAiException("The model returned no text content");
        }

        return text;
    }

    private static string ExtractErrorMessage(string body)
    {
        try
        {
            using JsonDocument doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("error", out JsonElement errorEl) &&
                errorEl.TryGetProperty("message", out JsonElement messageEl) &&
                messageEl.ValueKind == JsonValueKind.String)
            {
                return messageEl.GetString() ?? "unknown error";
            }
        }
        catch (JsonException)
        {
            // Body wasn't JSON (or wasn't shaped as expected) - fall through to the generic message below.
        }

        return "unknown error";
    }

    private sealed class AnthropicMessageResponse
    {
        [JsonPropertyName("content")]
        public List<AnthropicContentBlock>? Content { get; set; }

        [JsonPropertyName("stop_reason")]
        public string? StopReason { get; set; }
    }

    private sealed class AnthropicContentBlock
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = string.Empty;

        [JsonPropertyName("text")]
        public string? Text { get; set; }
    }
}
