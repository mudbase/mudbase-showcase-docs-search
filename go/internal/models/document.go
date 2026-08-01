// Package models holds this app's typed views of the two Mudbase collections it reads and writes
// (documents, search_log) - see plan/build-plan.md for the full schema.
package models

// Document mirrors the `documents` Mudbase collection schema.
type Document struct {
	ID         string `json:"_id"`
	CreatedAt  string `json:"createdAt"`
	UpdatedAt  string `json:"updatedAt"`
	Title      string `json:"title"`
	Content    string `json:"content"`
	Tags       string `json:"tags,omitempty"` // comma-separated, e.g. "billing,invoices"
	AuthorID   string `json:"authorId"`
	AuthorName string `json:"authorName"`
}
