package server

import (
	"log"
	"net/http"
	"strings"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/askai"
)

// askQuestionMaxLen mirrors the reference web app's AskRequestSchema
// (web/src/lib/ask-schema.ts: `question: z.string().min(1).max(2000)`).
const askQuestionMaxLen = 2000

// askTopCandidates mirrors the reference web app's AskAIPanel, which shortlists the top 5 scored
// documents before sending them to the retrieval Function (web/src/components/ask/AskAIPanel.tsx).
const askTopCandidates = 5

// noFunctionMatchAnswer mirrors web/src/app/api/ask/route.ts's canned answer when the retrieval
// Function ran successfully but found no usable candidates (usedCount === 0) - this is a normal,
// successful response, not an error: the route returns 200, and the client still logs the search.
const noFunctionMatchAnswer = "I couldn't find anything in the knowledge base closely related to that question. Try rephrasing, or add a document that covers it."

// AskData is the /ask page's content payload, covering every state the panel can be in: initial,
// no keyword match, a real (or canned) answer with citations, and an error from the Function or
// LLM call.
type AskData struct {
	Base
	Question       string
	Answer         string
	Citations      []AskCitationView
	NoMatch        bool
	ErrorMessage   string
	RecentSearches []RecentSearchView
}

func (a *App) recentSearchViews(r *http.Request) []RecentSearchView {
	data := sessionFrom(r)
	entries, err := a.searchLog.Recent(r.Context(), data.AccessToken())
	if err != nil {
		log.Printf("server: loading recent searches: %v", err)
		return nil
	}
	return newRecentSearchViews(entries)
}

func (a *App) handleAskShow(w http.ResponseWriter, r *http.Request) {
	view := AskData{
		Base:           a.baseView(r, "Ask AI"),
		RecentSearches: a.recentSearchViews(r),
	}
	view.FlashError, view.FlashSuccess = flashFromQuery(r)
	a.render(w, r, http.StatusOK, "ask.html", view)
}

// logAskSearch records the query in search_log, best-effort: mirrors the reference web app's own
// behavior of setting UI state (answer/citations) before awaiting the search_log write, so a
// logging failure never hides an answer the visitor already got. userId/userName are included
// only for a real signed-in visitor (see store.SearchLogService.Log's doc comment).
func (a *App) logAskSearch(r *http.Request, question string, resultCount int) {
	data := sessionFrom(r)
	userID, userName := "", ""
	if data.IsSignedIn() {
		userID, userName = data.UserID(), data.DisplayName()
	}
	if err := a.searchLog.Log(r.Context(), data.AccessToken(), question, userID, userName, resultCount); err != nil {
		log.Printf("server: logging ask search: %v", err)
	}
}

// handleAskSubmit runs the full Ask AI pipeline - the actual point of this showcase. See
// plan/build-plan.md "Ask AI architecture" for the two platform constraints that shape it:
//
//  1. Client-side keyword retrieval shortlists candidates from the same document pool the
//     library page reads (askai.ScoreDocuments/TopCandidates) - ported here since this app has no
//     client-side JS state to hold a loaded set across requests.
//  2. The real, deployed Mudbase Function (docsAskRetrieval) re-ranks those candidates and
//     assembles a grounded context block - the only work its network-free sandbox can do
//     (internal/askai/functioninvoke.go).
//  3. This handler - not the Function - makes the one LLM completion call, using the context
//     block the Function assembled (internal/askai/llm.go). This is the smallest possible
//     server-side surface, existing purely because of that sandbox constraint.
func (a *App) handleAskSubmit(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		a.serverError(w, r, err)
		return
	}
	question := strings.TrimSpace(r.FormValue("question"))

	renderWith := func(status int, view AskData) {
		view.Base = a.baseView(r, "Ask AI")
		view.Question = question
		view.RecentSearches = a.recentSearchViews(r)
		view.FlashError, view.FlashSuccess = flashFromQuery(r)
		a.render(w, r, status, "ask.html", view)
	}

	if question == "" {
		renderWith(http.StatusOK, AskData{ErrorMessage: "Enter a question to ask."})
		return
	}
	if len(question) > askQuestionMaxLen {
		renderWith(http.StatusOK, AskData{ErrorMessage: "Question is too long."})
		return
	}

	data := sessionFrom(r)
	documents, err := a.documents.CandidatePool(r.Context(), data.AccessToken())
	if err != nil {
		a.serverError(w, r, err)
		return
	}

	scored := askai.ScoreDocuments(documents, question)
	if len(scored) == 0 {
		a.logAskSearch(r, question, 0)
		renderWith(http.StatusOK, AskData{NoMatch: true})
		return
	}

	candidates := askai.TopCandidates(scored, askTopCandidates)
	retrieval, err := a.functions.Invoke(r.Context(), question, candidates)
	if err != nil {
		// Mirrors web/src/app/api/ask/route.ts's catch block: the Function call failing (or
		// timing out) never gets a search_log entry, exactly like the client's own
		// askAI.mutateAsync throwing before logSearch.mutateAsync is reached.
		renderWith(http.StatusBadGateway, AskData{ErrorMessage: err.Error()})
		return
	}

	if retrieval.UsedCount == 0 {
		// This is a normal, successful response (route.ts returns 200 here), not an error - the
		// Function ran but found nothing usable. The client still logs the search.
		a.logAskSearch(r, question, 0)
		renderWith(http.StatusOK, AskData{Answer: noFunctionMatchAnswer})
		return
	}

	answer, err := a.llm.GenerateGroundedAnswer(r.Context(), question, retrieval.ContextBlock)
	if err != nil {
		renderWith(http.StatusBadGateway, AskData{ErrorMessage: err.Error()})
		return
	}

	citations := make([]AskCitationView, 0, len(retrieval.Citations))
	for _, c := range retrieval.Citations {
		citations = append(citations, AskCitationView{DocumentID: c.DocumentID, Title: c.Title})
	}

	a.logAskSearch(r, question, len(retrieval.Citations))
	renderWith(http.StatusOK, AskData{Answer: answer, Citations: citations})
}
