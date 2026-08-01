package askai

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	mudbase "github.com/mudbase/mudbase-sdk/go"

	"github.com/mudbase/mudbase-showcase-docs-search/go/internal/mbase"
)

// FunctionInvoker invokes the deployed Mudbase Function (`docsAskRetrieval`, real deployed
// _id from MUDBASE_FUNCTION_ID) that ranks candidate documents by keyword overlap and assembles a
// grounded context block.
//
// Why this exists at all - the two independently-verified platform constraints that rule out the
// naive "client does retrieval, Function calls the LLM itself" design (full detail in
// plan/build-plan.md "Ask AI architecture"):
//
//  1. A project end-user JWT can never invoke a Function: the `/execute` route requires
//     rbacCheck("functions","create"), and every project end-user - including a real, signed-in
//     "customer" account - always carries org role "viewer", which only satisfies
//     "functions:read". Only an org-scoped API key (ak_ prefix) with `functions` permission can
//     call it - that's FunctionsAPIKey below, wired through the SDK's ApiKeyAuth context
//     mechanism (mudbase.ContextAPIKeys), never sent to the browser.
//  2. The Function's own sandbox (isolated-vm) has zero network access - no fetch, no http/https
//     module - so it cannot make the outbound HTTPS call to the LLM provider itself, no matter
//     what env var it holds. That's why the Function only does retrieval-ranking (real,
//     structurally the only thing it *can* do), and the LLM completion call happens in llm.go
//     instead, invoked from internal/server/handlers_ask.go - the smallest server-side surface
//     this app has, and the only place with a real network stack.
type FunctionInvoker struct {
	sdk        *mudbase.APIClient
	projectID  string
	functionID string
	apiKey     string
}

// NewFunctionInvoker builds a FunctionInvoker sharing the app's existing Mudbase SDK client
// instance (no second HTTP client needed - ApiKeyAuth is attached per-request via context, not
// stored on the client).
func NewFunctionInvoker(mudbaseClient *mbase.Client, functionID, apiKey string) *FunctionInvoker {
	return &FunctionInvoker{
		sdk:        mudbaseClient.SDK,
		projectID:  mudbaseClient.ProjectID(),
		functionID: functionID,
		apiKey:     apiKey,
	}
}

// apiKeyContext attaches apiKey to ctx the way the generated SDK expects it for ApiKeyAuth-scoped
// endpoints (context.WithValue(ctx, mudbase.ContextAPIKeys, map[string]mudbase.APIKey{...})) -
// confirmed against mudbase-sdk/go/api_functions.go's ExecuteFunctionExecute, which reads exactly
// this shape and sets it as the X-API-Key header.
func (f *FunctionInvoker) apiKeyContext(ctx context.Context) context.Context {
	return context.WithValue(ctx, mudbase.ContextAPIKeys, map[string]mudbase.APIKey{
		"ApiKeyAuth": {Key: f.apiKey},
	})
}

// Citation is one document the Function's retrieval ranking used to build the context block.
type Citation struct {
	DocumentID string `json:"documentId"`
	Title      string `json:"title"`
	Score      int    `json:"score"`
}

// RetrievalResult is the Function's real, decoded return value.
type RetrievalResult struct {
	ContextBlock string     `json:"contextBlock"`
	Citations    []Citation `json:"citations"`
	UsedCount    int        `json:"usedCount"`
}

const (
	pollInterval = 600 * time.Millisecond
	pollTimeout  = 20 * time.Second
)

// Invoke executes the Function with {question, candidates}, then polls its execution status until
// it leaves queued/running - mirrors web/src/lib/server/functionInvoke.ts's invokeRetrievalFunction
// exactly (same poll interval and timeout).
func (f *FunctionInvoker) Invoke(ctx context.Context, question string, candidates []Candidate) (RetrievalResult, error) {
	execReq := mudbase.NewExecuteFunctionRequest()
	execReq.SetPayload(map[string]interface{}{
		"question":   question,
		"candidates": candidates,
	})

	execResp, _, err := f.sdk.FunctionsAPI.
		ExecuteFunction(f.apiKeyContext(ctx), f.projectID, f.functionID).
		ExecuteFunctionRequest(*execReq).
		Execute()
	if err != nil {
		return RetrievalResult{}, fmt.Errorf("askai: executing retrieval function: %s: %w", mbase.FriendlyMessage(err), err)
	}

	execData := execResp.GetData()
	executionID := execData.GetExecutionId()
	if executionID == "" {
		return RetrievalResult{}, fmt.Errorf("askai: function execute response had no executionId")
	}

	deadline := time.Now().Add(pollTimeout)
	for time.Now().Before(deadline) {
		statusResp, _, pollErr := f.sdk.FunctionsAPI.
			GetFunctionExecution(f.apiKeyContext(ctx), f.projectID, f.functionID, executionID).
			Execute()
		if pollErr != nil {
			return RetrievalResult{}, fmt.Errorf("askai: polling function execution: %s: %w", mbase.FriendlyMessage(pollErr), pollErr)
		}

		data := statusResp.GetData()
		switch data.GetStatus() {
		case "success":
			return decodeRetrievalResult(data.GetResult())
		case "failed", "timeout":
			return RetrievalResult{}, fmt.Errorf("askai: function execution %s: %s", data.GetStatus(), data.GetError())
		}

		select {
		case <-ctx.Done():
			return RetrievalResult{}, fmt.Errorf("askai: waiting for function execution: %w", ctx.Err())
		case <-time.After(pollInterval):
		}
	}

	return RetrievalResult{}, fmt.Errorf("askai: timed out waiting for the function execution to complete")
}

// decodeRetrievalResult re-marshals the Function's map[string]interface{} result into a typed
// RetrievalResult - the same round-trip internal/mbase/data.go's decodeInto uses for collection
// documents, applied here to a Function's arbitrary JSON return value instead.
func decodeRetrievalResult(raw map[string]interface{}) (RetrievalResult, error) {
	var result RetrievalResult
	b, err := json.Marshal(raw)
	if err != nil {
		return RetrievalResult{}, fmt.Errorf("askai: encoding function result for decode: %w", err)
	}
	if err := json.Unmarshal(b, &result); err != nil {
		return RetrievalResult{}, fmt.Errorf("askai: decoding function result: %w", err)
	}
	return result, nil
}
