<?php

declare(strict_types=1);

namespace App\Ai;

/** Raised when the Mudbase Function invocation/poll fails, times out, or returns no result. */
final class RetrievalError extends \RuntimeException
{
}
