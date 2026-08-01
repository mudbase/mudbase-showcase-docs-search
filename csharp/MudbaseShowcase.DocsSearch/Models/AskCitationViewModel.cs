namespace MudbaseShowcase.DocsSearch.Models;

/// <summary>One source document citation rendered under an Ask AI answer - mirrors web/src/lib/ask-schema.ts's AskCitationSchema.</summary>
public sealed class AskCitationViewModel
{
    public required string DocumentId { get; init; }
    public required string Title { get; init; }
}
