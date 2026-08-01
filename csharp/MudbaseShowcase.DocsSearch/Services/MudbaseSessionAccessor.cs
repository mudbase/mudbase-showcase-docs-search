using System.Text.Json;
using Microsoft.AspNetCore.Http;
using MudbaseShowcase.DocsSearch.Models;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// Reads/writes the current browser session's Mudbase JWT and cached user info in ASP.NET Core's
/// server-side session state - the JWT never reaches client JS. Registered as a singleton: it
/// only closes over IHttpContextAccessor (itself safe as a singleton, since it resolves the
/// ambient HttpContext per call via AsyncLocal), so every read/write here is already scoped to
/// whichever request is currently in flight. This lets <see cref="SessionBearerTokenProvider"/>
/// (also a singleton, per the SDK's DI wiring) depend on it directly without a scoped-from-
/// singleton DI violation.
/// </summary>
public sealed class MudbaseSessionAccessor
{
    private const string TokenKey = "mb_token";
    private const string RefreshTokenKey = "mb_refresh_token";
    private const string UserKey = "mb_user";

    private readonly IHttpContextAccessor _httpContextAccessor;

    public MudbaseSessionAccessor(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    private ISession Session =>
        _httpContextAccessor.HttpContext?.Session
        ?? throw new InvalidOperationException("MudbaseSessionAccessor was used outside an active HTTP request.");

    public bool HasToken => !string.IsNullOrEmpty(Session.GetString(TokenKey));

    public string? GetToken() => Session.GetString(TokenKey);

    /// <summary>
    /// Sets the access token and, when present, the refresh token - call this after every
    /// login/register/anonymous-session/refresh response so <see cref="TokenRefreshHandler"/> can
    /// transparently recover from a future 401 without the user noticing.
    /// </summary>
    public void SetTokens(string accessToken, string? refreshToken)
    {
        Session.SetString(TokenKey, accessToken);
        if (!string.IsNullOrEmpty(refreshToken))
        {
            Session.SetString(RefreshTokenKey, refreshToken);
        }
    }

    public string? GetRefreshToken() => Session.GetString(RefreshTokenKey);

    public void ClearToken()
    {
        Session.Remove(TokenKey);
        Session.Remove(RefreshTokenKey);
    }

    public MudbaseSessionUser? CurrentUser
    {
        get
        {
            string? raw = Session.GetString(UserKey);
            if (raw is null) return null;
            try
            {
                return JsonSerializer.Deserialize<MudbaseSessionUser>(raw, MudbaseJson.Options);
            }
            catch (JsonException)
            {
                return null;
            }
        }
    }

    public void SetUser(MudbaseSessionUser user) => Session.SetString(UserKey, JsonSerializer.Serialize(user, MudbaseJson.Options));

    public void ClearUser() => Session.Remove(UserKey);
}
