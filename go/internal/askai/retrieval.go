// Package askai implements the Ask AI request pipeline this showcase exists to demonstrate: a
// deployed Mudbase Function does retrieval-ranking (the only network-free work it's structurally
// capable of - see functioninvoke.go's doc comment), and a small, unavoidable server-side call to
// Anthropic's Claude API produces the grounded completion (llm.go). This package intentionally
// holds no HTTP handlers - internal/server/handlers_ask.go orchestrates it.
package askai

import (
	"regexp"
	"sort"
	"strings"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/models"
)

// tokenPattern splits free text into alphanumeric runs, mirroring the reference web app's
// tokenizeQuery (web/src/lib/utils.ts: `text.toLowerCase().split(/[^a-z0-9]+/)`).
var tokenPattern = regexp.MustCompile(`[a-z0-9]+`)

// tokenizeQuery splits text into lowercase alphanumeric tokens of length > 2, deduplicated -
// mirrors web/src/lib/utils.ts's tokenizeQuery exactly (including the length-3 minimum).
func tokenizeQuery(text string) []string {
	matches := tokenPattern.FindAllString(strings.ToLower(text), -1)
	seen := make(map[string]bool, len(matches))
	tokens := make([]string, 0, len(matches))
	for _, tok := range matches {
		if len(tok) <= 2 || seen[tok] {
			continue
		}
		seen[tok] = true
		tokens = append(tokens, tok)
	}
	return tokens
}

// countOccurrences is a case-insensitive substring occurrence count, mirroring
// web/src/lib/utils.ts's countOccurrences exactly (including its non-overlapping scan).
func countOccurrences(text, term string) int {
	if term == "" {
		return 0
	}
	haystack := strings.ToLower(text)
	needle := strings.ToLower(term)
	count := 0
	pos := 0
	for {
		idx := strings.Index(haystack[pos:], needle)
		if idx == -1 {
			break
		}
		count++
		pos += idx + len(needle)
	}
	return count
}

// ScoredDocument pairs a document with its client-side keyword-retrieval score.
type ScoredDocument struct {
	Document models.Document
	Score    int
}

// ScoreDocuments scores each document by counting query-term occurrences across title (weight 3),
// tags (weight 2), and content (weight 1), returning only documents with a positive score, ranked
// highest-first - mirrors web/src/lib/retrieval.ts's scoreDocuments exactly. No vector DB, no
// external search service: simple substring matching, per plan/build-plan.md.
func ScoreDocuments(documents []models.Document, query string) []ScoredDocument {
	terms := tokenizeQuery(query)
	if len(terms) == 0 {
		return nil
	}

	scored := make([]ScoredDocument, 0, len(documents))
	for _, doc := range documents {
		score := 0
		for _, term := range terms {
			score += countOccurrences(doc.Title, term) * 3
			score += countOccurrences(doc.Tags, term) * 2
			score += countOccurrences(doc.Content, term)
		}
		if score > 0 {
			scored = append(scored, ScoredDocument{Document: doc, Score: score})
		}
	}

	sort.SliceStable(scored, func(i, j int) bool { return scored[i].Score > scored[j].Score })
	return scored
}

// maxCandidateContentChars bounds each candidate's content in the Ask AI request payload, mirroring
// web/src/lib/retrieval.ts's MAX_CANDIDATE_CONTENT_CHARS.
const maxCandidateContentChars = 4000

// Candidate is one shortlisted document sent to the retrieval Function's payload.
type Candidate struct {
	DocumentID string `json:"documentId"`
	Title      string `json:"title"`
	Content    string `json:"content"`
	Tags       string `json:"tags,omitempty"`
}

// TopCandidates takes the top `limit` scored documents and builds the Function payload shape,
// truncating each document's content to bound payload size - mirrors
// web/src/lib/retrieval.ts's topCandidates exactly.
func TopCandidates(scored []ScoredDocument, limit int) []Candidate {
	if limit > len(scored) {
		limit = len(scored)
	}
	candidates := make([]Candidate, 0, limit)
	for _, entry := range scored[:limit] {
		content := entry.Document.Content
		if len(content) > maxCandidateContentChars {
			content = content[:maxCandidateContentChars]
		}
		candidates = append(candidates, Candidate{
			DocumentID: entry.Document.ID,
			Title:      entry.Document.Title,
			Content:    content,
			Tags:       entry.Document.Tags,
		})
	}
	return candidates
}
