using MudbaseShowcase.DocsSearch.Services;

namespace MudbaseShowcase.DocsSearch.Infrastructure;

/// <summary>
/// Runs once per request, right after the session cookie middleware, and bootstraps an anonymous
/// Mudbase session the first time a given browser session shows up with no token yet - mirrors the
/// guest-browsing bootstrap in web/src/lib/mudbase-provider.tsx's MudbaseProvider effect (every
/// collection read 401s with zero auth on this project, even with the project's own publishable
/// key - an anonymous session is required for guest browsing/search, per the task). Every later
/// request from the same browser reuses the token already cached in session state, so this only
/// calls out to Mudbase once per session (or once again after logout).
/// </summary>
public sealed class EnsureMudbaseSessionMiddleware
{
    private readonly RequestDelegate _next;

    public EnsureMudbaseSessionMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context, MudbaseAuthService authService)
    {
        if (!IsStaticAsset(context.Request.Path))
        {
            await authService.EnsureAnonymousSessionAsync(context.RequestAborted);
        }

        await _next(context);
    }

    private static bool IsStaticAsset(PathString path) =>
        path.StartsWithSegments("/css") ||
        path.StartsWithSegments("/js") ||
        path.StartsWithSegments("/lib") ||
        path.StartsWithSegments("/favicon.ico");
}
