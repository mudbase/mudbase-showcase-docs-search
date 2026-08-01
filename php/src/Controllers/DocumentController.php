<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Ai\RetrievalScorer;
use App\Http\AppContext;
use App\Http\Csrf;
use App\Http\Flash;
use App\Http\Response;
use App\Mudbase\MudbaseApiError;
use App\View;

/**
 * The document library — mirrors the reference app's `/`, `/documents/[id]`, `/documents/new`,
 * and `/documents/[id]/edit` (src/app/page.tsx, src/app/documents/**). Guest browsing and search
 * are public (an anonymous session already covers the required collection read — see
 * bootstrap.php); create/edit/delete require a real signed-in account.
 *
 * Unlike the kanban PHP port's board (where every signed-in role gets the exact CRUD permissions
 * Mudbase's own collection permissions grant, so the platform is the sole security boundary),
 * this project ships a single "customer" role with full collection CRUD — Mudbase has no concept
 * of per-document ownership. "Only the author can edit/delete their own document" is therefore an
 * application-level rule this controller must enforce itself, exactly mirroring the reference
 * app's client-side `isOwner` gate (src/app/documents/[id]/page.tsx) but enforced server-side here
 * since there is no client to trust.
 */
final class DocumentController
{
    private const MAX_TITLE_LENGTH = 200;
    private const MAX_CONTENT_LENGTH = 50000;
    private const MAX_TAGS_LENGTH = 500;
    private const LIBRARY_LIMIT = 100;

    /** @param array<string, string> $params */
    public function index(array $params): void
    {
        $ctx = AppContext::current();
        $query = trim((string) ($_GET['q'] ?? ''));

        $documents = [];
        $error = null;
        try {
            $result = $ctx->mudbase->listDocuments($ctx->documentsCollectionId, null, '-createdAt', 1, self::LIBRARY_LIMIT);
            $documents = array_values(array_filter(
                $result['data'],
                static fn (array $document): bool => RetrievalScorer::matchesSearchTerm($document, $query),
            ));
        } catch (MudbaseApiError $e) {
            $error = "Couldn't load the document library right now: {$e->getMessage()}";
        }

        View::render('home', ['documents' => $documents, 'query' => $query, 'error' => $error]);
    }

    /** @param array{id: string} $params */
    public function show(array $params): void
    {
        $ctx = AppContext::current();

        try {
            $document = $ctx->mudbase->getDocument($ctx->documentsCollectionId, $params['id']);
        } catch (MudbaseApiError $e) {
            View::render('errors/not_found', [], $e->isNotFound() ? 404 : 500);
            return;
        }

        $isOwner = $ctx->isSignedIn() && $ctx->userId() === (string) ($document['authorId'] ?? '');
        View::render('document_detail', ['document' => $document, 'isOwner' => $isOwner]);
    }

    /** @param array<string, string> $params */
    public function newForm(array $params): void
    {
        $ctx = AppContext::current();
        $ctx->requireSignIn('/documents/new');
        View::render('document_form', [
            'mode' => 'create',
            'formAction' => '/documents',
            'title' => '', 'content' => '', 'tags' => '',
            'error' => null,
        ]);
    }

    /** @param array<string, string> $params */
    public function create(array $params): void
    {
        $ctx = AppContext::current();
        $ctx->requireSignIn('/documents/new');
        $this->requireCsrf('/documents/new');

        $title = trim((string) ($_POST['title'] ?? ''));
        $content = trim((string) ($_POST['content'] ?? ''));
        $tags = trim((string) ($_POST['tags'] ?? ''));

        $validationError = $this->validate($title, $content, $tags);
        if ($validationError !== null) {
            View::render('document_form', [
                'mode' => 'create', 'formAction' => '/documents',
                'title' => $title, 'content' => $content, 'tags' => $tags,
                'error' => $validationError,
            ]);
            return;
        }

        try {
            $created = $ctx->mudbase->createDocument($ctx->documentsCollectionId, [
                'title' => $title,
                'content' => $content,
                'tags' => $tags,
                'authorId' => $ctx->userId(),
                'authorName' => $ctx->displayName() ?? 'Someone',
            ]);
        } catch (MudbaseApiError $e) {
            View::render('document_form', [
                'mode' => 'create', 'formAction' => '/documents',
                'title' => $title, 'content' => $content, 'tags' => $tags,
                'error' => $e->getMessage(),
            ]);
            return;
        }

        Response::redirect('/documents/' . urlencode((string) $created['_id']));
    }

    /** @param array{id: string} $params */
    public function editForm(array $params): void
    {
        $ctx = AppContext::current();
        $documentId = $params['id'];
        $ctx->requireSignIn("/documents/{$documentId}/edit");

        try {
            $document = $ctx->mudbase->getDocument($ctx->documentsCollectionId, $documentId);
        } catch (MudbaseApiError $e) {
            View::render('errors/not_found', [], $e->isNotFound() ? 404 : 500);
            return;
        }

        if ($ctx->userId() !== (string) ($document['authorId'] ?? '')) {
            Flash::set('error', 'You can only edit documents you authored.');
            Response::redirect('/documents/' . urlencode($documentId));
        }

        View::render('document_form', [
            'mode' => 'edit',
            'formAction' => "/documents/{$documentId}/edit",
            'title' => (string) ($document['title'] ?? ''),
            'content' => (string) ($document['content'] ?? ''),
            'tags' => (string) ($document['tags'] ?? ''),
            'error' => null,
        ]);
    }

    /** @param array{id: string} $params */
    public function update(array $params): void
    {
        $ctx = AppContext::current();
        $documentId = $params['id'];
        $ctx->requireSignIn("/documents/{$documentId}/edit");
        $this->requireCsrf("/documents/{$documentId}/edit");

        try {
            $existing = $ctx->mudbase->getDocument($ctx->documentsCollectionId, $documentId);
        } catch (MudbaseApiError $e) {
            View::render('errors/not_found', [], $e->isNotFound() ? 404 : 500);
            return;
        }

        // The actual security boundary for "only the author may edit": Mudbase's own "customer"
        // role grants full collection CRUD to every signed-in account, so this application-level
        // check is what prevents one member editing another's document — see class docblock.
        if ($ctx->userId() !== (string) ($existing['authorId'] ?? '')) {
            Flash::set('error', 'You can only edit documents you authored.');
            Response::redirect('/documents/' . urlencode($documentId));
        }

        $title = trim((string) ($_POST['title'] ?? ''));
        $content = trim((string) ($_POST['content'] ?? ''));
        $tags = trim((string) ($_POST['tags'] ?? ''));

        $validationError = $this->validate($title, $content, $tags);
        if ($validationError !== null) {
            View::render('document_form', [
                'mode' => 'edit', 'formAction' => "/documents/{$documentId}/edit",
                'title' => $title, 'content' => $content, 'tags' => $tags,
                'error' => $validationError,
            ]);
            return;
        }

        try {
            $ctx->mudbase->updateDocument($ctx->documentsCollectionId, $documentId, [
                'title' => $title,
                'content' => $content,
                'tags' => $tags,
            ]);
        } catch (MudbaseApiError $e) {
            View::render('document_form', [
                'mode' => 'edit', 'formAction' => "/documents/{$documentId}/edit",
                'title' => $title, 'content' => $content, 'tags' => $tags,
                'error' => $e->getMessage(),
            ]);
            return;
        }

        Response::redirect('/documents/' . urlencode($documentId));
    }

    /** @param array{id: string} $params */
    public function delete(array $params): void
    {
        $ctx = AppContext::current();
        $documentId = $params['id'];
        $ctx->requireSignIn('/documents/' . urlencode($documentId));
        $this->requireCsrf('/documents/' . urlencode($documentId));

        try {
            $existing = $ctx->mudbase->getDocument($ctx->documentsCollectionId, $documentId);
        } catch (MudbaseApiError $e) {
            View::render('errors/not_found', [], $e->isNotFound() ? 404 : 500);
            return;
        }

        if ($ctx->userId() !== (string) ($existing['authorId'] ?? '')) {
            Flash::set('error', 'You can only delete documents you authored.');
            Response::redirect('/documents/' . urlencode($documentId));
        }

        try {
            $ctx->mudbase->deleteDocument($ctx->documentsCollectionId, $documentId);
        } catch (MudbaseApiError $e) {
            Flash::set('error', "That didn't work: {$e->getMessage()}");
            Response::redirect('/documents/' . urlencode($documentId));
        }

        Flash::set('success', 'Document deleted.');
        Response::redirect('/');
    }

    private function validate(string $title, string $content, string $tags): ?string
    {
        if ($title === '') {
            return 'Title is required.';
        }
        if (mb_strlen($title) > self::MAX_TITLE_LENGTH) {
            return 'Title is too long (max ' . self::MAX_TITLE_LENGTH . ' characters).';
        }
        if ($content === '') {
            return 'Content is required.';
        }
        if (mb_strlen($content) > self::MAX_CONTENT_LENGTH) {
            return 'Content is too long (max ' . self::MAX_CONTENT_LENGTH . ' characters).';
        }
        if (mb_strlen($tags) > self::MAX_TAGS_LENGTH) {
            return 'Tags are too long (max ' . self::MAX_TAGS_LENGTH . ' characters).';
        }
        return null;
    }

    private function requireCsrf(string $fallbackRedirect): void
    {
        if (!Csrf::verify($_POST['_csrf'] ?? null)) {
            Flash::set('error', 'Your session expired — please try again.');
            Response::redirect($fallbackRedirect);
        }
    }
}
