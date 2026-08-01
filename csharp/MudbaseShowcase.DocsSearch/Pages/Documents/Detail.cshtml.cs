using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages.Documents;

/// <summary>Single document page: full content, author, tags, and author-only edit/delete. Mirrors web/src/app/documents/[id]/page.tsx's ownership check (`user.id === document.authorId`).</summary>
public sealed class DetailModel : PageModel
{
    private readonly DocumentsService _documents;
    private readonly MudbaseSessionAccessor _session;

    public DetailModel(DocumentsService documents, MudbaseSessionAccessor session)
    {
        _documents = documents;
        _session = session;
    }

    public DocumentRecord? Document { get; private set; }

    public bool IsOwner { get; private set; }

    public bool IsNotFound { get; private set; }

    public string? LoadError { get; private set; }

    [TempData]
    public string? FlashError { get; set; }

    public async Task OnGetAsync(string id, CancellationToken cancellationToken)
    {
        await LoadAsync(id, cancellationToken);
    }

    public async Task<IActionResult> OnPostDeleteAsync(string id, CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;
        DocumentRecord? document = await _documents.GetAsync(id, cancellationToken);
        if (document is null)
        {
            return RedirectToPage("/Index");
        }

        if (user is not { IsSignedIn: true } || user.Id != document.AuthorId)
        {
            FlashError = "You can only delete documents you authored.";
            return RedirectToPage(new { id });
        }

        try
        {
            await _documents.DeleteAsync(id, cancellationToken);
        }
        catch (MudbaseApiException ex)
        {
            FlashError = "Couldn't delete this document. (" + ex.Message + ")";
            return RedirectToPage(new { id });
        }

        return RedirectToPage("/Index");
    }

    private async Task LoadAsync(string id, CancellationToken cancellationToken)
    {
        MudbaseSessionUser? user = _session.CurrentUser;

        try
        {
            Document = await _documents.GetAsync(id, cancellationToken);
        }
        catch (MudbaseApiException ex)
        {
            LoadError = "This document isn't available right now. (" + ex.Message + ")";
            return;
        }

        if (Document is null)
        {
            IsNotFound = true;
            return;
        }

        IsOwner = user is { IsSignedIn: true } && user.Id == Document.AuthorId;
    }
}
