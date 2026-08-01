using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages;

/// <summary>Document library: a GET-bound search box (server-side substring match across title/content/tags, since this app has no client-side JS) plus a grid of document cards. Mirrors web/src/app/page.tsx.</summary>
public sealed class IndexModel : PageModel
{
    private const int ListLimit = 100;

    private readonly DocumentsService _documents;

    public IndexModel(DocumentsService documents)
    {
        _documents = documents;
    }

    public IReadOnlyList<DocumentRecord> Documents { get; private set; } = Array.Empty<DocumentRecord>();

    /// <summary>The search box's current value - a GET query parameter (`?Q=...`) so the search itself is a normal, bookmarkable page load, not an XHR call.</summary>
    [BindProperty(SupportsGet = true)]
    public string? Q { get; set; }

    public string? LoadError { get; private set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        try
        {
            MudbaseListResult<DocumentRecord> result = await _documents.ListAsync(ListLimit, cancellationToken);
            string term = Q ?? string.Empty;
            Documents = result.Items.Where(document => RetrievalHelpers.MatchesSearchTerm(document, term)).ToList();
        }
        catch (MudbaseApiException ex)
        {
            LoadError = "Couldn't load the document library right now. Try refreshing. (" + ex.Message + ")";
        }
    }
}
