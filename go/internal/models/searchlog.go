package models

// SearchLogEntry mirrors the `search_log` Mudbase collection schema. UserID/UserName are only
// ever set when the searcher was a real signed-in user - see store.SearchLogService.Log, which
// omits both fields entirely for a guest/anonymous searcher rather than writing a placeholder.
type SearchLogEntry struct {
	ID          string `json:"_id"`
	CreatedAt   string `json:"createdAt"`
	UpdatedAt   string `json:"updatedAt"`
	QueryText   string `json:"queryText"`
	UserID      string `json:"userId,omitempty"`
	UserName    string `json:"userName,omitempty"`
	ResultCount int64  `json:"resultCount"`
}
