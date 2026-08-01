using System.Text.Json.Serialization;

namespace MudbaseShowcase.DocsSearch.Models;

/// <summary>
/// The authenticated user info this app cares about, parsed from Mudbase's session/user payload
/// (which the generated SDK types loosely as `Object` - see
/// <see cref="MudbaseShowcase.DocsSearch.Services.MudbaseAuthService"/>). Mirrors
/// web/src/lib/mudbase.ts's UserObject.
/// </summary>
public sealed class MudbaseSessionUser
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("email")]
    public string Email { get; set; } = string.Empty;

    [JsonPropertyName("firstName")]
    public string FirstName { get; set; } = string.Empty;

    [JsonPropertyName("lastName")]
    public string LastName { get; set; } = string.Empty;

    [JsonPropertyName("role")]
    public string? Role { get; set; }

    /// <summary>Mudbase Multi-Role customRole - this app only ever has "customer" (single-role starter template).</summary>
    [JsonPropertyName("customRole")]
    public string? CustomRole { get; set; }

    [JsonPropertyName("emailVerified")]
    public bool EmailVerified { get; set; }

    [JsonPropertyName("isAnonymous")]
    public bool? IsAnonymous { get; set; }

    /// <summary>
    /// True for a real signed-in "customer" account, false for a guest anonymous session - mirrors
    /// web/src/hooks/useAuth.ts's isAuthenticated exactly: `!!user && user.isAnonymous !== true &&
    /// !!user.customRole`. Checking CustomRole in addition to IsAnonymous (unlike the sibling
    /// social/ecommerce C# ports, which only check IsAnonymous) matters here because this app's
    /// guest/anonymous session and its signed-in "customer" session are both real accounts an
    /// end-user can be logged in as - the extra CustomRole check is what the reference app itself
    /// relies on to tell them apart.
    /// </summary>
    public bool IsSignedIn => IsAnonymous != true && !string.IsNullOrEmpty(CustomRole);

    /// <summary>"First Last", trimmed - used as the denormalized authorName/userName written to every collection row this user creates.</summary>
    public string DisplayName => $"{FirstName} {LastName}".Trim();
}
