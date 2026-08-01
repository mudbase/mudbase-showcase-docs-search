import Foundation

/// Mirrors `../web/src/lib/utils.ts`'s formatting helpers exactly (same thresholds and wording),
/// so this port's library cards, document detail page, and recent-searches list read identically
/// to the reference web app.
enum Formatting {
    static func relativeTime(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let diffSeconds = Int((now.timeIntervalSince(date)).rounded())

        if diffSeconds < 5 { return "just now" }
        if diffSeconds < 60 { return "\(diffSeconds)s ago" }
        let diffMinutes = Int((Double(diffSeconds) / 60).rounded())
        if diffMinutes < 60 { return "\(diffMinutes)m ago" }
        let diffHours = Int((Double(diffMinutes) / 60).rounded())
        if diffHours < 24 { return "\(diffHours)h ago" }
        let diffDays = Int((Double(diffHours) / 24).rounded())
        if diffDays < 7 { return "\(diffDays)d ago" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func dateTime(from date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Builds a short plain-text snippet from document content, for library-card previews. Mirrors
    /// `../web/src/lib/utils.ts`'s `snippet`.
    static func snippet(_ text: String, maxLength: Int = 160) -> String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count <= maxLength { return collapsed }
        let cutoff = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        let truncated = String(collapsed[..<cutoff]).trimmingCharacters(in: .whitespaces)
        return "\(truncated)…"
    }

    /// Parses the `documents.tags` field (comma-separated string) into a clean array. Mirrors
    /// `../web/src/lib/utils.ts`'s `parseTags`.
    static func parseTags(_ tags: String?) -> [String] {
        guard let tags, !tags.isEmpty else { return [] }
        return tags
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
