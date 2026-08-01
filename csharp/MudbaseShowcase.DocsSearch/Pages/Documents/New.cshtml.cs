using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages.Documents;

/// <summary>Create a document. Signed-in "customer" only - a guest anonymous session cannot reach this page's POST handler. Mirrors web/src/app/documents/new/page.tsx.</summary>
public sealed class NewModel : PageModel
{
    private readonly DocumentsService _documents;
    private readonly MudbaseSessionAccessor _session;

    public NewModel(DocumentsService documents, MudbaseSessionAccessor session)
    {
        _documents = documents;
        _session = session;
    }

    [BindProperty]
    public DocumentInput Input { get; set; } = new();

    public string? ErrorMessage { get; private set; }

    public bool IsSignedIn => _session.CurrentUser is { IsSignedIn: true };

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        if (user is not { IsSignedIn: true })
        {
            return RedirectToPage("/Login", new { ReturnUrl = "/Documents/New" });
        }

        if (!ModelState.IsValid)
        {
            return Page();
        }

        try
        {
            DocumentRecord created = await _documents.CreateAsync(
                Input.Title, Input.Content, Input.Tags, user.Id, user.DisplayName, cancellationToken);
            return RedirectToPage("/Documents/Detail", new { id = created.Id });
        }
        catch (MudbaseApiException ex)
        {
            ErrorMessage = "Couldn't create the document. (" + ex.Message + ")";
            return Page();
        }
    }

    public sealed class DocumentInput
    {
        [Required(ErrorMessage = "Title is required"), StringLength(200, ErrorMessage = "Title is too long")]
        public string Title { get; set; } = string.Empty;

        [Required(ErrorMessage = "Content is required"), StringLength(50000, ErrorMessage = "Content is too long")]
        public string Content { get; set; } = string.Empty;

        [StringLength(500, ErrorMessage = "Tags are too long")]
        public string? Tags { get; set; }
    }
}
