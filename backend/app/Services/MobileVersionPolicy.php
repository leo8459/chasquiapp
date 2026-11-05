<?php

namespace App\Services;

use Symfony\Component\HttpKernel\Exception\HttpException;

class MobileVersionPolicy
{
    public function metadata(string $installedVersion): array
    {
        $required = trim((string) config('mobile.required_version'));
        $downloadUrl = trim((string) config('mobile.download_url'));
        if ($downloadUrl === '') {
            $downloadUrl = rtrim((string) config('app.url'), '/').'/descargas/';
        }

        if (! preg_match('/^\d+\.\d+\.\d+\+\d+$/D', $required)
            || ! filter_var($downloadUrl, FILTER_VALIDATE_URL)
            || ! in_array(parse_url($downloadUrl, PHP_URL_SCHEME), ['http', 'https'], true)) {
            throw new HttpException(503, 'No se pudo comprobar la versión autorizada. Intenta nuevamente.');
        }

        return [
            'required_version' => $required,
            'download_url' => $downloadUrl,
            'update_required' => $installedVersion !== $required,
        ];
    }
}
