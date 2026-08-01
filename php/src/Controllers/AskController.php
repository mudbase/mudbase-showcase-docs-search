<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Ai\AnthropicClient;
use App\Ai\FunctionInvoker;
use App\Ai\LlmError;
use App\Ai\RetrievalError;
use App\Ai\RetrievalScorer;
use App\Http\AppContext;
use App\Http\Csrf;
use App\Http\Flash;
use App\Http\Response;
use App\Mudbase\MudbaseApiError;
use App\View;

/**
 * `/ask` — mirrors the reference app's Ask AI panel (src/components/ask/AskAIPanel.tsx) and its
 * `POST /api/ask` route handler (src/app/api/ask/route.ts), collapsed into one PHP controller
 * because this whole app is already server-rendered — there is no separate client to keep an API
 * key away from. See plan/build-plan.md "Ask AI architecture" for the full platform-constraint
 * rationale behind why retrieval ranking happens in a real Mudbase Function while the LLM
 * completion call happens here instead of inside that Function.
 *
 * Full request flow, mirroring the reference app exactly:
 *   1. Load up to 100 documents, score them by keyword overlap (`RetrievalScorer`, a PHP port of
 *      the reference app's client-side `scoreDocuments`).
 *   2. If nothing scores above zero, log a zero-result search and render the "no match" state —
 *      never call the Function or the LLM for a query with no plausible candidates.
 *   3. Otherwise take the top 5 candidates (content truncated to 4000 chars each) and invoke the
 *      real, deployed `docsAskRetrieval` Mudbase Function (`FunctionInvoker`) using the
 *      org-scoped API key — this is genuine retrieval-ranking work running on the platform, not a
 *      stand-in.
 *   4. If the Function found nothing worth citing (`usedCount === 0`), log a zero-result search
 *      and render the same "couldn't find anything" message the reference app shows.
 *   5. Otherwise call Anthropic's Claude API directly (`AnthropicClient`) with the Function's
 *      grounded context block — the one call the Function's sandbox is structurally incapable of
 *      making itself.
 *   6. Log the search (`queryText`, `resultCount`, and `userId`/`userName` only when a real
 *      account is signed in — never a placeholder) and render the answer with citations.
 */
final class AskController
{
    private const MAX_QUESTION_LENGTH = 2000;
    private const CANDIDATE_LIMIT = 5;
    private const LIBRARY_SCAN_LIMIT = 100;
    private const RECENT_SEARCHES_LIMIT = 10;

    /** @param array<string, string> $params */
    public function form(array $params): void
    {
        $ctx = AppContext::current();
        $recentSearches = [];
        try {
            $result = $ctx->mudbase->listDocuments(
                $ctx->searchLogCollectionId,
                null,
                '-createdAt',
                1,
                self::RECENT_SEARCHES_LIMIT,
            );
            $recentSearches = $result['data'];
        } catch (MudbaseApiError) {
            // Recent searches are a nice-to-have sidebar, not core functionality — degrade to an
            // empty list rather than blocking the Ask AI form from rendering at all.
        }

        View::render('ask', [
            'question' => '', 'answer' => null, 'citations' => [],
            'noMatch' => false, 'askError' => null,
            'recentSearches' => $recentSearches,
        ]);
    }

    /** @param array<string, string> $params */
    public function ask(array $params): void
    {
        $ctx = AppContext::current();
        $this->requireCsrf();

        $question = trim((string) ($_POST['question'] ?? ''));
        $recentSearches = $this->loadRecentSearches($ctx);

        if ($question === '' || mb_strlen($question) > self::MAX_QUESTION_LENGTH) {
            View::render('ask', [
                'question' => $question, 'answer' => null, 'citations' => [],
                'noMatch' => false,
                'askError' => $question === '' ? 'Enter a question.' : 'Keep the question under ' . self::MAX_QUESTION_LENGTH . ' characters.',
                'recentSearches' => $recentSearches,
            ]);
            return;
        }

        $documents = [];
        try {
            $result = $ctx->mudbase->listDocuments($ctx->documentsCollectionId, null, '-createdAt', 1, self::LIBRARY_SCAN_LIMIT);
            $documents = $result['data'];
        } catch (MudbaseApiError $e) {
            View::render('ask', [
                'question' => $question, 'answer' => null, 'citations' => [],
                'noMatch' => false, 'askError' => "Couldn't load the document library: {$e->getMessage()}",
                'recentSearches' => $recentSearches,
            ]);
            return;
        }

        $scored = RetrievalScorer::scoreDocuments($documents, $question);
        if ($scored === []) {
            $this->logSearch($ctx, $question, 0);
            View::render('ask', [
                'question' => $question, 'answer' => null, 'citations' => [],
                'noMatch' => true, 'askError' => null,
                'recentSearches' => $this->loadRecentSearches($ctx),
            ]);
            return;
        }

        if ($ctx->functionId === null || $ctx->functionsApiKey === null) {
            View::render('ask', [
                'question' => $question, 'answer' => null, 'citations' => [],
                'noMatch' => false,
                'askError' => 'Ask AI is not configured on this server — MUDBASE_FUNCTION_ID / MUDBASE_FUNCTIONS_API_KEY are missing. See .env.example.',
                'recentSearches' => $recentSearches,
            ]);
            return;
        }

        $candidates = RetrievalScorer::topCandidates($scored, self::CANDIDATE_LIMIT);

        try {
            $invoker = new FunctionInvoker($ctx->mudbaseUrl, $ctx->projectId, $ctx->functionId, $ctx->functionsApiKey);
            $retrieval = $invoker->invokeRetrieval($question, $candidates);
        } catch (RetrievalError $e) {
            View::render('ask', [
                'question' => $question, 'answer' => null, 'citations' => [],
                'noMatch' => false, 'askError' => $e->getMessage(),
                'recentSearches' => $recentSearches,
            ]);
            return;
        }

        if ($retrieval['usedCount'] === 0) {
            $this->logSearch($ctx, $question, 0);
            View::render('ask', [
                'question' => $question, 'answer' => null, 'citations' => [],
                'noMatch' => true, 'askError' => null,
                'recentSearches' => $this->loadRecentSearches($ctx),
            ]);
            return;
        }

        try {
            $llm = new AnthropicClient($ctx->anthropicApiKey, $ctx->llmModel);
            $answer = $llm->generateGroundedAnswer($question, $retrieval['contextBlock']);
        } catch (LlmError $e) {
            // Never fabricate a success here - the retrieval pipeline (Function invoke, poll,
            // ranking) already succeeded, so surface exactly what failed: the LLM call itself.
            View::render('ask', [
                'question' => $question, 'answer' => null, 'citations' => $retrieval['citations'],
                'noMatch' => false, 'askError' => $e->getMessage(),
                'recentSearches' => $recentSearches,
            ]);
            return;
        }

        $this->logSearch($ctx, $question, count($retrieval['citations']));

        View::render('ask', [
            'question' => $question, 'answer' => $answer, 'citations' => $retrieval['citations'],
            'noMatch' => false, 'askError' => null,
            'recentSearches' => $this->loadRecentSearches($ctx),
        ]);
    }

    private function logSearch(AppContext $ctx, string $queryText, int $resultCount): void
    {
        try {
            $fields = ['queryText' => $queryText, 'resultCount' => $resultCount];
            // userId must be a real ObjectId or omitted entirely - never a placeholder string.
            // Only included when a real, signed-in account (not the anonymous guest) is present.
            if ($ctx->isSignedIn() && $ctx->userId() !== null) {
                $fields['userId'] = $ctx->userId();
                $fields['userName'] = $ctx->displayName() ?? 'Someone';
            }
            $ctx->mudbase->createDocument($ctx->searchLogCollectionId, $fields);
        } catch (MudbaseApiError) {
            // Logging is best-effort - a failed search_log write must never block the answer
            // that was already computed from reaching the visitor.
        }
    }

    /** @return list<array<string, mixed>> */
    private function loadRecentSearches(AppContext $ctx): array
    {
        try {
            return $ctx->mudbase->listDocuments(
                $ctx->searchLogCollectionId,
                null,
                '-createdAt',
                1,
                self::RECENT_SEARCHES_LIMIT,
            )['data'];
        } catch (MudbaseApiError) {
            return [];
        }
    }

    private function requireCsrf(): void
    {
        if (!Csrf::verify($_POST['_csrf'] ?? null)) {
            Flash::set('error', 'Your session expired — please try again.');
            Response::redirect('/ask');
        }
    }
}
