<?php

declare(strict_types=1);

require dirname(__DIR__) . '/src/bootstrap.php';

use App\Controllers\AskController;
use App\Controllers\AuthController;
use App\Controllers\DocumentController;
use App\Mudbase\MudbaseApiError;
use App\Router;
use App\View;

$router = new Router();

$documents = new DocumentController();
$ask = new AskController();
$auth = new AuthController();

$router->get('/', [$documents, 'index']);
$router->get('/documents/new', [$documents, 'newForm']);
$router->post('/documents', [$documents, 'create']);
$router->get('/documents/{id}', [$documents, 'show']);
$router->get('/documents/{id}/edit', [$documents, 'editForm']);
$router->post('/documents/{id}/edit', [$documents, 'update']);
$router->post('/documents/{id}/delete', [$documents, 'delete']);

$router->get('/ask', [$ask, 'form']);
$router->post('/ask', [$ask, 'ask']);

$router->get('/login', [$auth, 'loginForm']);
$router->post('/login', [$auth, 'login']);
$router->get('/register', [$auth, 'registerForm']);
$router->post('/register', [$auth, 'register']);
$router->post('/logout', [$auth, 'logout']);

try {
    $router->dispatch((string) $_SERVER['REQUEST_METHOD'], (string) $_SERVER['REQUEST_URI'], function (): void {
        View::render('errors/not_found', [], 404);
    });
} catch (MudbaseApiError $e) {
    if ($e->isUnauthorized()) {
        // Token expired/was revoked mid-session - clear it and redirect back to the same URL so
        // bootstrap.php re-establishes a fresh anonymous guest session on the next request,
        // mirroring the sibling social PHP port's recovery path.
        $requestedPath = (string) $_SERVER['REQUEST_URI'];
        unset($_SESSION['mudbase_token'], $_SESSION['mudbase_refresh_token'], $_SESSION['mudbase_user']);
        header('Location: ' . $requestedPath);
        exit;
    }

    View::render('errors/server_error', ['message' => $e->getMessage()], 500);
} catch (\Throwable $e) {
    View::render('errors/server_error', ['message' => $e->getMessage()], 500);
}
