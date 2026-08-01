using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Pages;

/// <summary>
/// Self-signup is always "customer" - this project ships Mudbase's single-role starter template,
/// so there is no role picker. Registration requires email verification: a successful submit here
/// shows a "check your inbox" state instead of assuming a session, mirroring
/// web/src/components/auth/RegisterForm.tsx.
/// </summary>
public sealed class RegisterModel : PageModel
{
    private readonly MudbaseAuthService _authService;

    public RegisterModel(MudbaseAuthService authService)
    {
        _authService = authService;
    }

    [BindProperty]
    public RegisterInput Input { get; set; } = new();

    public string? ErrorMessage { get; private set; }

    public string? SuccessMessage { get; private set; }

    [BindProperty(SupportsGet = true)]
    public string? ReturnUrl { get; set; }

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        if (!Input.AgreedToTerms)
        {
            // Must be the fully-qualified "Input.AgreedToTerms" key, matching the [BindProperty]
            // prefix - plain nameof(Input.AgreedToTerms) resolves to just "AgreedToTerms" and
            // silently fails to line up with asp-validation-for="Input.AgreedToTerms" in the view.
            ModelState.AddModelError($"{nameof(Input)}.{nameof(Input.AgreedToTerms)}", "You must agree to the Terms of Service and Privacy Policy.");
        }

        if (!ModelState.IsValid)
        {
            return Page();
        }

        AuthOutcome outcome = await _authService.RegisterCustomerAsync(
            Input.Email, Input.Password, Input.FirstName, Input.LastName, Input.AgreedToTerms, cancellationToken);

        if (outcome.RequiresEmailVerification)
        {
            SuccessMessage = outcome.ErrorMessage ?? "Account created — check your email to verify it, then sign in.";
            return Page();
        }

        if (!outcome.Succeeded)
        {
            ErrorMessage = outcome.ErrorMessage ?? "Registration failed";
            return Page();
        }

        if (!string.IsNullOrWhiteSpace(ReturnUrl) && Url.IsLocalUrl(ReturnUrl))
        {
            return LocalRedirect(ReturnUrl);
        }

        return RedirectToPage("/Index");
    }

    public sealed class RegisterInput
    {
        [Required(ErrorMessage = "First name is required")]
        public string FirstName { get; set; } = string.Empty;

        [Required(ErrorMessage = "Last name is required")]
        public string LastName { get; set; } = string.Empty;

        [Required(ErrorMessage = "Email is required"), EmailAddress(ErrorMessage = "Enter a valid email address")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Password is required")]
        [MinLength(8, ErrorMessage = "Password must be at least 8 characters")]
        public string Password { get; set; } = string.Empty;

        public bool AgreedToTerms { get; set; }
    }
}
