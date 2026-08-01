using System.Text.Json;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// A single, dedicated JsonSerializerOptions for everything this app parses/writes itself:
/// document bodies unwrapped from the SDK's untyped `Object`/JsonElement response fields,
/// TokenRefreshHandler's raw refresh-endpoint payloads, and FunctionInvocationService's/
/// LlmService's raw HTTP request/response bodies. Deliberately independent of the SDK's own
/// JsonSerializerOptionsProvider (which carries its own converters for the SDK's generated models)
/// so our own POCOs never pick up an unrelated converter by accident - every property on our
/// POCOs is mapped explicitly with [JsonPropertyName], so case-insensitivity here is a safety net,
/// not a requirement.
/// </summary>
public static class MudbaseJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = false,
    };
}
