namespace MudbaseShowcase.DocsSearch.Models;

/// <summary>Result of a login/register/verify attempt against Mudbase, for display in a Razor Page without throwing on expected failures.</summary>
public sealed class AuthOutcome
{
    public bool Succeeded { get; private init; }
    public string? ErrorMessage { get; private init; }
    public bool RequiresEmailVerification { get; private init; }

    public static AuthOutcome Success() => new() { Succeeded = true };

    public static AuthOutcome Failure(string message) => new() { Succeeded = false, ErrorMessage = message };

    public static AuthOutcome NeedsEmailVerification(string message) =>
        new() { Succeeded = false, ErrorMessage = message, RequiresEmailVerification = true };
}
