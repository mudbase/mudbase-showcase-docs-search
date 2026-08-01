package store

import (
	"context"
	"fmt"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/models"
)

// recentSearchesLimit mirrors the reference web app's RecentSearches panel
// (web/src/components/ask/RecentSearches.tsx: `useDocuments(..., { limit: 10 })`).
const recentSearchesLimit = 10

// SearchLogService implements every operation the app needs against the `search_log` collection.
type SearchLogService struct {
	client       *mbase.Client
	collectionID string
}

// NewSearchLogService builds a SearchLogService bound to the given search_log collection ID.
func NewSearchLogService(client *mbase.Client, searchLogCollectionID string) *SearchLogService {
	return &SearchLogService{client: client, collectionID: searchLogCollectionID}
}

// Log records one Ask AI query. userID/userName are passed as "" for a guest/anonymous searcher -
// Log omits both fields from the write entirely in that case rather than writing a placeholder
// string, exactly matching the reference web app's AskAIPanel spread-conditional
// (`...(user?.id ? { userId: user.id } : {})`) and this task's own instruction that any *Id filter
// field must be a real ObjectId or simply absent, never a placeholder.
func (s *SearchLogService) Log(ctx context.Context, token, queryText, userID, userName string, resultCount int) error {
	body := map[string]interface{}{
		"queryText":   queryText,
		"resultCount": resultCount,
	}
	if userID != "" {
		body["userId"] = userID
	}
	if userName != "" {
		body["userName"] = userName
	}
	if _, err := mbase.Create[models.SearchLogEntry](ctx, s.client, token, s.collectionID, body); err != nil {
		return fmt.Errorf("store: logging search %q: %w", queryText, err)
	}
	return nil
}

// Recent returns the most recent search_log entries, newest first, for the "Recent searches"
// panel on the /ask page.
func (s *SearchLogService) Recent(ctx context.Context, token string) ([]models.SearchLogEntry, error) {
	result, err := mbase.List[models.SearchLogEntry](ctx, s.client, token, s.collectionID, mbase.ListParams{
		Sort:  "-createdAt",
		Limit: recentSearchesLimit,
	})
	if err != nil {
		return nil, fmt.Errorf("store: listing recent searches: %w", err)
	}
	return result.Data, nil
}
