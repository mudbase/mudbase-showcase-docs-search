using Microsoft.Extensions.Options;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Options;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>Document CRUD - direct port of web/src/hooks/useCollection.ts's server calls (minus the client-side cache bookkeeping, which a server-rendered page doesn't need). Any signed-in "customer" may create; edit/delete are gated to the document's own author both here (defensively, in Pages/Documents/*) and by Mudbase's own collection permissions.</summary>
public sealed class DocumentsService
{
    private readonly MudbaseDataService _data;
    private readonly MudbaseOptions _options;

    public DocumentsService(MudbaseDataService data, IOptions<MudbaseOptions> options)
    {
        _data = data;
        _options = options.Value;
    }

    /// <summary>Newest-first. `limit` is caller-supplied because the library page (100) and the Ask AI candidate pool (200) use different windows, mirroring the reference app's two separate useDocuments() calls.</summary>
    public Task<MudbaseListResult<DocumentRecord>> ListAsync(int limit, CancellationToken cancellationToken) =>
        _data.ListAsync<DocumentRecord>(_options.DocumentsCollectionId, sort: "-createdAt", page: 1, limit: limit, cancellationToken: cancellationToken);

    public Task<DocumentRecord?> GetAsync(string documentId, CancellationToken cancellationToken) =>
        _data.GetAsync<DocumentRecord>(_options.DocumentsCollectionId, documentId, cancellationToken);

    public Task<DocumentRecord> CreateAsync(
        string title, string content, string? tags, string authorId, string authorName, CancellationToken cancellationToken) =>
        _data.CreateAsync<DocumentRecord>(_options.DocumentsCollectionId, new Dictionary<string, object?>
        {
            ["title"] = title,
            ["content"] = content,
            ["tags"] = tags ?? string.Empty,
            ["authorId"] = authorId,
            ["authorName"] = authorName,
        }, cancellationToken);

    public Task<DocumentRecord> UpdateAsync(string documentId, string title, string content, string? tags, CancellationToken cancellationToken) =>
        _data.UpdateAsync<DocumentRecord>(_options.DocumentsCollectionId, documentId, new Dictionary<string, object?>
        {
            ["title"] = title,
            ["content"] = content,
            ["tags"] = tags ?? string.Empty,
        }, cancellationToken);

    public Task DeleteAsync(string documentId, CancellationToken cancellationToken) =>
        _data.DeleteAsync(_options.DocumentsCollectionId, documentId, cancellationToken);
}
