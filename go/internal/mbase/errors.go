package mbase

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	mudbase "github.com/mudbase/mudbase-sdk/go"
)

// wireError is the common {"error": "...", "message": "...", "code": "..."} shape Mudbase's REST
// API returns on failure - the SDK's GenericOpenAPIError body uses it, as does this package's
// raw-HTTP registration workaround (see auth.go's Register). Code carries machine-readable error
// identifiers like "EMAIL_VERIFICATION_REQUIRED" (see IsEmailVerificationRequired below).
type wireError struct {
	Error   string `json:"error"`
	Message string `json:"message"`
	Code    string `json:"code"`
}

// userFacingError carries a message already clean enough to show a visitor directly (extracted
// from a wire {error}/{message} body outside the generated SDK's own error path - see Register's
// raw HTTP call). FriendlyMessage recognizes it so callers don't have to care which code path
// produced the error.
type userFacingError struct {
	message string
}

func (e *userFacingError) Error() string { return e.message }

func newUserFacingError(message string) error {
	return &userFacingError{message: message}
}

// FriendlyMessage extracts a human-readable message from an error returned by this package. The
// generated SDK client wraps every non-2xx response in a *mudbase.GenericOpenAPIError carrying the
// raw response body (see mudbase-sdk/go/client.go); this unwraps that body's {error} or {message}
// field instead of surfacing the generic "400 Bad Request"-style Error() string. It also
// recognizes userFacingError, produced by this package's own raw-HTTP workaround.
func FriendlyMessage(err error) string {
	if err == nil {
		return ""
	}

	var userErr *userFacingError
	if errors.As(err, &userErr) {
		return userErr.message
	}

	var apiErr *mudbase.GenericOpenAPIError
	if errors.As(err, &apiErr) {
		var wire wireError
		if jsonErr := json.Unmarshal(apiErr.Body(), &wire); jsonErr == nil {
			if wire.Error != "" {
				return wire.Error
			}
			if wire.Message != "" {
				return wire.Message
			}
		}
	}
	return err.Error()
}

// wrapAPIError produces a consistently-formatted, %w-wrapped error carrying the friendly message
// as context, per this project's "every error wrapped with fmt.Errorf" rule.
func wrapAPIError(action string, err error) error {
	return fmt.Errorf("%s: %s: %w", action, FriendlyMessage(err), err)
}

// IsEmailVerificationRequired reports whether err carries the wire code "EMAIL_VERIFICATION_
// REQUIRED" - mirrors the reference web app's errorCode(err) === "EMAIL_VERIFICATION_REQUIRED"
// check (web/src/hooks/useAuth.ts), used to show a specific "check your inbox" message on login
// rather than the generic credentials-rejected error.
func IsEmailVerificationRequired(err error) bool {
	if err == nil {
		return false
	}
	var apiErr *mudbase.GenericOpenAPIError
	if errors.As(err, &apiErr) {
		var wire wireError
		if jsonErr := json.Unmarshal(apiErr.Body(), &wire); jsonErr == nil {
			return wire.Code == "EMAIL_VERIFICATION_REQUIRED"
		}
	}
	return false
}

// IsUnauthorized reports whether err represents an HTTP 401 response from the Mudbase API - an
// expired or invalid access token, as opposed to any other 4xx/5xx failure a token refresh cannot
// fix. The generated SDK client records the response's Status string (e.g. "401 Unauthorized") as
// GenericOpenAPIError's error field (see mudbase-sdk/go/client.go's callAPI), so that's what this
// checks against rather than a parsed status code the SDK doesn't expose.
func IsUnauthorized(err error) bool {
	if err == nil {
		return false
	}
	var apiErr *mudbase.GenericOpenAPIError
	if errors.As(err, &apiErr) {
		return strings.HasPrefix(apiErr.Error(), "401")
	}
	return false
}
