// Package mbase wraps the real Mudbase Go SDK (github.com/mudbase/mudbase-sdk/go) with the
// docs-search app's auth and collection-data operations. It intentionally stays thin: every
// method maps to one real SDK call. There is no "unified higher-level client" invented here -
// this is a direct sibling of mudbase-showcase-social/go and mudbase-showcase-ecommerce/go's
// internal/mbase packages. Function invocation (a separate concern - see
// plan/build-plan.md "Ask AI architecture") lives in internal/askai, not here, since it
// authenticates with an org-scoped API key rather than an end-user JWT.
package mbase

import (
	"context"
	"net/http"
	"time"

	mudbase "github.com/mudbase/mudbase-sdk/go"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/config"
)

// Client bundles the generated SDK client with the project configuration every call needs.
type Client struct {
	SDK        *mudbase.APIClient
	cfg        *config.Config
	httpClient *http.Client
}

// New builds a Client from the app configuration, wiring the SDK to point at the configured
// Mudbase server exactly as documented: NewConfiguration() then override Servers.
func New(cfg *config.Config) *Client {
	sdkCfg := mudbase.NewConfiguration()
	sdkCfg.Servers = mudbase.ServerConfigurations{
		{URL: cfg.MudbaseURL},
	}
	sdkCfg.HTTPClient = &http.Client{Timeout: 15 * time.Second}

	return &Client{
		SDK:        mudbase.NewAPIClient(sdkCfg),
		cfg:        cfg,
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}
}

// ProjectID returns the configured Mudbase project ID.
func (c *Client) ProjectID() string {
	return c.cfg.ProjectID
}

// authedContext attaches a bearer token to ctx the way the generated SDK expects it
// (context.WithValue(ctx, mudbase.ContextAccessToken, token)) - confirmed against
// mudbase-sdk/go/configuration.go and client.go's prepareRequest, which reads exactly this key.
func authedContext(ctx context.Context, token string) context.Context {
	if token == "" {
		return ctx
	}
	return context.WithValue(ctx, mudbase.ContextAccessToken, token)
}
