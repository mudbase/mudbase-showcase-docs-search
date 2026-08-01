using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// Attached (see Program.cs's ConfigureApi wiring) to every HttpClient the generated Mudbase SDK
/// uses. A Mudbase access token is short-lived; without this handler, any page whose session
/// token has expired mid-visit gets a raw 401 surfaced as an unhandled MudbaseApiException. Instead:
/// on a 401, exchange the session's stored refresh token for a new access/refresh pair via
/// POST /api/auth/refresh (through the handler-free "MudbaseRaw" HttpClient, deliberately bypassing
/// this same pipeline so a refresh call can never recursively trigger itself), store the new pair,
/// and retry the original request exactly once with the new access token. If refresh fails for any
/// reason (no refresh token stored, network error, refresh token itself expired/revoked), the
/// original 401 is returned untouched and callers fall back to their existing failure handling
/// (MudbaseApiException, or EnsureMudbaseSessionMiddleware bootstrapping a fresh anonymous session
/// on the next request).
/// </summary>
public sealed class TokenRefreshHandler : DelegatingHandler
{
    private readonly MudbaseSessionAccessor _session;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<TokenRefreshHandler> _logger;

    public TokenRefreshHandler(
        MudbaseSessionAccessor session, IHttpClientFactory httpClientFactory, ILogger<TokenRefreshHandler> logger)
    {
        _session = session;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        // Buffer the outgoing body up front - HttpContent's underlying stream can only be read
        // once, and a retry needs a fresh HttpRequestMessage (a single HttpRequestMessage instance
        // cannot be sent twice).
        byte[]? bufferedBody = request.Content is null
            ? null
            : await request.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);

        HttpResponseMessage response = await base.SendAsync(request, cancellationToken).ConfigureAwait(false);

        if (response.StatusCode != HttpStatusCode.Unauthorized)
        {
            return response;
        }

        string? refreshToken = _session.GetRefreshToken();
        if (string.IsNullOrEmpty(refreshToken))
        {
            return response;
        }

        string? newAccessToken = await TryRefreshAsync(refreshToken, cancellationToken).ConfigureAwait(false);
        if (newAccessToken is null)
        {
            return response;
        }

        response.Dispose();

        using HttpRequestMessage retryRequest = CloneRequest(request, bufferedBody);
        retryRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", newAccessToken);

        return await base.SendAsync(retryRequest, cancellationToken).ConfigureAwait(false);
    }

    private async Task<string?> TryRefreshAsync(string refreshToken, CancellationToken cancellationToken)
    {
        try
        {
            HttpClient rawClient = _httpClientFactory.CreateClient(HttpClientNames.MudbaseRaw);
            using HttpResponseMessage refreshResponse = await rawClient.PostAsJsonAsync(
                "/api/auth/refresh", new RefreshRequestPayload(refreshToken), MudbaseJson.Options, cancellationToken)
                .ConfigureAwait(false);

            if (!refreshResponse.IsSuccessStatusCode)
            {
                _logger.LogWarning("Mudbase token refresh failed with status {StatusCode}", refreshResponse.StatusCode);
                return null;
            }

            RefreshResponsePayload? payload = await refreshResponse.Content
                .ReadFromJsonAsync<RefreshResponsePayload>(MudbaseJson.Options, cancellationToken)
                .ConfigureAwait(false);

            if (payload?.Token is not { Length: > 0 } newAccessToken)
            {
                return null;
            }

            _session.SetTokens(newAccessToken, payload.RefreshToken);
            return newAccessToken;
        }
        catch (HttpRequestException ex)
        {
            _logger.LogWarning(ex, "Mudbase token refresh could not reach Mudbase");
            return null;
        }
    }

    private static HttpRequestMessage CloneRequest(HttpRequestMessage original, byte[]? bufferedBody)
    {
        HttpRequestMessage clone = new(original.Method, original.RequestUri);

        foreach (KeyValuePair<string, IEnumerable<string>> header in original.Headers)
        {
            clone.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        if (bufferedBody is not null && original.Content is not null)
        {
            ByteArrayContent content = new(bufferedBody);
            foreach (KeyValuePair<string, IEnumerable<string>> header in original.Content.Headers)
            {
                content.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }

            clone.Content = content;
        }

        return clone;
    }

    private sealed record RefreshRequestPayload([property: JsonPropertyName("refreshToken")] string RefreshToken);

    private sealed class RefreshResponsePayload
    {
        [JsonPropertyName("token")]
        public string? Token { get; set; }

        [JsonPropertyName("refreshToken")]
        public string? RefreshToken { get; set; }
    }
}
