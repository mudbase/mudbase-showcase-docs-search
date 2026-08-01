namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>
/// Thrown by <see cref="FunctionInvocationService"/> and <see cref="LlmService"/> on any failure
/// along the Ask AI pipeline - execute/poll failures, a missing server-only credential, or an
/// unusable LLM response. The message is always safe to render directly to a page (never includes
/// a secret value), mirroring the reference app's POST /api/ask route handler, which catches any
/// error from either step and returns its message as-is.
/// </summary>
public sealed class AskAiException : Exception
{
    public AskAiException(string message) : base(message)
    {
    }

    public AskAiException(string message, Exception innerException) : base(message, innerException)
    {
    }
}
