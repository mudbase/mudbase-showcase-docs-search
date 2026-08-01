// Package session wraps gorilla/sessions to hold the visitor's per-request state - the
// Mudbase-issued JWT and a cached snapshot of the signed-in user - in a signed, encrypted, httpOnly
// cookie. The JWT never reaches client-side JavaScript because there is none: every page is
// server-rendered, so the cookie is the only place a token can live.
package session

import (
	"crypto/sha256"
	"fmt"
	"net/http"

	"github.com/gorilla/sessions"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/mbase"
)

const cookieName = "mudbase_showcase_docs_search_session"

const (
	keyAccessToken  = "access_token"
	keyRefreshToken = "refresh_token"
	keyUserID       = "user_id"
	keyEmail        = "email"
	keyFirstName    = "first_name"
	keyLastName     = "last_name"
	keyCustomRole   = "custom_role"
	keyIsAnonymous  = "is_anonymous"
)

const thirtyDaysSeconds = 60 * 60 * 24 * 30

// Store is the app-wide cookie session store.
type Store struct {
	cookies *sessions.CookieStore
}

// New builds a Store whose signing/encryption keys are derived deterministically from secret, so
// sessions created before a restart remain valid afterward (a random key per process would log
// out every visitor on every deploy). secret must be at least 32 bytes - enforced in
// internal/config.
func New(secret string, secureCookie bool) *Store {
	hashKey := sha256.Sum256([]byte(secret + ":hash"))
	blockKey := sha256.Sum256([]byte(secret + ":block"))

	cookies := sessions.NewCookieStore(hashKey[:], blockKey[:])
	cookies.Options = &sessions.Options{
		Path:     "/",
		MaxAge:   thirtyDaysSeconds,
		HttpOnly: true,
		Secure:   secureCookie,
		SameSite: http.SameSiteLaxMode,
	}
	return &Store{cookies: cookies}
}

// Data is the decoded session for one request, mutated in place and persisted via Save.
type Data struct {
	sess *sessions.Session
}

// Load reads (or, on first visit / a corrupted cookie, initializes) the session for r.
func (s *Store) Load(r *http.Request) (*Data, error) {
	sess, err := s.cookies.Get(r, cookieName)
	if err != nil {
		// gorilla/sessions returns both an error AND a new empty session when the cookie is
		// missing, expired, or fails to decode (e.g. after a SESSION_SECRET rotation) - treating
		// that as "start a fresh session" is correct here; only a nil session is unrecoverable.
		if sess == nil {
			return nil, fmt.Errorf("session: loading cookie: %w", err)
		}
	}
	return &Data{sess: sess}, nil
}

// Save persists any changes made to d back onto the response as a Set-Cookie header.
func (d *Data) Save(w http.ResponseWriter, r *http.Request) error {
	if err := d.sess.Save(r, w); err != nil {
		return fmt.Errorf("session: saving cookie: %w", err)
	}
	return nil
}

func (d *Data) str(key string) string {
	v, _ := d.sess.Values[key].(string)
	return v
}

func (d *Data) boolean(key string) bool {
	v, _ := d.sess.Values[key].(bool)
	return v
}

// AccessToken returns the current Mudbase bearer token, or "" before any session is established.
func (d *Data) AccessToken() string { return d.str(keyAccessToken) }

// RefreshToken returns the current Mudbase refresh token, or "" before any session is established
// (or after a refresh whose response - unexpectedly - omitted one).
func (d *Data) RefreshToken() string { return d.str(keyRefreshToken) }

// UserID returns the signed-in (or anonymous) user's Mudbase ID.
func (d *Data) UserID() string { return d.str(keyUserID) }

// Email returns the current user's email address.
func (d *Data) Email() string { return d.str(keyEmail) }

// FirstName returns the current user's first name.
func (d *Data) FirstName() string { return d.str(keyFirstName) }

// LastName returns the current user's last name.
func (d *Data) LastName() string { return d.str(keyLastName) }

// DisplayName returns "First Last" for the signed-in user, matching how authorName is written on
// create (see server/handlers_documents.go).
func (d *Data) DisplayName() string {
	first, last := d.FirstName(), d.LastName()
	if first == "" && last == "" {
		return "Member"
	}
	if last == "" {
		return first
	}
	if first == "" {
		return last
	}
	return first + " " + last
}

// CustomRole returns the Mudbase Multi-Role customRole ("customer", or "" for a guest).
func (d *Data) CustomRole() string { return d.str(keyCustomRole) }

// IsAnonymous reports whether the current session is a guest (systemRole "viewer") session.
func (d *Data) IsAnonymous() bool { return d.boolean(keyIsAnonymous) }

// IsSignedIn reports whether this is a real (non-anonymous) account - mirrors the reference web
// app's useAuth: `!!user && user.isAnonymous !== true && !!user.customRole`.
func (d *Data) IsSignedIn() bool {
	return d.UserID() != "" && !d.IsAnonymous() && d.CustomRole() != ""
}

// SetUser stores the given auth result as the session's current identity.
func (d *Data) SetUser(auth mbase.AuthResult) {
	d.sess.Values[keyAccessToken] = auth.Token
	d.sess.Values[keyRefreshToken] = auth.RefreshToken
	d.sess.Values[keyUserID] = auth.User.ID
	d.sess.Values[keyEmail] = auth.User.Email
	d.sess.Values[keyFirstName] = auth.User.FirstName
	d.sess.Values[keyLastName] = auth.User.LastName
	d.sess.Values[keyCustomRole] = auth.User.CustomRole
	d.sess.Values[keyIsAnonymous] = auth.User.IsAnonymous
}

// SetTokens replaces just the access/refresh token pair, leaving every other identity field (user
// ID, name, role, ...) untouched - used after a transparent token refresh (internal/mbase.Refresh),
// whose response carries no `user` object to re-derive those fields from.
func (d *Data) SetTokens(accessToken, refreshToken string) {
	d.sess.Values[keyAccessToken] = accessToken
	d.sess.Values[keyRefreshToken] = refreshToken
}

// ClearUser wipes identity fields (used on logout) - the visitor immediately gets a fresh
// anonymous session on their next request via the session middleware.
func (d *Data) ClearUser() {
	delete(d.sess.Values, keyAccessToken)
	delete(d.sess.Values, keyRefreshToken)
	delete(d.sess.Values, keyUserID)
	delete(d.sess.Values, keyEmail)
	delete(d.sess.Values, keyFirstName)
	delete(d.sess.Values, keyLastName)
	delete(d.sess.Values, keyCustomRole)
	delete(d.sess.Values, keyIsAnonymous)
}
