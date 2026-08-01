// Package config loads and validates every environment variable this app needs at startup.
// Failing fast here means a misconfigured deployment never serves a single request instead of
// panicking deep inside a request handler the first time a particular env var is touched.
package config

import (
	"fmt"
	"os"
	"strconv"
)

// Config holds every environment-derived setting the app needs, resolved once at startup.
type Config struct {
	// MudbaseURL is the Mudbase API base URL (e.g. https://cloud.mudbase.dev).
	MudbaseURL string
	// ProjectID is this app's Mudbase project ID.
	ProjectID string
	// DocumentsCollectionID is the Mudbase collection ID backing the `documents` collection.
	DocumentsCollectionID string
	// SearchLogCollectionID is the Mudbase collection ID backing the `search_log` collection.
	SearchLogCollectionID string
	// FunctionID is the deployed `docsAskRetrieval` Mudbase Function's _id - see
	// internal/askai/functioninvoke.go and plan/build-plan.md "Ask AI architecture" for why this
	// Function exists at all (it does the retrieval-ranking work its own sandbox is capable of).
	FunctionID string
	// FunctionsAPIKey is an org-scoped Mudbase API key (ak_ prefix) permissioned only for
	// "functions", used solely to invoke FunctionID. Server-only - never logged, never rendered.
	// A project end-user JWT (org role always "viewer") can never satisfy the /execute route's
	// rbacCheck("functions","create"), so this key is the only way this app can invoke it.
	FunctionsAPIKey string
	// AnthropicAPIKey is the server-only Anthropic Claude API key used for the one LLM completion
	// call this app makes (internal/askai/llm.go). May be empty - see that package's doc comment
	// for the honest, documented behavior when it is.
	AnthropicAPIKey string
	// LLMModel is the Claude model used for the grounded completion call. Defaults to
	// claude-opus-5 if unset.
	LLMModel string
	// SessionSecret signs and encrypts the httpOnly session cookie holding the Mudbase JWT.
	SessionSecret string
	// CookieSecure sets the session cookie's Secure flag. Enable in production (HTTPS); leave off
	// for plain-HTTP local development, where a Secure cookie would silently never be sent.
	CookieSecure bool
	// Port is the local HTTP listen port.
	Port string
}

const defaultLLMModel = "claude-opus-5"

// Load reads and validates every required environment variable, returning a descriptive error
// for the first one that's missing rather than letting the zero value propagate silently.
func Load() (*Config, error) {
	cfg := &Config{
		MudbaseURL:            envOrDefault("MUDBASE_URL", "https://cloud.mudbase.dev"),
		ProjectID:             os.Getenv("MUDBASE_PROJECT_ID"),
		DocumentsCollectionID: os.Getenv("MUDBASE_DOCUMENTS_COLLECTION_ID"),
		SearchLogCollectionID: os.Getenv("MUDBASE_SEARCH_LOG_COLLECTION_ID"),
		FunctionID:            os.Getenv("MUDBASE_FUNCTION_ID"),
		FunctionsAPIKey:       os.Getenv("MUDBASE_FUNCTIONS_API_KEY"),
		AnthropicAPIKey:       os.Getenv("ANTHROPIC_API_KEY"),
		LLMModel:              envOrDefault("LLM_MODEL", defaultLLMModel),
		SessionSecret:         os.Getenv("SESSION_SECRET"),
		CookieSecure:          envOrDefault("COOKIE_SECURE", "false") == "true",
		Port:                  envOrDefault("PORT", "8080"),
	}

	// ANTHROPIC_API_KEY and the Function wiring are intentionally NOT in this required set: the
	// app must still start and serve document CRUD + search when they're absent - only the /ask
	// route itself fails, with a clear, honest error (see internal/askai/llm.go,
	// internal/server/handlers_ask.go), exactly like the reference web app's own documented
	// behavior when no Anthropic key is available.
	required := map[string]string{
		"MUDBASE_PROJECT_ID":               cfg.ProjectID,
		"MUDBASE_DOCUMENTS_COLLECTION_ID":  cfg.DocumentsCollectionID,
		"MUDBASE_SEARCH_LOG_COLLECTION_ID": cfg.SearchLogCollectionID,
		"SESSION_SECRET":                   cfg.SessionSecret,
	}
	for name, value := range required {
		if value == "" {
			return nil, fmt.Errorf("config: missing required environment variable %s", name)
		}
	}

	if len(cfg.SessionSecret) < 32 {
		return nil, fmt.Errorf("config: SESSION_SECRET must be at least 32 characters, got %d", len(cfg.SessionSecret))
	}

	if _, err := strconv.Atoi(cfg.Port); err != nil {
		return nil, fmt.Errorf("config: PORT must be numeric: %w", err)
	}

	return cfg, nil
}

func envOrDefault(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
