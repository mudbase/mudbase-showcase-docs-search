package mbase

import (
	"context"
	"encoding/json"
	"fmt"
)

// ListParams mirrors the query options the real ListData endpoint accepts (see
// mudbase-sdk/go/docs/DataApi.md): Mongo-style filter (JSON-encoded), sort string, and pagination.
type ListParams struct {
	Filter map[string]interface{}
	Sort   string
	Page   int32
	Limit  int32
}

// ListResult is a typed, decoded page of collection documents plus pagination metadata.
type ListResult[T any] struct {
	Data       []T
	Page       int32
	Limit      int32
	Total      int32
	TotalPages int32
}

// decodeInto re-marshals a document (a map[string]interface{} from DataResponse, or a
// DataListResponseDataInner whose own MarshalJSON merges _id/createdAt/updatedAt with its
// AdditionalProperties map) into a concrete Go struct. This round-trip is the simplest correct way
// to turn Mudbase's schemaless collection documents into this app's typed Document/SearchLogEntry
// structs without hand-writing a type switch over map[string]interface{} for every field.
func decodeInto[T any](raw interface{}) (T, error) {
	var out T
	b, err := json.Marshal(raw)
	if err != nil {
		return out, fmt.Errorf("mbase: encoding document for decode: %w", err)
	}
	if err := json.Unmarshal(b, &out); err != nil {
		return out, fmt.Errorf("mbase: decoding document into %T: %w", out, err)
	}
	return out, nil
}

// List fetches a page of documents from collectionID, decoded into T. On a 401 (expired access
// token), and if ctx carries a TokenRefresher (see refresh.go - wired by
// internal/server/middleware.go's sessionMiddleware), it refreshes the token and retries once
// before giving up - so an expired session degrades to "quietly renewed" rather than a raw 401
// bubbling up to the visitor.
func List[T any](ctx context.Context, c *Client, token, collectionID string, params ListParams) (ListResult[T], error) {
	var result ListResult[T]
	err := callWithRefresh(ctx, token, func(tok string) error {
		req := c.SDK.DataAPI.ListData(authedContext(ctx, tok), c.cfg.ProjectID, collectionID)
		if params.Page > 0 {
			req = req.Page(params.Page)
		}
		if params.Limit > 0 {
			req = req.Limit(params.Limit)
		}
		if params.Sort != "" {
			req = req.Sort(params.Sort)
		}
		if len(params.Filter) > 0 {
			filterJSON, encodeErr := json.Marshal(params.Filter)
			if encodeErr != nil {
				return fmt.Errorf("mbase: encoding filter for %s: %w", collectionID, encodeErr)
			}
			req = req.Filter(string(filterJSON))
		}

		resp, _, execErr := req.Execute()
		if execErr != nil {
			return execErr
		}

		pagination := resp.GetPagination()
		page := ListResult[T]{
			Page:       pagination.GetPage(),
			Limit:      pagination.GetLimit(),
			Total:      pagination.GetTotal(),
			TotalPages: pagination.GetTotalPages(),
		}
		for _, item := range resp.GetData() {
			decoded, decodeErr := decodeInto[T](item)
			if decodeErr != nil {
				return decodeErr
			}
			page.Data = append(page.Data, decoded)
		}
		result = page
		return nil
	})
	if err != nil {
		return ListResult[T]{}, wrapAPIError(fmt.Sprintf("mbase: listing %s", collectionID), err)
	}
	return result, nil
}

// Get fetches a single document by ID, decoded into T. See List's doc comment for the 401-refresh
// behavior shared by every function in this file.
func Get[T any](ctx context.Context, c *Client, token, collectionID, documentID string) (T, error) {
	var result T
	err := callWithRefresh(ctx, token, func(tok string) error {
		resp, _, execErr := c.SDK.DataAPI.GetData(authedContext(ctx, tok), c.cfg.ProjectID, collectionID, documentID).Execute()
		if execErr != nil {
			return execErr
		}
		decoded, decodeErr := decodeInto[T](resp.GetData())
		if decodeErr != nil {
			return decodeErr
		}
		result = decoded
		return nil
	})
	if err != nil {
		var zero T
		return zero, wrapAPIError(fmt.Sprintf("mbase: fetching %s/%s", collectionID, documentID), err)
	}
	return result, nil
}

// Create inserts a new document into collectionID and returns the created, decoded document. See
// List's doc comment for the 401-refresh behavior shared by every function in this file.
func Create[T any](ctx context.Context, c *Client, token, collectionID string, body map[string]interface{}) (T, error) {
	var result T
	err := callWithRefresh(ctx, token, func(tok string) error {
		resp, _, execErr := c.SDK.DataAPI.CreateData(authedContext(ctx, tok), c.cfg.ProjectID, collectionID).Body(body).Execute()
		if execErr != nil {
			return execErr
		}
		decoded, decodeErr := decodeInto[T](resp.GetData())
		if decodeErr != nil {
			return decodeErr
		}
		result = decoded
		return nil
	})
	if err != nil {
		var zero T
		return zero, wrapAPIError(fmt.Sprintf("mbase: creating %s document", collectionID), err)
	}
	return result, nil
}

// Update patches an existing document and returns the updated, decoded document. See List's doc
// comment for the 401-refresh behavior shared by every function in this file.
func Update[T any](ctx context.Context, c *Client, token, collectionID, documentID string, body map[string]interface{}) (T, error) {
	var result T
	err := callWithRefresh(ctx, token, func(tok string) error {
		resp, _, execErr := c.SDK.DataAPI.UpdateData(authedContext(ctx, tok), c.cfg.ProjectID, collectionID, documentID).Body(body).Execute()
		if execErr != nil {
			return execErr
		}
		decoded, decodeErr := decodeInto[T](resp.GetData())
		if decodeErr != nil {
			return decodeErr
		}
		result = decoded
		return nil
	})
	if err != nil {
		var zero T
		return zero, wrapAPIError(fmt.Sprintf("mbase: updating %s/%s", collectionID, documentID), err)
	}
	return result, nil
}

// Delete removes a document by ID. See List's doc comment for the 401-refresh behavior shared by
// every function in this file.
func Delete(ctx context.Context, c *Client, token, collectionID, documentID string) error {
	err := callWithRefresh(ctx, token, func(tok string) error {
		_, _, execErr := c.SDK.DataAPI.DeleteData(authedContext(ctx, tok), c.cfg.ProjectID, collectionID, documentID).Execute()
		return execErr
	})
	if err != nil {
		return wrapAPIError(fmt.Sprintf("mbase: deleting %s/%s", collectionID, documentID), err)
	}
	return nil
}
