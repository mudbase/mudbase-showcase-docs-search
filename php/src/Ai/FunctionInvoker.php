<?php

declare(strict_types=1);

namespace App\Ai;

use GuzzleHttp\Client as GuzzleClient;
use Mudbase\Sdk\Api\FunctionsApi;
use Mudbase\Sdk\ApiException;
use Mudbase\Sdk\Configuration;
use Mudbase\Sdk\Model\ExecuteFunctionRequest;

/**
 * Invokes the deployed Mudbase Function (`docsAskRetrieval`, `_id 6a6d431ef09e238c3e62b2f4`) that
 * ranks candidate documents by keyword overlap and assembles a grounded context block. This is
 * server-only code: `MUDBASE_FUNCTIONS_API_KEY` is an org-scoped `ak_` API key with `functions`
 * permission, created specifically for this purpose (see plan/build-plan.md "Ask AI architecture"
 * for why — short version: the project end-user JWT this app otherwise uses can only ever satisfy
 * `rbacCheck("functions","read")`, never `"create"`, which is what the `/execute` route requires,
 * confirmed against `mudbase-backend` source). This key must never reach a browser — since this
 * app is server-rendered PHP, it never does; it only ever leaves this process as an outbound
 * request to `cloud.mudbase.dev`.
 *
 * Uses a dedicated `Configuration` instance (not the shared `Configuration::getDefaultConfiguration()`
 * singleton `MudbaseClient` mutates for the signed-in user's Bearer token) so the org-scoped
 * `X-API-Key` used here can never leak onto, or be clobbered by, the per-request user-session
 * client.
 */
final class FunctionInvoker
{
    private const POLL_INTERVAL_MICROSECONDS = 600_000; // 600ms, matching the reference app's POLL_INTERVAL_MS
    private const POLL_TIMEOUT_SECONDS = 20.0;

    private readonly FunctionsApi $functions;

    public function __construct(
        string $baseUrl,
        private readonly string $projectId,
        private readonly string $functionId,
        string $apiKey,
    ) {
        $config = new Configuration();
        $config->setHost(rtrim($baseUrl, '/'));
        $config->setApiKey('X-API-Key', $apiKey);
        $this->functions = new FunctionsApi(new GuzzleClient(), $config);
    }

    /**
     * @param list<array{documentId: string, title: string, content: string, tags?: string}> $candidates
     * @return array{contextBlock: string, citations: list<array{documentId: string, title: string, score: int}>, usedCount: int}
     */
    public function invokeRetrieval(string $question, array $candidates): array
    {
        $request = new ExecuteFunctionRequest([
            'payload' => ['question' => $question, 'candidates' => $candidates],
        ]);

        try {
            $executeResponse = $this->functions->executeFunction($this->projectId, $this->functionId, $request);
        } catch (ApiException $e) {
            throw new RetrievalError("Mudbase Function execute request failed: {$e->getMessage()}", previous: $e);
        }

        $executeData = $executeResponse->getData();
        $executionId = $executeData?->getExecutionId();
        if (!is_string($executionId) || $executionId === '') {
            throw new RetrievalError('Mudbase Function execute request did not return an executionId');
        }

        $deadline = microtime(true) + self::POLL_TIMEOUT_SECONDS;
        while (microtime(true) < $deadline) {
            try {
                $statusResponse = $this->functions->getFunctionExecution($this->projectId, $this->functionId, $executionId);
            } catch (ApiException $e) {
                throw new RetrievalError("Mudbase Function execution poll failed: {$e->getMessage()}", previous: $e);
            }

            $statusData = $statusResponse->getData();
            $status = $statusData?->getStatus();

            if ($status === 'success') {
                $result = $statusData?->getResult();
                if ($result === null) {
                    throw new RetrievalError('Function execution succeeded but returned no result');
                }
                return self::normalizeResult($result);
            }

            if ($status === 'failed' || $status === 'timeout') {
                $error = $statusData?->getError() ?? 'unknown error';
                throw new RetrievalError("Mudbase Function execution {$status}: {$error}");
            }

            usleep(self::POLL_INTERVAL_MICROSECONDS);
        }

        throw new RetrievalError('Timed out waiting for the Mudbase Function execution to complete');
    }

    /**
     * `FunctionExecutionStatusResponseData::getResult()` is typed `object` in the OpenAPI spec
     * (the generator has no way to know a Function's arbitrary return shape) — the SDK's
     * deserializer does a shallow `(array)` cast for that type, which can leave nested JSON
     * objects (each entry of `citations`) as `stdClass`. Round-tripping through
     * `json_encode`/`json_decode(..., true)` flattens the whole tree into plain arrays, the same
     * technique `MudbaseApiError::fromApiException()` already uses for its own decoded body.
     *
     * @return array{contextBlock: string, citations: list<array{documentId: string, title: string, score: int}>, usedCount: int}
     */
    private static function normalizeResult(mixed $result): array
    {
        $decoded = json_decode((string) json_encode($result), true);
        $decoded = is_array($decoded) ? $decoded : [];

        $citations = [];
        foreach ((is_array($decoded['citations'] ?? null) ? $decoded['citations'] : []) as $citation) {
            if (!is_array($citation)) {
                continue;
            }
            $citations[] = [
                'documentId' => (string) ($citation['documentId'] ?? ''),
                'title' => (string) ($citation['title'] ?? ''),
                'score' => (int) ($citation['score'] ?? 0),
            ];
        }

        return [
            'contextBlock' => (string) ($decoded['contextBlock'] ?? ''),
            'citations' => $citations,
            'usedCount' => (int) ($decoded['usedCount'] ?? count($citations)),
        ];
    }
}
