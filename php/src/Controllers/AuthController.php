<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Http\AppContext;
use App\Http\Csrf;
use App\Http\Flash;
use App\Http\Response;
use App\Mudbase\MudbaseApiError;
use App\View;

/**
 * Login/register/logout — mirrors the reference app's `/login`, `/register`, and `useAuth()`.
 * Role is never taken from the form: this project ships a single application role ("customer",
 * the Multi-Role feature's default), so self-signup always registers as "customer".
 */
final class AuthController
{
    private const ROLE = 'customer';

    /** @param array<string, string> $params */
    public function loginForm(array $params): void
    {
        $ctx = AppContext::current();
        if ($ctx->isSignedIn()) {
            Response::redirect('/');
        }
        View::render('login', ['redirectTo' => (string) ($_GET['redirect'] ?? '/')]);
    }

    /** @param array<string, string> $params */
    public function login(array $params): void
    {
        $ctx = AppContext::current();
        $this->requireCsrf('/login');

        $email = trim((string) ($_POST['email'] ?? ''));
        $password = (string) ($_POST['password'] ?? '');
        $redirectTo = (string) ($_POST['redirectTo'] ?? '/');

        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $password === '') {
            Flash::set('error', 'Enter a valid email address and password.');
            Response::redirect('/login');
        }

        try {
            $session = $ctx->mudbase->login($email, $password);
        } catch (MudbaseApiError $e) {
            $code = $e->getDetails()['code'] ?? null;
            Flash::set(
                'error',
                $code === 'EMAIL_VERIFICATION_REQUIRED'
                    ? 'Please verify your email first — check your inbox for the verification link, then sign in.'
                    : $e->getMessage(),
            );
            Response::redirect('/login');
        }

        $this->establishSession($session['token'], $session['refreshToken'], $session['user']);

        // redirectTo travels here from an unauthenticated action (creating/editing a document,
        // asking a question that needs the search log tied to an account) that sent the visitor
        // to /login?redirect=... - validate it as a same-site path before trusting it, same guard
        // as Response::redirectToSafe uses everywhere else.
        Response::redirectToSafe($redirectTo, '/');
    }

    /** @param array<string, string> $params */
    public function registerForm(array $params): void
    {
        $ctx = AppContext::current();
        if ($ctx->isSignedIn()) {
            Response::redirect('/');
        }
        View::render('register', ['redirectTo' => (string) ($_GET['redirect'] ?? '/')]);
    }

    /** @param array<string, string> $params */
    public function register(array $params): void
    {
        $ctx = AppContext::current();
        $this->requireCsrf('/register');

        $firstName = trim((string) ($_POST['firstName'] ?? ''));
        $lastName = trim((string) ($_POST['lastName'] ?? ''));
        $email = trim((string) ($_POST['email'] ?? ''));
        $password = (string) ($_POST['password'] ?? '');
        $agreedToTerms = ($_POST['agreedToTerms'] ?? null) === 'on';
        $redirectTo = (string) ($_POST['redirectTo'] ?? '/');

        $errors = [];
        if ($firstName === '') {
            $errors[] = 'First name is required.';
        }
        if ($lastName === '') {
            $errors[] = 'Last name is required.';
        }
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $errors[] = 'Enter a valid email address.';
        }
        if (strlen($password) < 8) {
            $errors[] = 'Password must be at least 8 characters.';
        }
        if (!$agreedToTerms) {
            $errors[] = 'You must agree to the Terms of Service and Privacy Policy.';
        }

        if ($errors !== []) {
            Flash::set('error', implode(' ', $errors));
            Response::redirect('/register');
        }

        try {
            $result = $ctx->mudbase->registerWithRole(self::ROLE, $email, $password, $firstName, $lastName, $agreedToTerms);
        } catch (MudbaseApiError $e) {
            Flash::set('error', $e->getMessage());
            Response::redirect('/register');
        }

        // Defensive — see MudbaseClient::registerWithRole() docblock: this project's reference
        // web app has no /verify-email route, but never assume a session exists just because the
        // HTTP call succeeded.
        if ($result['token'] === null) {
            Flash::set('success', "Account created. Check {$email} for a verification link if one was sent, then sign in.");
            Response::redirect('/login');
        }

        $this->establishSession($result['token'], $result['refreshToken'], $result['user'] ?? []);
        Response::redirectToSafe($redirectTo, '/');
    }

    /** @param array<string, string> $params */
    public function logout(array $params): void
    {
        $ctx = AppContext::current();
        $this->requireCsrf('/');

        $ctx->mudbase->logout();
        unset($_SESSION['mudbase_token'], $_SESSION['mudbase_refresh_token'], $_SESSION['mudbase_user']);
        session_regenerate_id(true);

        Response::redirect('/');
    }

    /** @param array<string, mixed> $user */
    private function establishSession(string $token, ?string $refreshToken, array $user): void
    {
        // Regenerate the session id on every privilege change (anonymous guest -> real account)
        // so a session identifier issued before authentication can never be reused to ride along
        // with the authenticated one.
        session_regenerate_id(true);

        $_SESSION['mudbase_token'] = $token;
        $_SESSION['mudbase_refresh_token'] = $refreshToken;
        $_SESSION['mudbase_user'] = $user;

        // Rebuild the request-scoped context so anything checked later in this same request
        // (redirect targets, layout nav) reflects the account we just signed into, not the guest
        // we booted this request as.
        $ctx = AppContext::current();
        AppContext::set(new AppContext(
            mudbase: $ctx->mudbase->withToken($token, $refreshToken),
            user: $user,
            projectId: $ctx->projectId,
            documentsCollectionId: $ctx->documentsCollectionId,
            searchLogCollectionId: $ctx->searchLogCollectionId,
            mudbaseUrl: $ctx->mudbaseUrl,
            functionId: $ctx->functionId,
            functionsApiKey: $ctx->functionsApiKey,
            anthropicApiKey: $ctx->anthropicApiKey,
            llmModel: $ctx->llmModel,
        ));
    }

    private function requireCsrf(string $fallbackRedirect): void
    {
        if (!Csrf::verify($_POST['_csrf'] ?? null)) {
            Flash::set('error', 'Your session expired — please try again.');
            Response::redirect($fallbackRedirect);
        }
    }
}
