using Microsoft.Extensions.Options;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Options;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>Reads and appends to the "search_log" collection - direct port of the reference app's RecentSearches.tsx read and AskAIPanel.tsx's log-after-ask write.</summary>
public sealed class SearchLogService
{
    private readonly MudbaseDataService _data;
    private readonly MudbaseOptions _options;

    public SearchLogService(MudbaseDataService data, IOptions<MudbaseOptions> options)
    {
        _data = data;
        _options = options.Value;
    }

    /// <summary>Newest-first, for the Ask AI page's "Recent searches" list.</summary>
    public Task<MudbaseListResult<SearchLogRecord>> ListRecentAsync(int limit, CancellationToken cancellationToken) =>
        _data.ListAsync<SearchLogRecord>(_options.SearchLogCollectionId, sort: "-createdAt", page: 1, limit: limit, cancellationToken: cancellationToken);

    /// <summary>
    /// Appends one row per Ask AI question. `userId`/`userName` are omitted entirely (not sent as
    /// null/placeholder) when the asker was a guest - a real ObjectId or nothing, never a
    /// placeholder string, matching the reference app's own conditional spread exactly.
    /// </summary>
    public Task<SearchLogRecord> LogAsync(string queryText, int resultCount, string? userId, string? userName, CancellationToken cancellationToken)
    {
        var data = new Dictionary<string, object?>
        {
            ["queryText"] = queryText,
            ["resultCount"] = resultCount,
        };

        if (!string.IsNullOrEmpty(userId)) data["userId"] = userId;
        if (!string.IsNullOrEmpty(userName)) data["userName"] = userName;

        return _data.CreateAsync<SearchLogRecord>(_options.SearchLogCollectionId, data, cancellationToken);
    }
}
