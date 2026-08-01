using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages.Documents;

/// <summary>Edit a document - author only, both defensively here and enforced server-side by Mudbase's own collection permissions. Mirrors web/src/app/documents/[id]/edit/page.tsx.</summary>
public sealed class EditModel : PageModel
{
    private readonly DocumentsService _documents;
    private readonly MudbaseSessionAccessor _session;

    public EditModel(DocumentsService documents, MudbaseSessionAccessor session)
    {
        _documents = documents;
        _session = session;
    }

    [BindProperty]
    public DocumentInput Input { get; set; } = new();

    public string? ErrorMessage { get; private set; }

    public bool IsOwner { get; private set; }

    public bool IsNotFound { get; private set; }

    public string? LoadError { get; private set; }

    public async Task OnGetAsync(string id, CancellationToken cancellationToken)
    {
        DocumentRecord? document = await FetchDocumentAsync(id, cancellationToken);
        if (LoadError is not null || document is null)
        {
            return;
        }

        MudbaseSessionUser? user = _session.CurrentUser;
        IsOwner = user is { IsSignedIn: true } && user.Id == document.AuthorId;
        Input = new DocumentInput { Title = document.Title, Content = document.Content, Tags = document.Tags };
    }

    public async Task<IActionResult> OnPostAsync(string id, CancellationToken cancellationToken)
    {
        DocumentRecord? document = await FetchDocumentAsync(id, cancellationToken);
        if (LoadError is not null || document is null)
        {
            return Page();
        }

        MudbaseSessionUser? user = _session.CurrentUser;
        IsOwner = user is { IsSignedIn: true } && user.Id == document.AuthorId;
        if (!IsOwner)
        {
            return Page();
        }

        if (!ModelState.IsValid)
        {
            return Page();
        }

        try
        {
            await _documents.UpdateAsync(id, Input.Title, Input.Content, Input.Tags, cancellationToken);
            return RedirectToPage("/Documents/Detail", new { id });
        }
        catch (MudbaseApiException ex)
        {
            ErrorMessage = "Couldn't update the document. (" + ex.Message + ")";
            return Page();
        }
    }

    private async Task<DocumentRecord?> FetchDocumentAsync(string id, CancellationToken cancellationToken)
    {
        try
        {
            DocumentRecord? document = await _documents.GetAsync(id, cancellationToken);
            if (document is null)
            {
                IsNotFound = true;
            }

            return document;
        }
        catch (MudbaseApiException ex)
        {
            LoadError = "This document isn't available right now. (" + ex.Message + ")";
            return null;
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
