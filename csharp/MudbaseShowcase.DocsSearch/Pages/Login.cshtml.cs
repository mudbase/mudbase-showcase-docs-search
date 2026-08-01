using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages;

/// <summary>
/// Email+password sign-in, plus a "Sign in as demo" quick-fill button for the task's one demo
/// account - mirrors web/src/components/auth/LoginForm.tsx. Unlike the Kanban showcase (three
/// roles) this project ships a single "customer" role, so there is only one quick-login button.
/// </summary>
public sealed class LoginModel : PageModel
{
    private readonly MudbaseAuthService _authService;

    public LoginModel(MudbaseAuthService authService)
    {
        _authService = authService;
    }

    [BindProperty]
    public LoginInput Input { get; set; } = new();

    public string? ErrorMessage { get; private set; }

    /// <summary>Where to send the visitor after a successful sign-in - the New/Edit document pages pass their own page URL here so signing in doesn't bounce back to the library root.</summary>
    [BindProperty(SupportsGet = true)]
    public string? ReturnUrl { get; set; }

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid)
        {
            return Page();
        }

        AuthOutcome outcome = await _authService.LoginAsync(Input.Email, Input.Password, cancellationToken);
        return AfterLogin(outcome);
    }

    /// <summary>The task's one pre-verified demo account - not a secret credential store, just a fast-demo convenience mirroring the reference project's single test account.</summary>
    public async Task<IActionResult> OnPostQuickLoginAsync(CancellationToken cancellationToken)
    {
        AuthOutcome outcome = await _authService.LoginAsync("docs.member.demo@gmail.com", "DemoTest123!", cancellationToken);
        return AfterLogin(outcome);
    }

    private IActionResult AfterLogin(AuthOutcome outcome)
    {
        if (!outcome.Succeeded)
        {
            ErrorMessage = outcome.ErrorMessage ?? "Login failed";
            return Page();
        }

        if (!string.IsNullOrWhiteSpace(ReturnUrl) && Url.IsLocalUrl(ReturnUrl))
        {
            return LocalRedirect(ReturnUrl);
        }

        return RedirectToPage("/Index");
    }

    public sealed class LoginInput
    {
        [Required(ErrorMessage = "Email is required"), EmailAddress(ErrorMessage = "Enter a valid email address")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Password is required")]
        public string Password { get; set; } = string.Empty;
    }
}
