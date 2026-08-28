<?php

namespace App\Exceptions;

use RuntimeException;

class MobileApiException extends RuntimeException
{
    public function __construct(
        string $message,
        private readonly int $status,
        private readonly ?string $errorCode = null,
    ) {
        parent::__construct($message, $status);
    }

    public function status(): int
    {
        return $this->status;
    }

    public function errorCode(): ?string
    {
        return $this->errorCode;
    }
}
