package server

import (
	"strconv"
	"strings"
	"time"
)

// formatDate parses an RFC3339 timestamp (as returned by Mudbase's createdAt/updatedAt fields) and
// renders it in a medium, readable form. Malformed or empty input renders as "-" rather than
// panicking or leaking a raw parse error into the page.
func formatDate(iso string) string {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return "-"
	}
	return t.Local().Format("Jan 2, 2006, 3:04 PM")
}

// formatRelativeTime renders iso as a short relative label ("just now", "5m ago", ...), falling
// back to formatDate past a week - mirrors web/src/lib/utils.ts's formatRelativeTime, used by the
// /ask page's recent-searches panel.
func formatRelativeTime(iso string) string {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return "-"
	}
	diff := time.Since(t)
	switch {
	case diff < 5*time.Second:
		return "just now"
	case diff < time.Minute:
		return strconv.Itoa(int(diff.Seconds())) + "s ago"
	case diff < time.Hour:
		return strconv.Itoa(int(diff.Minutes())) + "m ago"
	case diff < 24*time.Hour:
		return strconv.Itoa(int(diff.Hours())) + "h ago"
	case diff < 7*24*time.Hour:
		return strconv.Itoa(int(diff.Hours()/24)) + "d ago"
	default:
		return formatDate(iso)
	}
}

// initials renders up to two uppercase letters from name for the avatar-circle fallback this app
// uses wherever a real profile photo would go.
func initials(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "?"
	}
	fields := strings.Fields(name)
	if len(fields) == 1 {
		runes := []rune(fields[0])
		if len(runes) == 1 {
			return strings.ToUpper(string(runes[0]))
		}
		return strings.ToUpper(string(runes[:2]))
	}
	first := []rune(fields[0])[0]
	last := []rune(fields[len(fields)-1])[0]
	return strings.ToUpper(string(first) + string(last))
}

// parseTags parses the documents.tags field (comma-separated string) into a clean slice - mirrors
// web/src/lib/utils.ts's parseTags exactly.
func parseTags(tags string) []string {
	if tags == "" {
		return nil
	}
	parts := strings.Split(tags, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// snippet builds a short plain-text preview from document content, for library-card previews -
// mirrors web/src/lib/utils.ts's snippet exactly.
func snippet(text string, maxLength int) string {
	trimmed := strings.Join(strings.Fields(text), " ")
	runes := []rune(trimmed)
	if len(runes) <= maxLength {
		return trimmed
	}
	return strings.TrimRight(string(runes[:maxLength]), " ") + "…"
}
