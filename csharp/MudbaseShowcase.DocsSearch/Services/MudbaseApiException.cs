using System.Net;
using System.Text.Json;
using Mudbase.Sdk.Client;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// Thrown when a Mudbase SDK call returns a non-success status this app doesn't have a more
/// specific recovery path for. Carries the HTTP status and a best-effort human-readable message
/// extracted from the response body, mirroring the reference app's MudbaseError
/// (web/src/lib/mudbase.ts): try `error`, then `message`, then fall back to the status code.
/// </summary>
public sealed class MudbaseApiException : Exception
{
    public HttpStatusCode StatusCode { get; }

    private MudbaseApiException(HttpStatusCode statusCode, string message) : base(message)
    {
        StatusCode = statusCode;
    }

    public static MudbaseApiException From(IApiResponse response) =>
        new(response.StatusCode, ExtractMessage(response.RawContent, response.StatusCode));

    private static string ExtractMessage(string rawContent, HttpStatusCode statusCode)
    {
        if (!string.IsNullOrWhiteSpace(rawContent))
        {
            try
            {
                using JsonDocument doc = JsonDocument.Parse(rawContent);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                {
                    if (doc.RootElement.TryGetProperty("error", out JsonElement errorProp) &&
                        errorProp.ValueKind == JsonValueKind.String)
                    {
                        return errorProp.GetString() ?? DefaultMessage(statusCode);
                    }

                    if (doc.RootElement.TryGetProperty("message", out JsonElement messageProp) &&
                        messageProp.ValueKind == JsonValueKind.String)
                    {
                        return messageProp.GetString() ?? DefaultMessage(statusCode);
                    }
                }
            }
            catch (JsonException)
            {
                // Body wasn't JSON (or wasn't an object) - fall through to the generic message below.
            }
        }

        return DefaultMessage(statusCode);
    }

    private static string DefaultMessage(HttpStatusCode statusCode) => $"Mudbase request failed ({(int)statusCode} {statusCode}).";
}
