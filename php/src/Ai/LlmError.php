<?php

declare(strict_types=1);

namespace App\Ai;

/** Raised when the Anthropic completion call is misconfigured, fails, or returns no usable text. */
final class LlmError extends \RuntimeException
{
}
