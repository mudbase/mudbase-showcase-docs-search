using System.Text.Json.Serialization;

namespace MudbaseShowcase.DocsSearch.Models;

/// <summary>
/// Maps a document from the "search_log" Mudbase collection - one row per Ask AI question asked.
/// `UserId`/`UserName` are nullable: populated only when the asker was a real signed-in "customer"
/// (never a placeholder string for a guest) - mirrors web/src/types/document.ts's SearchLogRecord
/// and the reference AskAIPanel.tsx's conditional spread exactly.
/// </summary>
public sealed class SearchLogRecord
{
    [JsonPropertyName("_id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("queryText")]
    public string QueryText { get; set; } = string.Empty;

    [JsonPropertyName("userId")]
    public string? UserId { get; set; }

    [JsonPropertyName("userName")]
    public string? UserName { get; set; }

    [JsonPropertyName("resultCount")]
    public int ResultCount { get; set; }

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}
