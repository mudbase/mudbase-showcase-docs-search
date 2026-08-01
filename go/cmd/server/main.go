// Command server runs the Mudbase Showcase Docs Search knowledge-base app: a server-rendered Go
// reimplementation of the Mudbase showcase docs-search reference app, talking to the real Mudbase
// Go SDK for auth/collections/Functions, plus one small server-side call to Anthropic's Claude API
// for the Ask AI feature's grounded completion - see plan/build-plan.md "Ask AI architecture" for
// exactly why that one call can't be avoided.
package main

import (
	"log"
	"net/http"
	"time"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/config"
	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/server"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	app, err := server.New(cfg)
	if err != nil {
		log.Fatalf("server: %v", err)
	}

	httpServer := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           app.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		// WriteTimeout is generous because POST /ask can legitimately run long: up to a 20s
		// Mudbase Function execution poll (internal/askai/functioninvoke.go) followed by a real
		// Anthropic completion call (internal/askai/llm.go, 60s client timeout) - the worst case
		// is well under 90s, but nowhere near the other routes' near-instant response times.
		WriteTimeout: 90 * time.Second,
		IdleTimeout:  90 * time.Second,
	}

	log.Printf("Mudbase Showcase Docs Search listening on http://localhost:%s", cfg.Port)
	if err := httpServer.ListenAndServe(); err != nil {
		log.Fatalf("server: %v", err)
	}
}
