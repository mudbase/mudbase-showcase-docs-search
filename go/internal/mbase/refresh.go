package mbase

import "context"

// TokenRefresher obtains a fresh Mudbase access token when the one currently in use has expired,
// and persists it wherever the caller keeps session state (the app's encrypted session cookie, in
// this codebase - see internal/server/middleware.go's sessionMiddleware). It returns the new
// access token, or an error if refreshing itself failed (in which case the original 401 is
// surfaced to the caller instead of the refresh error).
//
// This is the corrected pattern: the reference web app's MudbaseClient captures refreshToken on
// login and rewires it through every retried request via refreshAccessToken() (see
// web/src/lib/mudbase.ts) - the bug class every sibling port of this showcase had to find and fix
// was capturing a refresh token at auth time and then never actually using it on a 401. Wiring
// TokenRefresher through request context (below) and into every mbase.List/Get/Create/Update/
// Delete call (see data.go's callWithRefresh) is what makes the fix structural instead of
// something a future handler could accidentally omit.
type TokenRefresher func(ctx context.Context) (newToken string, err error)

type refresherContextKey struct{}

// WithTokenRefresher attaches refresher to ctx so every List/Get/Create/Update/Delete call made
// with this ctx can transparently refresh an expired access token and retry once on a 401, instead
// of surfacing a raw 401 up to the visitor - mirrors the reference web app's axios-equivalent
// interceptor (web/src/lib/mudbase.ts's request()).
func WithTokenRefresher(ctx context.Context, refresher TokenRefresher) context.Context {
	return context.WithValue(ctx, refresherContextKey{}, refresher)
}

func refresherFrom(ctx context.Context) (TokenRefresher, bool) {
	fn, ok := ctx.Value(refresherContextKey{}).(TokenRefresher)
	return fn, ok
}

// callWithRefresh runs op with token. If op fails with a 401 (mbase.IsUnauthorized), and ctx
// carries a TokenRefresher, it refreshes once and retries op with the new token. Any other error -
// including a refresh failure itself - is returned as-is so the original, more specific error
// reaches the caller.
func callWithRefresh(ctx context.Context, token string, op func(token string) error) error {
	err := op(token)
	if err == nil || !IsUnauthorized(err) {
		return err
	}

	refresher, ok := refresherFrom(ctx)
	if !ok {
		return err
	}

	newToken, refreshErr := refresher(ctx)
	if refreshErr != nil {
		return err
	}

	return op(newToken)
}
