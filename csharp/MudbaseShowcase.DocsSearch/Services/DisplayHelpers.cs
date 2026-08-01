using System.Globalization;
using System.Text.RegularExpressions;

namespace MudbaseShowcase.DocsSearch.Services;

/// <summary>Small display-formatting helpers shared by Razor views. Direct port of web/src/lib/utils.ts's formatRelativeTime/formatDateTime/snippet/parseTags.</summary>
public static class DisplayHelpers
{
    public static string FormatRelativeTime(DateTimeOffset value)
    {
        double diffSeconds = Math.Round((DateTimeOffset.UtcNow - value).TotalSeconds);

        if (diffSeconds < 5) return "just now";
        if (diffSeconds < 60) return $"{(int)diffSeconds}s ago";

        double diffMinutes = Math.Round(diffSeconds / 60);
        if (diffMinutes < 60) return $"{(int)diffMinutes}m ago";

        double diffHours = Math.Round(diffMinutes / 60);
        if (diffHours < 24) return $"{(int)diffHours}h ago";

        double diffDays = Math.Round(diffHours / 24);
        if (diffDays < 7) return $"{(int)diffDays}d ago";

        return value.ToLocalTime().ToString("MMM d, yyyy", CultureInfo.InvariantCulture);
    }

    public static string FormatDateTime(DateTimeOffset value) =>
        value.ToLocalTime().ToString("MMM d, yyyy h:mm tt", CultureInfo.InvariantCulture);

    /// <summary>Builds a short plain-text snippet from document content, for library-card previews.</summary>
    public static string Snippet(string text, int maxLength = 160)
    {
        string trimmed = Regex.Replace(text.Trim(), @"\s+", " ");
        if (trimmed.Length <= maxLength) return trimmed;
        return trimmed[..maxLength].TrimEnd() + "…";
    }

    /// <summary>Parses the documents.tags field (comma-separated string) into a clean list.</summary>
    public static IReadOnlyList<string> ParseTags(string? tags)
    {
        if (string.IsNullOrWhiteSpace(tags)) return Array.Empty<string>();
        return tags.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
    }
}
