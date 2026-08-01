package server

import (
	"context"
	"net/http"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/session"
)

type contextKey int

const sessionContextKey contextKey = iota

// withSession returns a copy of r carrying data in its context, retrievable via sessionFrom.
func withSession(r *http.Request, data *session.Data) *http.Request {
	return r.WithContext(context.WithValue(r.Context(), sessionContextKey, data))
}

// sessionFrom returns the session.Data the middleware attached to r. It panics if called on a
// request that didn't go through the session middleware - every route in this app does, so that
// indicates a routing bug, not a runtime condition to recover from gracefully.
func sessionFrom(r *http.Request) *session.Data {
	data, ok := r.Context().Value(sessionContextKey).(*session.Data)
	if !ok {
		panic("server: request has no session.Data in context - session middleware was not applied")
	}
	return data
}
