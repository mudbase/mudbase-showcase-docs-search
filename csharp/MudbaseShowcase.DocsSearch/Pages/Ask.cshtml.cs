using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Logging;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages;

/// <summary>
/// Ask AI: keyword retrieval over the loaded document library -&gt; a real Mudbase Function
/// (re-ranking + grounded context assembly) -&gt; a single server-side Anthropic Claude completion
/// call -&gt; a citations-backed answer, plus a recent-searches feed. Mirrors
/// web/src/components/ask/AskAIPanel.tsx and RecentSearches.tsx exactly, folded into one Razor
/// Page since this app has no separate API route the way the Next.js reference needed one - see
/// Services/FunctionInvocationService.cs and Services/LlmService.cs's doc comments for why.
/// </summary>
public sealed class AskModel : PageModel
{
    private const int DocumentLimit = 200;
    private const int RecentSearchLimit = 10;
    private const int CandidateLimit = 5;

    private readonly DocumentsService _documents;
    private readonly SearchLogService _searchLog;
    private readonly FunctionInvocationService _functionInvocation;
    private readonly LlmService _llm;
    private readonly MudbaseSessionAccessor _session;
    private readonly ILogger<AskModel> _logger;

    public AskModel(
        DocumentsService documents,
        SearchLogService searchLog,
        FunctionInvocationService functionInvocation,
        LlmService llm,
        MudbaseSessionAccessor session,
        ILogger<AskModel> logger)
    {
        _documents = documents;
        _searchLog = searchLog;
        _functionInvocation = functionInvocation;
        _llm = llm;
        _session = session;
        _logger = logger;
    }

    [BindProperty]
    public string Question { get; set; } = string.Empty;

    public string? Answer { get; private set; }

    public IReadOnlyList<AskCitationViewModel> Citations { get; private set; } = Array.Empty<AskCitationViewModel>();

    public bool NoMatch { get; private set; }

    public string? AskError { get; private set; }

    public IReadOnlyList<SearchLogRecord> RecentSearches { get; private set; } = Array.Empty<SearchLogRecord>();

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        await LoadRecentSearchesAsync(cancellationToken);
    }

    public async Task<IActionResult> OnPostAskAsync(CancellationToken cancellationToken)
    {
        await LoadRecentSearchesAsync(cancellationToken);

        string trimmed = Question.Trim();
        if (trimmed.Length == 0)
        {
            return Page();
        }

        MudbaseSessionUser? user = _session.CurrentUser;

        MudbaseListResult<DocumentRecord> allDocuments;
        try
        {
            allDocuments = await _documents.ListAsync(DocumentLimit, cancellationToken);
        }
        catch (MudbaseApiException ex)
        {
            AskError = "Couldn't load the document library right now. (" + ex.Message + ")";
            return Page();
        }

        List<ScoredDocument> scored = RetrievalHelpers.ScoreDocuments(allDocuments.Items, trimmed);

        if (scored.Count == 0)
        {
            NoMatch = true;
            await LogSearchAsync(trimmed, 0, user, cancellationToken);
            return Page();
        }

        List<RetrievalCandidate> candidates = RetrievalHelpers.TopCandidates(scored, CandidateLimit);

        try
        {
            RetrievalResult retrieval = await _functionInvocation.InvokeAsync(trimmed, candidates, cancellationToken);

            if (retrieval.UsedCount == 0)
            {
                Answer =
                    "I couldn't find anything in the knowledge base closely related to that question. Try rephrasing, or add a document that covers it.";
                Citations = Array.Empty<AskCitationViewModel>();
                await LogSearchAsync(trimmed, 0, user, cancellationToken);
                return Page();
            }

            string answer = await _llm.GenerateGroundedAnswerAsync(trimmed, retrieval.ContextBlock, cancellationToken);

            Answer = answer;
            Citations = retrieval.Citations
                .Select(citation => new AskCitationViewModel { DocumentId = citation.DocumentId, Title = citation.Title })
                .ToList();

            await LogSearchAsync(trimmed, Citations.Count, user, cancellationToken);
        }
        catch (AskAiException ex)
        {
            _logger.LogError(ex, "Ask AI request failed");
            AskError = ex.Message;
        }

        return Page();
    }

    /// <summary>
    /// Best-effort: a failed search_log write must never hide an already-computed answer from the
    /// visitor - mirrors the reference AskAIPanel.tsx, where this same call also isn't guarded
    /// against blocking the already-rendered answer state.
    /// </summary>
    private async Task LogSearchAsync(string queryText, int resultCount, MudbaseSessionUser? user, CancellationToken cancellationToken)
    {
        string? userId = user is { IsSignedIn: true } ? user.Id : null;
        string? userName = user is { IsSignedIn: true } ? user.DisplayName : null;

        try
        {
            await _searchLog.LogAsync(queryText, resultCount, userId, userName, cancellationToken);
        }
        catch (MudbaseApiException ex)
        {
            _logger.LogWarning(ex, "search_log write failed after an Ask AI request");
        }
    }

    private async Task LoadRecentSearchesAsync(CancellationToken cancellationToken)
    {
        try
        {
            MudbaseListResult<SearchLogRecord> result = await _searchLog.ListRecentAsync(RecentSearchLimit, cancellationToken);
            RecentSearches = result.Items;
        }
        catch (MudbaseApiException ex)
        {
            _logger.LogWarning(ex, "Couldn't load recent searches");
            RecentSearches = Array.Empty<SearchLogRecord>();
        }
    }
}
