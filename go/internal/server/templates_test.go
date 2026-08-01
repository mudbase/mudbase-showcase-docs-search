package server

import (
	"bytes"
	"net/http/httptest"
	"testing"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/models"
)

// TestLoadTemplates verifies every page template parses cleanly from the embedded FS - a missing
// or misnamed template file, or a broken {{define "content"}} block, fails this test instead of
// the first real visit to that page.
func TestLoadTemplates(t *testing.T) {
	if _, err := loadTemplates(); err != nil {
		t.Fatalf("loadTemplates: %v", err)
	}
}

// TestRenderEveryPage exercises Templates.Render against representative view data for every page
// this app serves, catching template execution errors (nil dereferences, missing fields, bad
// range/if usage) without needing a live Mudbase session.
func TestRenderEveryPage(t *testing.T) {
	tmpl, err := loadTemplates()
	if err != nil {
		t.Fatalf("loadTemplates: %v", err)
	}

	base := Base{Title: "Test", IsSignedIn: true, DisplayName: "Ada Lovelace", UserID: "000000000000000000000001"}

	doc := models.Document{
		ID:         "000000000000000000000002",
		CreatedAt:  "2026-08-01T00:00:00Z",
		UpdatedAt:  "2026-08-01T00:00:00Z",
		Title:      "Password Reset Guide",
		Content:    "To reset your password, go to Settings and click Reset.",
		Tags:       "billing, accounts",
		AuthorID:   "000000000000000000000001",
		AuthorName: "Ada Lovelace",
	}
	docView := newDocumentView(doc, base.UserID)

	cases := []struct {
		name string
		data interface{}
	}{
		{"home.html", LibraryData{Base: base, Documents: []DocumentView{docView}, Empty: false, Query: "password"}},
		{"home.html (empty)", LibraryData{Base: base, Documents: nil, Empty: true, Query: ""}},
		{"document_detail.html", DocumentDetailData{Base: base, Document: docView}},
		{"document_form.html (new)", DocumentFormData{Base: base, Mode: "new"}},
		{"document_form.html (edit)", DocumentFormData{Base: base, Mode: "edit", DocumentID: doc.ID, Title: doc.Title, Content: doc.Content, Tags: doc.Tags}},
		{"ask.html", AskData{
			Base:      base,
			Question:  "How do I reset my password?",
			Answer:    "Go to Settings and click Reset. (Password Reset Guide)",
			Citations: []AskCitationView{{DocumentID: doc.ID, Title: doc.Title}},
			RecentSearches: []RecentSearchView{
				{QueryText: "reset password", ResultCount: 1, RelativeLabel: "5m ago"},
			},
		}},
		{"ask.html (no match)", AskData{Base: base, Question: "xyz", NoMatch: true}},
		{"login.html", LoginData{Base: base, Redirect: "/documents/new"}},
		{"register.html", RegisterData{Base: base}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			templateName := tc.name
			for i, r := range templateName {
				if r == ' ' || r == '(' {
					templateName = templateName[:i]
					break
				}
			}
			var buf bytes.Buffer
			rec := httptest.NewRecorder()
			rec.Body = &buf
			if err := tmpl.Render(rec, 200, templateName, tc.data); err != nil {
				t.Fatalf("rendering %s: %v", templateName, err)
			}
			if buf.Len() == 0 {
				t.Fatalf("rendering %s produced no output", templateName)
			}
		})
	}
}
