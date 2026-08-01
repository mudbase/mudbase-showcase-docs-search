package server

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/store"
)

// Field length caps mirror the reference web app's DocumentForm zod schema
// (web/src/components/documents/DocumentForm.tsx: documentFormSchema).
const (
	titleMaxLen   = 200
	contentMaxLen = 50000
	tagsMaxLen    = 500
)

// LibraryData is the / page's content payload.
type LibraryData struct {
	Base
	Documents []DocumentView
	Empty     bool
	Query     string
}

// handleLibrary renders the document library: a search box filtering the loaded set server-side
// (see store.DocumentService.Library) and a grid of document cards.
func (a *App) handleLibrary(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	data := sessionFrom(r)

	docs, err := a.documents.Library(r.Context(), data.AccessToken(), query)
	if err != nil {
		a.serverError(w, r, err)
		return
	}

	view := LibraryData{
		Base:      a.baseView(r, ""),
		Documents: newDocumentViews(docs, data.UserID()),
		Empty:     len(docs) == 0,
		Query:     query,
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "home.html", view)
}

// DocumentDetailData is the /documents/{id} page's content payload.
type DocumentDetailData struct {
	Base
	Document DocumentView
}

func (a *App) handleDocumentDetail(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)

	doc, err := a.documents.ByID(r.Context(), data.AccessToken(), id)
	if err != nil {
		redirectWithError(w, r, "/", "That document isn't available.")
		return
	}

	view := DocumentDetailData{
		Base:     a.baseView(r, doc.Title),
		Document: newDocumentView(doc, data.UserID()),
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "document_detail.html", view)
}

// DocumentFormData is the /documents/new and /documents/{id}/edit pages' shared content payload -
// one template (document_form.html) renders both, switched on Mode.
type DocumentFormData struct {
	Base
	Mode       string // "new" or "edit"
	DocumentID string
	Title      string
	Content    string
	Tags       string
}

func (a *App) handleDocumentNewShow(w http.ResponseWriter, r *http.Request) {
	view := DocumentFormData{
		Base: a.baseView(r, "New document"),
		Mode: "new",
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "document_form.html", view)
}

// validateDocumentForm mirrors web/src/components/documents/DocumentForm.tsx's documentFormSchema
// exactly (required title/content, the three length caps).
func validateDocumentForm(title, content, tags string) string {
	if title == "" {
		return "Title is required."
	}
	if len(title) > titleMaxLen {
		return "Title is too long."
	}
	if content == "" {
		return "Content is required."
	}
	if len(content) > contentMaxLen {
		return "Content is too long."
	}
	if len(tags) > tagsMaxLen {
		return "Tags are too long."
	}
	return ""
}

// handleDocumentCreate publishes a new document owned by the signed-in visitor. Route already
// gated by requireSignedIn.
func (a *App) handleDocumentCreate(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	title := strings.TrimSpace(r.FormValue("title"))
	content := strings.TrimSpace(r.FormValue("content"))
	tags := strings.TrimSpace(r.FormValue("tags"))

	if message := validateDocumentForm(title, content, tags); message != "" {
		redirectWithError(w, r, "/documents/new", message)
		return
	}

	data := sessionFrom(r)
	doc, err := a.documents.Create(r.Context(), data.AccessToken(), data.UserID(), data.DisplayName(), store.CreateInput{
		Title:   title,
		Content: content,
		Tags:    tags,
	})
	if err != nil {
		redirectWithError(w, r, "/documents/new", "Couldn't publish that document. Please try again.")
		return
	}

	http.Redirect(w, r, "/documents/"+doc.ID, http.StatusSeeOther)
}

// handleDocumentEditShow shows the edit form, gated to the document's author. Ownership is
// enforced here at the app UX layer only, not by a Mudbase dataScope restriction - this project's
// single `customer` role grants full CRUD on `documents` with no per-row scoping (see
// plan/build-plan.md), so this check (and handleDocumentUpdate/handleDocumentDelete's matching
// checks) is this app's own responsibility, exactly like the reference web app's own
// isOwner-gated UI (web/src/app/documents/[id]/edit/page.tsx).
func (a *App) handleDocumentEditShow(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)

	doc, err := a.documents.ByID(r.Context(), data.AccessToken(), id)
	if err != nil {
		redirectWithError(w, r, "/", "That document isn't available.")
		return
	}
	if doc.AuthorID != data.UserID() {
		redirectWithError(w, r, "/documents/"+id, "You can only edit documents you authored.")
		return
	}

	view := DocumentFormData{
		Base:       a.baseView(r, "Edit document"),
		Mode:       "edit",
		DocumentID: doc.ID,
		Title:      doc.Title,
		Content:    doc.Content,
		Tags:       doc.Tags,
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "document_form.html", view)
}

// handleDocumentUpdate saves an edited document. Route already gated by requireSignedIn; ownership
// re-checked here (see handleDocumentEditShow's doc comment).
func (a *App) handleDocumentUpdate(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)

	doc, err := a.documents.ByID(r.Context(), data.AccessToken(), id)
	if err != nil {
		redirectWithError(w, r, "/", "That document isn't available.")
		return
	}
	if doc.AuthorID != data.UserID() {
		redirectWithError(w, r, "/documents/"+id, "You can only edit documents you authored.")
		return
	}

	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	title := strings.TrimSpace(r.FormValue("title"))
	content := strings.TrimSpace(r.FormValue("content"))
	tags := strings.TrimSpace(r.FormValue("tags"))

	if message := validateDocumentForm(title, content, tags); message != "" {
		redirectWithError(w, r, "/documents/"+id+"/edit", message)
		return
	}

	if _, err := a.documents.Update(r.Context(), data.AccessToken(), id, store.UpdateInput{
		Title:   title,
		Content: content,
		Tags:    tags,
	}); err != nil {
		redirectWithError(w, r, "/documents/"+id+"/edit", "Couldn't save those changes. Please try again.")
		return
	}

	http.Redirect(w, r, "/documents/"+id, http.StatusSeeOther)
}

// handleDocumentDelete deletes a document. Route already gated by requireSignedIn; ownership
// re-checked here (see handleDocumentEditShow's doc comment).
func (a *App) handleDocumentDelete(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	data := sessionFrom(r)

	doc, err := a.documents.ByID(r.Context(), data.AccessToken(), id)
	if err != nil {
		redirectWithError(w, r, "/", "That document isn't available.")
		return
	}
	if doc.AuthorID != data.UserID() {
		redirectWithError(w, r, "/documents/"+id, "You can only delete documents you authored.")
		return
	}

	if err := a.documents.Delete(r.Context(), data.AccessToken(), id); err != nil {
		redirectWithError(w, r, "/documents/"+id, "Couldn't delete that document. Please try again.")
		return
	}

	redirectWithSuccess(w, r, "/", "Document deleted.")
}
