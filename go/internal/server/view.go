package server

import "github.com/mudbase/mudbase-showcase-docs-search/go/internal/models"

// Base holds the fields every page's layout needs (header nav, flash banner). It is embedded in
// every page-specific data struct so templates can read `.IsSignedIn`, `.Flash`, etc. directly at
// the top level via Go's promoted-field rules.
type Base struct {
	Title        string
	IsSignedIn   bool
	DisplayName  string
	UserID       string
	FlashError   string
	FlashSuccess string
}

// DocumentView is a display-ready document: every derived value (author initials, formatted date,
// parsed tag list, card snippet, this viewer's ownership) is computed once here instead of in the
// template.
type DocumentView struct {
	models.Document
	CreatedLabel   string
	AuthorInitials string
	Tags           []string
	Snippet        string
	IsOwner        bool
}

func newDocumentView(doc models.Document, currentUserID string) DocumentView {
	return DocumentView{
		Document:       doc,
		CreatedLabel:   formatDate(doc.CreatedAt),
		AuthorInitials: initials(doc.AuthorName),
		Tags:           parseTags(doc.Tags),
		Snippet:        snippet(doc.Content, 160),
		IsOwner:        currentUserID != "" && doc.AuthorID == currentUserID,
	}
}

func newDocumentViews(documents []models.Document, currentUserID string) []DocumentView {
	views := make([]DocumentView, 0, len(documents))
	for _, doc := range documents {
		views = append(views, newDocumentView(doc, currentUserID))
	}
	return views
}

// RecentSearchView is a display-ready search_log entry for the /ask page's "Recent searches"
// panel.
type RecentSearchView struct {
	QueryText     string
	ResultCount   int64
	RelativeLabel string
}

func newRecentSearchViews(entries []models.SearchLogEntry) []RecentSearchView {
	views := make([]RecentSearchView, 0, len(entries))
	for _, entry := range entries {
		views = append(views, RecentSearchView{
			QueryText:     entry.QueryText,
			ResultCount:   entry.ResultCount,
			RelativeLabel: formatRelativeTime(entry.CreatedAt),
		})
	}
	return views
}

// AskCitationView is a display-ready Ask AI citation, linking back to its source document.
type AskCitationView struct {
	DocumentID string
	Title      string
}
