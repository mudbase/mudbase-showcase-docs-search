<?php

declare(strict_types=1);

namespace App;

use App\Http\AppContext;
use App\Http\Flash;

/**
 * Renders a view file inside the shared layout. Deliberately simple (no template engine — plain
 * PHP `.php` view files, matching the "plain PHP, no framework" brief) but always routes through
 * the same layout so header/nav/flash markup lives in exactly one place. Ported from the sibling
 * kanban/social PHP ports' View.php.
 */
final class View
{
    /**
     * @param array<string, mixed> $data
     */
    public static function render(string $view, array $data = [], int $statusCode = 200): void
    {
        http_response_code($statusCode);
        extract($data, EXTR_SKIP);
        $context = AppContext::current();
        $flash = Flash::consume();

        $viewFile = __DIR__ . "/views/{$view}.php";
        if (!is_file($viewFile)) {
            throw new \RuntimeException("View not found: {$view}");
        }

        ob_start();
        require $viewFile;
        $content = ob_get_clean();

        require __DIR__ . '/views/layout.php';
    }

    public static function escape(?string $value): string
    {
        return htmlspecialchars($value ?? '', ENT_QUOTES, 'UTF-8');
    }
}
