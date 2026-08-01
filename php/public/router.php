<?php

declare(strict_types=1);

/**
 * Entry script for PHP's built-in dev server: `php -S localhost:8080 -t public public/router.php`.
 * Static assets (public/assets/**) are served as-is; every other request goes through the front
 * controller (index.php), which is also what a real web server should be configured to rewrite
 * all non-file requests to.
 */

$requestPath = urldecode((string) parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH));
$candidate = __DIR__ . $requestPath;

if ($requestPath !== '/' && is_file($candidate) && !str_ends_with($requestPath, '.php')) {
    return false;
}

require __DIR__ . '/index.php';
