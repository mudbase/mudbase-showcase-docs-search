<?php

declare(strict_types=1);

namespace App\Ai;

use GuzzleHttp\Client as GuzzleClient;
use GuzzleHttp\Exception\GuzzleException;

/**
 * The one place in this codebase that calls a third-party LLM API. `$apiKey` comes from the
 * server-only `ANTHROPIC_API_KEY` env var — never sent to, or readable by, a browser (this app
 * has no client-side JS at all, but the same discipline as the reference Next.js app applies:
 * this value never leaves the process except as the `x-api-key` header on the request below).
 *
 * See plan/build-plan.md "Ask AI architecture" for why this call happens here rather than inside
 * the Mudbase Function itself: the Function's `isolated-vm` sandbox has no network primitives at
 * all (no `fetch`, no `curl`/socket equivalent — verified against the actual runner source, see
 * the plan doc), so it cannot make an outbound HTTPS call to any LLM provider. The Function still
 * does real work (keyword-overlap retrieval ranking + grounded context assembly, see
 * `FunctionInvoker`) — this class only performs the completion call the sandbox is structurally
 * incapable of making itself. Since this whole app is already server-side PHP, this class is
 * simply invoked directly from `AskController` rather than through a separate route — there is no
 * smaller server-side surface to carve out than "the one PHP class that holds this API key."
 */
final class AnthropicClient
{
    private const DEFAULT_MODEL = 'claude-opus-5';
    private const API_VERSION = '2023-06-01';
    private const ENDPOINT = 'https://api.anthropic.com/v1/messages';
    private const MAX_TOKENS = 1024;

    private const SYSTEM_PROMPT = <<<'PROMPT'
        You are a support assistant for a documentation knowledge base. Answer the user's
        question using ONLY the document excerpts provided below - never your own outside knowledge. If the
        excerpts do not contain enough information to answer, say so plainly rather than guessing. Keep the
        answer concise (a few sentences to a short paragraph). When you use a fact from an excerpt, mention
        which document it came from by its title.
        PROMPT;

    public function __construct(
        private readonly ?string $apiKey,
        private readonly string $model,
    ) {
    }

    public function generateGroundedAnswer(string $question, string $contextBlock): string
    {
        if ($this->apiKey === null || $this->apiKey === '') {
            throw new LlmError(
                'ANTHROPIC_API_KEY is not configured. This is a server-only env var (see README.md '
                . '"LLM setup" and .env.example) - the developer running this app must supply their own key.',
            );
        }

        $trimmedContext = trim($contextBlock);
        $userContent = $trimmedContext !== ''
            ? "Question: {$question}\n\nDocument excerpts:\n{$contextBlock}"
            : "Question: {$question}\n\n(No document excerpts were retrieved - say you don't have enough information in the knowledge base to answer.)";

        $client = new GuzzleClient();
        try {
            $response = $client->post(self::ENDPOINT, [
                'headers' => [
                    'x-api-key' => $this->apiKey,
                    'anthropic-version' => self::API_VERSION,
                    'content-type' => 'application/json',
                ],
                'json' => [
                    'model' => $this->model !== '' ? $this->model : self::DEFAULT_MODEL,
                    'max_tokens' => self::MAX_TOKENS,
                    'system' => self::SYSTEM_PROMPT,
                    'messages' => [['role' => 'user', 'content' => $userContent]],
                ],
                'http_errors' => false,
                'timeout' => 60,
            ]);
        } catch (GuzzleException $e) {
            throw new LlmError("Anthropic API request failed: {$e->getMessage()}", previous: $e);
        }

        $status = $response->getStatusCode();
        $decoded = json_decode((string) $response->getBody(), true);

        if ($status >= 400) {
            $message = is_array($decoded) ? ($decoded['error']['message'] ?? null) : null;
            throw new LlmError(is_string($message) ? $message : "Anthropic API request failed ({$status})");
        }

        $blocks = is_array($decoded) && is_array($decoded['content'] ?? null) ? $decoded['content'] : [];
        foreach ($blocks as $block) {
            if (is_array($block) && ($block['type'] ?? null) === 'text' && is_string($block['text'] ?? null)) {
                return $block['text'];
            }
        }

        $stopReason = is_array($decoded) ? ($decoded['stop_reason'] ?? null) : null;
        if ($stopReason === 'refusal') {
            throw new LlmError('The model declined to answer this question.');
        }
        throw new LlmError('The model returned no text content');
    }
}
