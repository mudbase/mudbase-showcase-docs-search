<?php

declare(strict_types=1);

namespace App\Mudbase;

use Mudbase\Sdk\ApiException;

/**
 * A friendlier wrapper around the generated SDK's ApiException. The generated client throws
 * ApiException for every non-2xx response (Guzzle's default http_errors behavior converts 4xx/5xx
 * into a RequestException, which every generated *WithHttpInfo() method catches and rethrows as
 * ApiException with the raw JSON error body attached) — this class decodes that body once so
 * controllers can show a clean message instead of re-parsing JSON at every call site. Ported
 * verbatim from the sibling kanban/social PHP ports.
 */
final class MudbaseApiError extends \RuntimeException
{
    /** @var array<string, mixed> */
    private array $details;

    /**
     * @param array<string, mixed> $details
     */
    public function __construct(string $message, private readonly int $statusCode, array $details = [])
    {
        parent::__construct($message, $statusCode);
        $this->details = $details;
    }

    public static function fromApiException(ApiException $exception): self
    {
        $body = $exception->getResponseBody();
        $details = [];
        if (is_string($body) && $body !== '') {
            $decoded = json_decode($body, true);
            if (is_array($decoded)) {
                $details = $decoded;
            }
        } elseif ($body instanceof \stdClass) {
            $details = (array) $body;
        }

        $message = $details['error'] ?? $details['message'] ?? $exception->getMessage();
        $code = $exception->getCode();

        return new self(is_string($message) ? $message : $exception->getMessage(), $code > 0 ? $code : 500, $details);
    }

    public static function fromResponse(int $statusCode, mixed $decodedBody): self
    {
        $details = is_array($decodedBody) ? $decodedBody : [];
        $message = $details['error'] ?? $details['message'] ?? "Mudbase request failed ({$statusCode})";
        return new self(is_string($message) ? $message : "Mudbase request failed ({$statusCode})", $statusCode, $details);
    }

    public function getStatusCode(): int
    {
        return $this->statusCode;
    }

    /** @return array<string, mixed> */
    public function getDetails(): array
    {
        return $this->details;
    }

    public function isNotFound(): bool
    {
        return $this->statusCode === 404;
    }

    public function isForbidden(): bool
    {
        return $this->statusCode === 403;
    }

    public function isUnauthorized(): bool
    {
        return $this->statusCode === 401;
    }
}
