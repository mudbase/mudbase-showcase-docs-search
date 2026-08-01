using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages;

/// <summary>Completes the emailed verification link.</summary>
public sealed class VerifyEmailModel : PageModel
{
    private readonly MudbaseAuthService _authService;

    public VerifyEmailModel(MudbaseAuthService authService)
    {
        _authService = authService;
    }

    public bool Succeeded { get; private set; }

    public string? ErrorMessage { get; private set; }

    public async Task OnGetAsync(string? token, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            ErrorMessage = "This verification link is missing its token.";
            return;
        }

        AuthOutcome outcome = await _authService.VerifyEmailAsync(token, cancellationToken);
        if (outcome.Succeeded)
        {
            Succeeded = true;
        }
        else
        {
            ErrorMessage = outcome.ErrorMessage ?? "This verification link is invalid or has expired.";
        }
    }
}
