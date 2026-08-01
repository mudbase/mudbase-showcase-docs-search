package askai

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ErrAnthropicKeyMissing is returned by GenerateGroundedAnswer when no API key was configured.
// internal/server/handlers_ask.go surfaces its message directly to the visitor rather than a
// generic 500 - the honest, documented behavior this task asked for rather than a fabricated
// success (see plan/build-plan.md "Known limitation").
var ErrAnthropicKeyMissing = errors.New(
	"ANTHROPIC_API_KEY is not configured. This is a server-only env var (see README.md " +
		`"LLM setup" and .env.example) - the developer running this app must supply their own key.`,
)

const (
	anthropicAPIVersion = "2023-06-01"
	defaultLLMModel     = "claude-opus-5"
	maxAnswerTokens     = 1024
)

// anthropicAPIURL is a var, not a const, solely so llm_test.go can point it at a local fake server
// - production code never reassigns it.
var anthropicAPIURL = "https://api.anthropic.com/v1/messages"

// systemPrompt instructs the model to answer only from the Function's retrieved excerpts -
// mirrors web/src/lib/server/llm.ts's SYSTEM_PROMPT exactly.
const systemPrompt = `You are a support assistant for a documentation knowledge base. Answer the user's
question using ONLY the document excerpts provided below - never your own outside knowledge. If the
excerpts do not contain enough information to answer, say so plainly rather than guessing. Keep the
answer concise (a few sentences to a short paragraph). When you use a fact from an excerpt, mention
which document it came from by its title.`

// LLMClient makes the one third-party LLM API call in this codebase: a single grounded completion
// request to Anthropic's Claude API. It is the smallest possible server-side surface, existing
// solely because of the two platform constraints functioninvoke.go documents - the Function that
// does the real retrieval-ranking work cannot make this call itself (its sandbox has no network
// access at all), so it happens here instead, in internal/server/handlers_ask.go's request path.
type LLMClient struct {
	apiKey     string
	model      string
	httpClient *http.Client
}

// NewLLMClient builds an LLMClient. apiKey may be legitimately empty - GenerateGroundedAnswer
// returns ErrAnthropicKeyMissing in that case rather than panicking or faking a response. model
// defaults to claude-opus-5 when empty.
func NewLLMClient(apiKey, model string) *LLMClient {
	if model == "" {
		model = defaultLLMModel
	}
	return &LLMClient{
		apiKey:     apiKey,
		model:      model,
		httpClient: &http.Client{Timeout: 60 * time.Second},
	}
}

type anthropicMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type anthropicRequest struct {
	Model     string             `json:"model"`
	MaxTokens int                `json:"max_tokens"`
	System    string             `json:"system"`
	Messages  []anthropicMessage `json:"messages"`
}

type anthropicContentBlock struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type anthropicResponse struct {
	Content    []anthropicContentBlock `json:"content"`
	StopReason string                  `json:"stop_reason"`
}

type anthropicErrorResponse struct {
	Error struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

// GenerateGroundedAnswer sends one completion request to Claude, grounded in contextBlock (the
// Function's assembled excerpts) - mirrors web/src/lib/server/llm.ts's generateGroundedAnswer
// exactly: same system prompt, same user-content shape, same "no excerpts retrieved" fallback
// phrasing, same refusal/no-text-block error handling.
func (c *LLMClient) GenerateGroundedAnswer(ctx context.Context, question, contextBlock string) (string, error) {
	if c.apiKey == "" {
		return "", ErrAnthropicKeyMissing
	}

	var userContent string
	if strings.TrimSpace(contextBlock) != "" {
		userContent = fmt.Sprintf("Question: %s\n\nDocument excerpts:\n%s", question, contextBlock)
	} else {
		userContent = fmt.Sprintf(
			"Question: %s\n\n(No document excerpts were retrieved - say you don't have enough information in the knowledge base to answer.)",
			question,
		)
	}

	reqBody := anthropicRequest{
		Model:     c.model,
		MaxTokens: maxAnswerTokens,
		System:    systemPrompt,
		Messages:  []anthropicMessage{{Role: "user", Content: userContent}},
	}
	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("askai: encoding anthropic request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, anthropicAPIURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", fmt.Errorf("askai: building anthropic request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("x-api-key", c.apiKey)
	httpReq.Header.Set("anthropic-version", anthropicAPIVersion)

	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("askai: calling anthropic api: %w", err)
	}
	defer httpResp.Body.Close()

	respBody, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return "", fmt.Errorf("askai: reading anthropic response: %w", err)
	}

	if httpResp.StatusCode >= 300 {
		var wire anthropicErrorResponse
		_ = json.Unmarshal(respBody, &wire)
		message := wire.Error.Message
		if message == "" {
			message = fmt.Sprintf("anthropic api request failed (%s)", httpResp.Status)
		}
		return "", fmt.Errorf("askai: %s", message)
	}

	var parsed anthropicResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return "", fmt.Errorf("askai: decoding anthropic response: %w", err)
	}

	for _, block := range parsed.Content {
		if block.Type == "text" && block.Text != "" {
			return block.Text, nil
		}
	}

	if parsed.StopReason == "refusal" {
		return "", fmt.Errorf("askai: the model declined to answer this question")
	}
	return "", fmt.Errorf("askai: the model returned no text content")
}
