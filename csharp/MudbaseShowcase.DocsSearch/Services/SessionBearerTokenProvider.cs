using Mudbase.Sdk;
using Mudbase.Sdk.Client;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// The Mudbase SDK's generated Api classes (AuthenticationApi, DataApi, MultiRoleFeatureApi,
/// UsersApi, ...) call `BearerTokenProvider.GetAsync()` on every authenticated request and put the
/// result straight in the Authorization header. The SDK's own DI wiring (HostConfiguration.AddTokens
/// + UseProvider) is built for a single static token registered once at startup - fine for a
/// server-to-server API key, wrong for this app, where every browser session carries its own
/// Mudbase JWT (anonymous guest or real "customer") that changes over the app's lifetime across
/// many concurrent users.
///
/// This provider closes over IHttpContextAccessor (via <see cref="MudbaseSessionAccessor"/>)
/// instead of a fixed token, so each call resolves whichever JWT is stored in *that request's*
/// session at the moment the SDK asks for one - safe to register as a singleton (as
/// UseProvider&lt;,&gt;() requires) because IHttpContextAccessor itself is singleton-safe, reading
/// the ambient HttpContext via AsyncLocal rather than storing per-instance state.
/// </summary>
public sealed class SessionBearerTokenProvider : TokenProvider<BearerToken>
{
    private readonly MudbaseSessionAccessor _session;

    public SessionBearerTokenProvider(MudbaseSessionAccessor session)
    {
        _session = session;
    }

    // Overriding a `protected internal` base member from a different assembly can only re-expose
    // the `protected` part - C# doesn't let this assembly grant the `internal` half back to the
    // SDK's assembly, so the override modifier here is intentionally narrower than the base.
    protected override ValueTask<BearerToken> GetAsync(string header = "", CancellationToken cancellation = default)
    {
        string token = _session.GetToken() ?? string.Empty;
        return ValueTask.FromResult(new BearerToken(token));
    }
}
