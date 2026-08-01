// Package server wires the app's HTTP surface: routing, session handling, and every
// server-rendered page handler, on top of internal/store's domain services and internal/askai's
// Ask AI pipeline.
package server

import (
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/askai"
	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/config"
	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/mbase"
	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/session"
	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/store"
)

// App bundles every dependency the HTTP handlers need.
type App struct {
	cfg       *config.Config
	sessions  *session.Store
	mudbase   *mbase.Client
	documents *store.DocumentService
	searchLog *store.SearchLogService
	functions *askai.FunctionInvoker
	llm       *askai.LLMClient
	templates *Templates
}

// New builds the App and its full dependency graph from cfg.
func New(cfg *config.Config) (*App, error) {
	templates, err := loadTemplates()
	if err != nil {
		return nil, fmt.Errorf("server: loading templates: %w", err)
	}

	client := mbase.New(cfg)
	documents := store.NewDocumentService(client, cfg.DocumentsCollectionID)
	searchLog := store.NewSearchLogService(client, cfg.SearchLogCollectionID)
	functions := askai.NewFunctionInvoker(client, cfg.FunctionID, cfg.FunctionsAPIKey)
	llm := askai.NewLLMClient(cfg.AnthropicAPIKey, cfg.LLMModel)

	return &App{
		cfg:       cfg,
		sessions:  session.New(cfg.SessionSecret, cfg.CookieSecure),
		mudbase:   client,
		documents: documents,
		searchLog: searchLog,
		functions: functions,
		llm:       llm,
		templates: templates,
	}, nil
}

// Routes builds the full chi router for this app. Static assets are mounted outside the session
// middleware group - a stylesheet request has no business establishing (or waiting on) a Mudbase
// anonymous session.
func (a *App) Routes() http.Handler {
	root := chi.NewRouter()
	root.Use(middleware.Logger)
	root.Use(middleware.Recoverer)

	staticHandler := http.FileServer(http.FS(staticFS))
	root.Get("/static/*", staticHandler.ServeHTTP)

	r := chi.NewRouter()
	r.Use(a.sessionMiddleware)

	r.Get("/", a.handleLibrary)

	r.With(a.requireSignedIn).Get("/documents/new", a.handleDocumentNewShow)
	r.With(a.requireSignedIn).Post("/documents", a.handleDocumentCreate)
	r.Get("/documents/{id}", a.handleDocumentDetail)
	r.With(a.requireSignedIn).Get("/documents/{id}/edit", a.handleDocumentEditShow)
	r.With(a.requireSignedIn).Post("/documents/{id}/edit", a.handleDocumentUpdate)
	r.With(a.requireSignedIn).Post("/documents/{id}/delete", a.handleDocumentDelete)

	r.Get("/ask", a.handleAskShow)
	r.Post("/ask", a.handleAskSubmit)

	r.Get("/login", a.handleLoginShow)
	r.Post("/login", a.handleLoginSubmit)
	r.Get("/register", a.handleRegisterShow)
	r.Post("/register", a.handleRegisterSubmit)
	r.Post("/logout", a.handleLogout)

	root.Mount("/", r)
	return root
}

// baseView builds the Base view fields shared by every page from the current request's session.
func (a *App) baseView(r *http.Request, title string) Base {
	data := sessionFrom(r)
	return Base{
		Title:       title,
		IsSignedIn:  data.IsSignedIn(),
		DisplayName: data.DisplayName(),
		UserID:      data.UserID(),
	}
}
