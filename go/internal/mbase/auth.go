package mbase

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	mudbase "github.com/mudbase/mudbase-sdk/go"
)

// AuthUser is this app's normalized view of a Mudbase end-user, decoded straight from the raw
// JSON response body of every auth call.
//
// Known SDK gap (same one documented in the sibling social/ecommerce ports): the vendored
// mudbase-sdk/go's generated response models for every auth endpoint omit `customRole` and
// `isAnonymous` entirely, even though the live API returns both (confirmed against the reference
// web app's working use of `session.user.customRole` in web/src/lib/mudbase-provider.tsx). Rather
// than losing them, every auth call below still executes through the real generated SDK method
// (for request construction, header/auth wiring, and error handling), then re-decodes the
// *http.Response body it returns into this struct - the generated client preserves that raw body
// via io.NopCloser(bytes.NewBuffer(...)) after its own typed decode, so this is a safe, side-
// effect-free second read, not a duplicate request.
type AuthUser struct {
	ID          string
	Email       string
	FirstName   string
	LastName    string
	Role        string
	CustomRole  string // "" means no app role (anonymous/guest); otherwise "customer".
	IsAnonymous bool
}

// AuthResult is the normalized shape of every auth response this app cares about.
type AuthResult struct {
	Token               string
	RefreshToken        string
	ExpiresIn           int32
	User                AuthUser
	RequireVerification bool // true when the project requires email verification before login.
}

// authWireUser is the raw wire shape of the `user` object on every auth response, capturing the
// fields the generated models omit alongside the ones they do carry.
type authWireUser struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	FirstName   string `json:"firstName"`
	LastName    string `json:"lastName"`
	Role        string `json:"role"`
	CustomRole  string `json:"customRole"`
	IsAnonymous bool   `json:"isAnonymous"`
}

// authWireResponse is the raw wire shape shared by CreateAnonymousSession, LoginLocalUser, and the
// raw-HTTP Register call (see Register below).
type authWireResponse struct {
	Message             string       `json:"message"`
	Token               string       `json:"token"`
	RefreshToken        string       `json:"refreshToken"`
	ExpiresIn           int32        `json:"expiresIn"`
	User                authWireUser `json:"user"`
	RequireVerification bool         `json:"requireVerification"`
}

func decodeAuthBody(body []byte) (AuthResult, error) {
	var wire authWireResponse
	if err := json.Unmarshal(body, &wire); err != nil {
		return AuthResult{}, fmt.Errorf("mbase: decoding auth response body: %w", err)
	}
	return AuthResult{
		Token:               wire.Token,
		RefreshToken:        wire.RefreshToken,
		ExpiresIn:           wire.ExpiresIn,
		RequireVerification: wire.RequireVerification,
		User: AuthUser{
			ID:          wire.User.ID,
			Email:       wire.User.Email,
			FirstName:   wire.User.FirstName,
			LastName:    wire.User.LastName,
			Role:        wire.User.Role,
			CustomRole:  wire.User.CustomRole,
			IsAnonymous: wire.User.IsAnonymous,
		},
	}, nil
}

// readPreservedBody reads the response body the generated SDK preserves via
// io.NopCloser(bytes.NewBuffer(...)) after its own decode, without disturbing anything the caller
// still wants to read (rare, but resets Body afterward so it stays safe to consume again).
func readPreservedBody(resp *http.Response) ([]byte, error) {
	if resp == nil || resp.Body == nil {
		return nil, fmt.Errorf("mbase: no response body to read")
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("mbase: reading response body: %w", err)
	}
	resp.Body.Close()
	resp.Body = io.NopCloser(bytes.NewBuffer(body))
	return body, nil
}

// CreateAnonymousSession establishes a guest session (systemRole "viewer", no customRole) so an
// unauthenticated visitor can browse the document library before ever signing in - every
// collection read on this backend requires *some* authentication, confirmed live (see
// web/plan/build-plan.md "Data model" and "Known limitations"): a completely unauthenticated
// request 401s even against a public-read collection.
func (c *Client) CreateAnonymousSession(ctx context.Context) (AuthResult, error) {
	req := mudbase.NewCreateAnonymousSessionRequest()
	req.SetProjectId(c.cfg.ProjectID)

	_, httpResp, err := c.SDK.AuthenticationAPI.CreateAnonymousSession(ctx).
		CreateAnonymousSessionRequest(*req).
		Execute()
	if err != nil {
		return AuthResult{}, wrapAPIError("mbase: creating anonymous session", err)
	}

	body, err := readPreservedBody(httpResp)
	if err != nil {
		return AuthResult{}, err
	}
	return decodeAuthBody(body)
}

// Login authenticates an existing "customer" account via email/password.
func (c *Client) Login(ctx context.Context, email, password string) (AuthResult, error) {
	req := mudbase.NewLoginLocalUserRequest(email, password)
	req.SetProjectId(c.cfg.ProjectID)

	_, httpResp, err := c.SDK.AuthenticationAPI.LoginLocalUser(ctx).
		LoginLocalUserRequest(*req).
		Execute()
	if err != nil {
		return AuthResult{}, wrapAPIError("mbase: logging in", err)
	}

	body, err := readPreservedBody(httpResp)
	if err != nil {
		return AuthResult{}, err
	}
	return decodeAuthBody(body)
}

// Logout revokes the current session's token server-side. Mudbase's `LogoutLocalUser` needs no
// request body, only the bearer token attached via authedContext.
func (c *Client) Logout(ctx context.Context, token string) error {
	_, _, err := c.SDK.AuthenticationAPI.LogoutLocalUser(authedContext(ctx, token)).Execute()
	if err != nil {
		return wrapAPIError("mbase: logging out", err)
	}
	return nil
}

// Refresh exchanges refreshToken for a new access token + refresh token pair. The previous refresh
// token is invalidated by rotation the moment this succeeds - confirmed against
// mudbase-sdk/go/api_authentication.go's RefreshToken doc comment ("the previous refresh token is
// invalidated ... if the same refresh token is used again, the session is revoked"), so callers
// must persist both returned values, not just the new access token. No bearer token is attached to
// this call; POST /api/auth/refresh authenticates purely via the refresh token in the request
// body. The response carries no `user` object, so the returned AuthResult's User field is left
// zero-valued - callers refreshing an existing session should keep whatever user snapshot they
// already have and only replace the token pair (see internal/server/middleware.go's
// tokenRefresher).
func (c *Client) Refresh(ctx context.Context, refreshToken string) (AuthResult, error) {
	req := mudbase.NewRefreshTokenRequest(refreshToken)

	resp, _, err := c.SDK.AuthenticationAPI.RefreshToken(ctx).
		RefreshTokenRequest(*req).
		Execute()
	if err != nil {
		return AuthResult{}, wrapAPIError("mbase: refreshing access token", err)
	}

	return AuthResult{
		Token:        resp.GetToken(),
		RefreshToken: resp.GetRefreshToken(),
		ExpiresIn:    resp.GetExpiresIn(),
	}, nil
}

// appRole is the Mudbase Multi-Role signup role slug this project ships as its single default
// starter role - confirmed live (same convention documented in the sibling social/ecommerce
// apps): signup against "user" 404s with "Role not found", signup against "customer" succeeds.
const appRole = "customer"

// registerRequestBody is the real REST body for POST /api/auth/local/signup/customer, including
// `agreedToTerms` - a field Mudbase's registration validator requires (a direct call without it
// is rejected) but that this SDK build's generated RegisterWithRoleRequest model does not declare
// as a field at all (confirmed against mudbase-sdk/go/model_register_with_role_request.go: it has
// exactly Email/Password/FirstName/LastName/ProjectId, no AdditionalProperties map either, so
// there is no way to attach an extra key through the typed request builder). Registration is
// therefore issued as a direct HTTP call built the same way the generated
// MultiRoleFeatureAPIService.RegisterWithRoleExecute builds its own request (same path, method,
// headers, base URL from this Client's configuration) rather than through the generated method -
// see README "Known limitations".
type registerRequestBody struct {
	Email         string `json:"email"`
	Password      string `json:"password"`
	FirstName     string `json:"firstName"`
	LastName      string `json:"lastName"`
	ProjectID     string `json:"projectId"`
	AgreedToTerms bool   `json:"agreedToTerms"`
}

// Register creates a new "customer" account and returns the resulting session, exactly like every
// other auth call here (token + user, decoded from the raw JSON body) - unless the project
// requires email verification, in which case RequireVerification is true and Token/RefreshToken
// are empty; callers must not treat that as a signed-in session (see
// internal/server/handlers_auth.go's handleRegisterSubmit).
func (c *Client) Register(ctx context.Context, email, password, firstName, lastName string, agreedToTerms bool) (AuthResult, error) {
	payload := registerRequestBody{
		Email:         email,
		Password:      password,
		FirstName:     firstName,
		LastName:      lastName,
		ProjectID:     c.cfg.ProjectID,
		AgreedToTerms: agreedToTerms,
	}
	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return AuthResult{}, fmt.Errorf("mbase: encoding register request: %w", err)
	}

	url := strings.TrimRight(c.cfg.MudbaseURL, "/") + "/api/auth/local/signup/" + appRole
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return AuthResult{}, fmt.Errorf("mbase: building register request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "application/json")

	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return AuthResult{}, fmt.Errorf("mbase: sending register request: %w", err)
	}
	defer httpResp.Body.Close()

	respBody, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return AuthResult{}, fmt.Errorf("mbase: reading register response: %w", err)
	}

	if httpResp.StatusCode >= 300 {
		var wire wireError
		_ = json.Unmarshal(respBody, &wire)
		message := wire.Error
		if message == "" {
			message = wire.Message
		}
		if message == "" {
			message = fmt.Sprintf("registration failed (%s)", httpResp.Status)
		}
		return AuthResult{}, newUserFacingError(message)
	}

	return decodeAuthBody(respBody)
}
