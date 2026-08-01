using System.Text.Json.Serialization;

namespace MudbaseShowcase.DocsSearch.Models;

/// <summary>
/// Maps a document from the "documents" Mudbase collection. Field names mirror the reference
/// Next.js implementation's schema exactly (see web/src/types/document.ts's DocumentRecord) so
/// this is a faithful port, not a reinterpretation. `Tags` is a comma-separated string (e.g.
/// "billing,invoices"), not an array - same as the reference.
/// </summary>
public sealed class DocumentRecord
{
    [JsonPropertyName("_id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("content")]
    public string Content { get; set; } = string.Empty;

    [JsonPropertyName("tags")]
    public string? Tags { get; set; }

    [JsonPropertyName("authorId")]
    public string AuthorId { get; set; } = string.Empty;

    [JsonPropertyName("authorName")]
    public string AuthorName { get; set; } = string.Empty;

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; set; }
}
