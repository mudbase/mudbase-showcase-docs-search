// Package store implements every domain operation this app needs against the two Mudbase
// collections (documents, search_log), on top of internal/mbase's generic CRUD helpers.
package store

import (
	"context"
	"fmt"
	"strings"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/models"
)

// libraryFetchLimit mirrors the reference web app's library page load size
// (web/src/app/page.tsx: `useDocuments(..., { limit: 100 })`) - the search box then filters that
// loaded set client-side rather than re-querying Mudbase per keystroke. This Go port does the
// equivalent filtering server-side (see Library below) since there is no client-side JS state to
// hold a loaded-but-unfiltered set across requests.
const libraryFetchLimit = 100

// askCandidatePoolLimit mirrors the reference web app's Ask AI panel, which scores against the
// same up-to-200-document set it loads for the library
// (web/src/components/ask/AskAIPanel.tsx: `useDocuments(..., { limit: 200 })`).
const askCandidatePoolLimit = 200

// DocumentService implements every operation the app needs against the `documents` collection.
type DocumentService struct {
	client       *mbase.Client
	collectionID string
}

// NewDocumentService builds a DocumentService bound to the given documents collection ID.
func NewDocumentService(client *mbase.Client, documentsCollectionID string) *DocumentService {
	return &DocumentService{client: client, collectionID: documentsCollectionID}
}

// fetchAll lists up to limit documents, newest first - the shared read path behind both Library
// and CandidatePool.
func (s *DocumentService) fetchAll(ctx context.Context, token string, limit int32) ([]models.Document, error) {
	result, err := mbase.List[models.Document](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Sort:  "-createdAt",
		Limit: limit,
	})
	if err != nil {
		return nil, fmt.Errorf("store: listing documents: %w", err)
	}
	return result.Data, nil
}

// matchesSearchTerm reports whether document matches term via a case-insensitive substring check
// across title, content, and tags - mirrors the reference web app's matchesSearchTerm
// (web/src/lib/retrieval.ts): no vector DB, no external search service, simple substring matching.
func matchesSearchTerm(doc models.Document, term string) bool {
	term = strings.TrimSpace(term)
	if term == "" {
		return true
	}
	needle := strings.ToLower(term)
	return strings.Contains(strings.ToLower(doc.Title), needle) ||
		strings.Contains(strings.ToLower(doc.Content), needle) ||
		strings.Contains(strings.ToLower(doc.Tags), needle)
}

// Library fetches the library page's document set (newest first, up to libraryFetchLimit) and, if
// query is non-empty, filters it server-side by matchesSearchTerm - the Go-server-rendered
// equivalent of the reference web app's client-side keyword filter over an already-loaded set.
func (s *DocumentService) Library(ctx context.Context, token, query string) ([]models.Document, error) {
	all, err := s.fetchAll(ctx, token, libraryFetchLimit)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(query) == "" {
		return all, nil
	}
	filtered := make([]models.Document, 0, len(all))
	for _, doc := range all {
		if matchesSearchTerm(doc, query) {
			filtered = append(filtered, doc)
		}
	}
	return filtered, nil
}

// CandidatePool fetches the full document set Ask AI scores against - same read as Library with
// query="", just a larger page size (see askCandidatePoolLimit's doc comment).
func (s *DocumentService) CandidatePool(ctx context.Context, token string) ([]models.Document, error) {
	return s.fetchAll(ctx, token, askCandidatePoolLimit)
}

// ByID fetches a single document by its Mudbase document ID.
func (s *DocumentService) ByID(ctx context.Context, token, id string) (models.Document, error) {
	doc, err := mbase.Get[models.Document](ctx, s.client, token, s.collectionID, id)
	if err != nil {
		return models.Document{}, fmt.Errorf("store: fetching document %s: %w", id, err)
	}
	return doc, nil
}

// CreateInput bundles the fields a new document needs beyond its author identity.
type CreateInput struct {
	Title   string
	Content string
	Tags    string
}

// Create inserts a new document owned by authorID/authorName.
func (s *DocumentService) Create(ctx context.Context, token, authorID, authorName string, input CreateInput) (models.Document, error) {
	body := map[string]interface{}{
		"title":      input.Title,
		"content":    input.Content,
		"tags":       input.Tags,
		"authorId":   authorID,
		"authorName": authorName,
	}
	doc, err := mbase.Create[models.Document](ctx, s.client, token, s.collectionID, body)
	if err != nil {
		return models.Document{}, fmt.Errorf("store: creating document: %w", err)
	}
	return doc, nil
}

// UpdateInput bundles the fields an edit can change. authorId/authorName are deliberately not
// editable - mirrors the reference web app's EditDocumentPage, which only ever PATCHes
// title/content/tags.
type UpdateInput struct {
	Title   string
	Content string
	Tags    string
}

// Update patches an existing document's title/content/tags and returns the updated document.
func (s *DocumentService) Update(ctx context.Context, token, id string, input UpdateInput) (models.Document, error) {
	doc, err := mbase.Update[models.Document](ctx, s.client, token, s.collectionID, id, map[string]interface{}{
		"title":   input.Title,
		"content": input.Content,
		"tags":    input.Tags,
	})
	if err != nil {
		return models.Document{}, fmt.Errorf("store: updating document %s: %w", id, err)
	}
	return doc, nil
}

// Delete removes a document by ID.
func (s *DocumentService) Delete(ctx context.Context, token, id string) error {
	if err := mbase.Delete(ctx, s.client, token, s.collectionID, id); err != nil {
		return fmt.Errorf("store: deleting document %s: %w", id, err)
	}
	return nil
}
