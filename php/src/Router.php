<?php

declare(strict_types=1);

namespace App;

/**
 * A small path-pattern router — dispatch logic kept separate from the per-route controller files
 * it dispatches into. Supports `{param}` segments only (no wildcards/regex authoring needed for
 * this app's route list). Ported verbatim from the sibling kanban/social PHP ports.
 */
final class Router
{
    /** @var array<string, list<array{pattern: string, names: list<string>, handler: callable}>> */
    private array $routes = [];

    public function get(string $path, callable $handler): void
    {
        $this->add('GET', $path, $handler);
    }

    public function post(string $path, callable $handler): void
    {
        $this->add('POST', $path, $handler);
    }

    private function add(string $method, string $path, callable $handler): void
    {
        $names = [];
        $pattern = preg_replace_callback('#\{([a-zA-Z_][a-zA-Z0-9_]*)\}#', function (array $m) use (&$names): string {
            $names[] = $m[1];
            return '(?P<' . $m[1] . '>[^/]+)';
        }, rtrim($path, '/') ?: '/');

        $this->routes[$method][] = [
            'pattern' => '#^' . $pattern . '$#',
            'names' => $names,
            'handler' => $handler,
        ];
    }

    /**
     * @param callable(): void $notFound
     */
    public function dispatch(string $method, string $requestUri, callable $notFound): void
    {
        $path = parse_url($requestUri, PHP_URL_PATH);
        $path = is_string($path) ? $path : '/';
        $path = rtrim($path, '/');
        if ($path === '') {
            $path = '/';
        }

        foreach ($this->routes[$method] ?? [] as $route) {
            if (preg_match($route['pattern'], $path, $matches) === 1) {
                $params = [];
                foreach ($route['names'] as $name) {
                    $params[$name] = urldecode($matches[$name]);
                }
                ($route['handler'])($params);
                return;
            }
        }

        $notFound();
    }
}
