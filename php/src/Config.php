<?php

declare(strict_types=1);

namespace App;

/**
 * Loads `.env` (a plain KEY=VALUE file, no external dependency needed for a handful of vars)
 * once per process and exposes required/optional lookups. Ported verbatim from the sibling
 * kanban/social PHP ports — same fail-fast behavior as the reference Next.js app's
 * src/lib/config.ts (requireEnv throws immediately on a missing var instead of letting the app
 * boot broken).
 */
final class Config
{
    /** @var array<string, string> */
    private static array $values = [];

    private static bool $loaded = false;

    public static function load(string $rootDir): void
    {
        if (self::$loaded) {
            return;
        }
        self::$loaded = true;

        foreach ([$rootDir . '/.env.local', $rootDir . '/.env'] as $path) {
            if (!is_file($path)) {
                continue;
            }
            $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            if ($lines === false) {
                continue;
            }
            foreach ($lines as $line) {
                $trimmed = trim($line);
                if ($trimmed === '' || str_starts_with($trimmed, '#')) {
                    continue;
                }
                $eq = strpos($trimmed, '=');
                if ($eq === false) {
                    continue;
                }
                $key = trim(substr($trimmed, 0, $eq));
                $value = trim(substr($trimmed, $eq + 1));
                $value = trim($value, "\"'");
                self::$values[$key] = $value;
            }
            break; // .env.local wins over .env when both exist, same convention as npm/Next.js
        }

        // Real process env vars (e.g. set by a host/PaaS) override the .env file.
        foreach ($_ENV as $key => $value) {
            if (is_string($value) && $value !== '') {
                self::$values[$key] = $value;
            }
        }
    }

    public static function required(string $name): string
    {
        $value = self::$values[$name] ?? getenv($name);
        if ($value === false || $value === null || $value === '') {
            throw new \RuntimeException("Missing required environment variable: {$name}");
        }
        return $value;
    }

    public static function optional(string $name, string $default): string
    {
        $value = self::$values[$name] ?? getenv($name);
        if ($value === false || $value === null || $value === '') {
            return $default;
        }
        return $value;
    }

    /** Returns null (not the SDK's usual "throw") for genuinely optional server-only secrets. */
    public static function optionalOrNull(string $name): ?string
    {
        $value = self::$values[$name] ?? getenv($name);
        if ($value === false || $value === null || $value === '') {
            return null;
        }
        return $value;
    }
}
