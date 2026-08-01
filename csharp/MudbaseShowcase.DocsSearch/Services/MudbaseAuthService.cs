using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Mudbase.Sdk.Api;
using Mudbase.Sdk.Model;
using MudbaseShowcase.DocsSearch.Models;
using MudbaseShowcase.DocsSearch.Options;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// Everything auth-related: bootstrapping a guest anonymous session so browsing/search works
/// without signing in, customer self-registration, login, session refresh, email verification,
/// and logout. Ported from the sibling mudbase-showcase-social/csharp port's MudbaseAuthService -
/// same single-role "customer" starter template, same email-verification-required registration
/// flow (mirrored by web/src/components/auth/RegisterForm.tsx's "check your inbox" success state).
///
/// Every call here goes through the generated SDK directly - no raw-HttpClient workarounds.
/// </summary>
public sealed class MudbaseAuthService
{
    private readonly IAuthenticationApi _authApi;
    private readonly IMultiRoleFeatureApi _multiRoleApi;
    private readonly IUsersApi _usersApi;
    private readonly MudbaseSessionAccessor _session;
    private readonly MudbaseOptions _options;
    private readonly ILogger<MudbaseAuthService> _logger;

    public MudbaseAuthService(
        IAuthenticationApi authApi,
        IMultiRoleFeatureApi multiRoleApi,
        IUsersApi usersApi,
        MudbaseSessionAccessor session,
        IOptions<MudbaseOptions> options,
        ILogger<MudbaseAuthService> logger)
    {
        _authApi = authApi;
        _multiRoleApi = multiRoleApi;
        _usersApi = usersApi;
        _session = session;
        _options = options.Value;
        _logger = logger;
    }

    /// <summary>
    /// Guest browsing with no signup: an anonymous session lets the library/search read permission
    /// resolve without forcing signup. Called once per browser session by
    /// EnsureMudbaseSessionMiddleware - every later request from the same browser reuses the token
    /// already cached in session state.
    /// </summary>
    public async Task EnsureAnonymousSessionAsync(CancellationToken cancellationToken)
    {
        if (_session.HasToken)
        {
            return;
        }

        try
        {
            ICreateAnonymousSessionApiResponse response =
                await _authApi.CreateAnonymousSessionAsync(new CreateAnonymousSessionRequest(_options.ProjectId), cancellationToken);

            if (response.TryOk(out CreateAnonymousSession200Response? body) && body?.Token is { Length: > 0 } token)
            {
                _session.SetTokens(token, body.RefreshToken);
                await RefreshSessionAsync(cancellationToken);
            }
            else
            {
                _logger.LogWarning("Anonymous Mudbase session bootstrap failed with status {StatusCode}", response.StatusCode);
            }
        }
        catch (HttpRequestException ex)
        {
            _logger.LogWarning(ex, "Anonymous Mudbase session bootstrap could not reach Mudbase");
        }
    }

    /// <summary>
    /// Self-signup is always the "customer" Multi-Role - this project ships Mudbase's single-role
    /// starter template. Registration requires email verification: the response comes back 201
    /// with no token and requireVerification: true, matching the reference RegisterForm.tsx's own
    /// "check your inbox" success state.
    /// </summary>
    public async Task<AuthOutcome> RegisterCustomerAsync(
        string email, string password, string firstName, string lastName, bool agreedToTerms, CancellationToken cancellationToken)
    {
        RegisterWithRoleRequest request = new(email, password, firstName, lastName, _options.ProjectId, agreedToTerms);
        IRegisterWithRoleApiResponse response = await _multiRoleApi.RegisterWithRoleAsync("customer", request, cancellationToken);

        if (!response.TryCreated(out RegisterWithRole201Response? body) || body is null)
        {
            return AuthOutcome.Failure(MudbaseApiException.From(response).Message);
        }

        if (body.RequireVerification == true || body.Token is not { Length: > 0 } token)
        {
            return AuthOutcome.NeedsEmailVerification(
                body.Message ?? "Account created — check your email to verify it, then sign in.");
        }

        _session.SetTokens(token, body.RefreshToken);
        await RefreshSessionAsync(cancellationToken);
        return AuthOutcome.Success();
    }

    /// <summary>
    /// Blocked with 403 EMAIL_VERIFICATION_REQUIRED until the account's email is verified - that
    /// server error's `error` message surfaces as-is via MudbaseApiException, matching the web
    /// app's LoginForm behavior.
    /// </summary>
    public async Task<AuthOutcome> LoginAsync(string email, string password, CancellationToken cancellationToken)
    {
        LoginLocalUserRequest request = new(email, password, _options.ProjectId);
        ILoginLocalUserApiResponse response = await _authApi.LoginLocalUserAsync(request, cancellationToken);

        if (!response.TryOk(out LoginLocalUser200Response? body) || body?.Token is not { Length: > 0 } token)
        {
            return AuthOutcome.Failure(MudbaseApiException.From(response).Message);
        }

        _session.SetTokens(token, body.RefreshToken);
        await RefreshSessionAsync(cancellationToken);
        return AuthOutcome.Success();
    }

    /// <summary>Completes the emailed verification link's token. Public, unauthenticated endpoint on Mudbase's side.</summary>
    public async Task<AuthOutcome> VerifyEmailAsync(string token, CancellationToken cancellationToken)
    {
        IVerifyEmailApiResponse response = await _usersApi.VerifyEmailAsync(new VerifyEmailAuthRequest(token), cancellationToken);

        if (!response.TryOk(out MessageResponse? body))
        {
            return AuthOutcome.Failure(MudbaseApiException.From(response).Message);
        }

        return AuthOutcome.Success();
    }

    /// <summary>
    /// Fetches the full, authoritative session user (including customRole, which the login/signup
    /// responses' typed models don't expose) and caches it in session state. Call after every
    /// token change (login, register, anonymous bootstrap, refresh) - mirrors refreshSession() in
    /// web/src/lib/mudbase-provider.tsx.
    /// </summary>
    public async Task RefreshSessionAsync(CancellationToken cancellationToken)
    {
        if (!_session.HasToken)
        {
            _session.ClearUser();
            return;
        }

        IGetLocalSessionApiResponse response = await _authApi.GetLocalSessionAsync(_options.ProjectId, cancellationToken);

        if (!response.TryOk(out GetLocalSession200Response? body) || body?.User is not JsonElement userElement)
        {
            _session.ClearToken();
            _session.ClearUser();
            return;
        }

        MudbaseSessionUser? user = JsonSerializer.Deserialize<MudbaseSessionUser>(userElement.GetRawText(), MudbaseJson.Options);
        _session.SetUser(user ?? new MudbaseSessionUser());
    }

    public async Task LogoutAsync(CancellationToken cancellationToken)
    {
        if (_session.HasToken)
        {
            try
            {
                await _authApi.LogoutLocalUserAsync(cancellationToken);
            }
            catch (HttpRequestException ex)
            {
                // Best-effort: the browser's session is cleared regardless so the user is signed
                // out locally even if Mudbase couldn't be reached to revoke server-side.
                _logger.LogWarning(ex, "Mudbase logout call failed; clearing local session anyway");
            }
        }

        _session.ClearToken();
        _session.ClearUser();
    }
}
