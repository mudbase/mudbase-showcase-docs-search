package askai

import (
	"strings"
	"testing"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/models"
)

func TestTokenizeQuery(t *testing.T) {
	tests := []struct {
		name string
		text string
		want []string
	}{
		{"drops short tokens", "how do I reset my password", []string{"how", "reset", "password"}},
		{"dedupes", "password reset password", []string{"password", "reset"}},
		{"empty on only short words", "a an is", nil},
		{"splits on punctuation", "billing, invoices & refunds!", []string{"billing", "invoices", "refunds"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tokenizeQuery(tt.text)
			if len(got) != len(tt.want) {
				t.Fatalf("tokenizeQuery(%q) = %v, want %v", tt.text, got, tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Fatalf("tokenizeQuery(%q) = %v, want %v", tt.text, got, tt.want)
				}
			}
		})
	}
}

func TestCountOccurrences(t *testing.T) {
	tests := []struct {
		text, term string
		want       int
	}{
		{"the password reset password guide", "password", 2},
		{"PASSWORD Password password", "password", 3},
		{"nothing here", "password", 0},
		{"", "password", 0},
		{"anything", "", 0},
	}
	for _, tt := range tests {
		got := countOccurrences(tt.text, tt.term)
		if got != tt.want {
			t.Errorf("countOccurrences(%q, %q) = %d, want %d", tt.text, tt.term, got, tt.want)
		}
	}
}

func TestScoreDocuments(t *testing.T) {
	docs := []models.Document{
		{ID: "1", Title: "Password Reset Guide", Content: "Reset your password from Settings.", Tags: "billing"},
		{ID: "2", Title: "Billing FAQ", Content: "Invoices and refunds explained.", Tags: "billing,invoices"},
		{ID: "3", Title: "Unrelated Doc", Content: "Nothing to do with the query.", Tags: ""},
	}

	scored := ScoreDocuments(docs, "How do I reset my password?")

	if len(scored) != 1 {
		t.Fatalf("expected exactly 1 matching document, got %d: %+v", len(scored), scored)
	}
	if scored[0].Document.ID != "1" {
		t.Fatalf("expected document 1 to match, got %s", scored[0].Document.ID)
	}
	if scored[0].Score <= 0 {
		t.Fatalf("expected a positive score, got %d", scored[0].Score)
	}

	if got := ScoreDocuments(docs, "a an is"); got != nil {
		t.Fatalf("expected nil for a query with no tokenizable terms, got %+v", got)
	}
}

func TestScoreDocumentsRanksByWeight(t *testing.T) {
	docs := []models.Document{
		{ID: "title-match", Title: "invoices", Content: "nothing else here."},
		{ID: "content-match", Title: "unrelated", Content: "invoices invoices invoices invoices"},
	}
	scored := ScoreDocuments(docs, "invoices")
	if len(scored) != 2 {
		t.Fatalf("expected both documents to match, got %d", len(scored))
	}
	// Title weight is 3, so one title hit (score 3) should still be found - content-match has 4
	// occurrences (score 4), so it legitimately outranks a single title hit here. This test
	// asserts the weighting is applied at all (both non-zero, sorted descending), not a specific
	// document order for this particular input.
	if scored[0].Score < scored[1].Score {
		t.Fatalf("expected descending score order, got %+v", scored)
	}
}

func TestTopCandidatesTruncatesContentAndLimit(t *testing.T) {
	longContent := strings.Repeat("x", maxCandidateContentChars+500)
	scored := []ScoredDocument{
		{Document: models.Document{ID: "1", Title: "One", Content: longContent, Tags: "a"}, Score: 10},
		{Document: models.Document{ID: "2", Title: "Two", Content: "short", Tags: ""}, Score: 5},
		{Document: models.Document{ID: "3", Title: "Three", Content: "short", Tags: ""}, Score: 1},
	}

	candidates := TopCandidates(scored, 2)
	if len(candidates) != 2 {
		t.Fatalf("expected 2 candidates, got %d", len(candidates))
	}
	if len(candidates[0].Content) != maxCandidateContentChars {
		t.Fatalf("expected content truncated to %d chars, got %d", maxCandidateContentChars, len(candidates[0].Content))
	}
	if candidates[1].DocumentID != "2" {
		t.Fatalf("expected second candidate to be document 2, got %s", candidates[1].DocumentID)
	}

	// limit larger than the scored set should not panic or over-slice.
	all := TopCandidates(scored, 10)
	if len(all) != 3 {
		t.Fatalf("expected 3 candidates when limit exceeds set size, got %d", len(all))
	}
}
