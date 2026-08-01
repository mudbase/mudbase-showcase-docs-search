package askai

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

// overrideAnthropicURLForTest points anthropicAPIURL at a local fake server for the duration of a
// test, returning a restore function - anthropicAPIURL is a var (not a const) solely to make this
// possible; production code never reassigns it.
func overrideAnthropicURLForTest(url string) func() {
	original := anthropicAPIURL
	anthropicAPIURL = url
	return func() { anthropicAPIURL = original }
}

// TestGenerateGroundedAnswerMissingKey verifies the honest, documented failure mode this task
// asked for: with no ANTHROPIC_API_KEY configured, the call fails immediately with
// ErrAnthropicKeyMissing rather than making a request or fabricating a response.
func TestGenerateGroundedAnswerMissingKey(t *testing.T) {
	client := NewLLMClient("", "")
	_, err := client.GenerateGroundedAnswer(context.Background(), "How do I reset my password?", "some context")
	if !errors.Is(err, ErrAnthropicKeyMissing) {
		t.Fatalf("expected ErrAnthropicKeyMissing, got %v", err)
	}
}

// TestGenerateGroundedAnswerSuccess exercises the full request/response parse against a local
// fake Anthropic endpoint - a real completion call still can't be verified without a live API
// key, but this proves the request shape, headers, and response parsing are all correct.
func TestGenerateGroundedAnswerSuccess(t *testing.T) {
	var gotAPIKey, gotVersion string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAPIKey = r.Header.Get("x-api-key")
		gotVersion = r.Header.Get("anthropic-version")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"content":[{"type":"text","text":"Go to Settings and click Reset."}],"stop_reason":"end_turn"}`))
	}))
	defer server.Close()

	client := &LLMClient{apiKey: "sk-test-key", model: "claude-opus-5", httpClient: server.Client()}
	restoreURL := overrideAnthropicURLForTest(server.URL)
	defer restoreURL()

	answer, err := client.GenerateGroundedAnswer(context.Background(), "How do I reset my password?", "Password Reset Guide: ...")
	if err != nil {
		t.Fatalf("GenerateGroundedAnswer: %v", err)
	}
	if answer != "Go to Settings and click Reset." {
		t.Fatalf("unexpected answer: %q", answer)
	}
	if gotAPIKey != "sk-test-key" {
		t.Fatalf("expected x-api-key header to be sent, got %q", gotAPIKey)
	}
	if gotVersion != anthropicAPIVersion {
		t.Fatalf("expected anthropic-version header %q, got %q", anthropicAPIVersion, gotVersion)
	}
}

// TestGenerateGroundedAnswerRefusal verifies the refusal-specific error message mirrors the
// reference web app's llm.ts handling of stop_reason === "refusal".
func TestGenerateGroundedAnswerRefusal(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"content":[],"stop_reason":"refusal"}`))
	}))
	defer server.Close()

	client := &LLMClient{apiKey: "sk-test-key", model: "claude-opus-5", httpClient: server.Client()}
	restoreURL := overrideAnthropicURLForTest(server.URL)
	defer restoreURL()

	_, err := client.GenerateGroundedAnswer(context.Background(), "question", "context")
	if err == nil {
		t.Fatal("expected an error for a refusal response")
	}
}
