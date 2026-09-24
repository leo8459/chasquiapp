<?php

namespace App\Services\Autenticacion;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;

class SiopLoginService
{
    public function authenticate(string $alias, string $password): array
    {
        $url = trim((string) config('services.siop_login.url'));
        $token = trim((string) config('services.siop_login.token'));

        if ($url === '' || $token === '') {
            throw new MobileApiException(
                'El inicio de sesion SIOP no esta configurado.',
                503,
                'SIOP_LOGIN_NOT_CONFIGURED',
            );
        }

        try {
            $response = Http::acceptJson()
                ->asJson()
                ->withToken($token)
                ->connectTimeout(10)
                ->timeout(max(1, (int) config('services.siop_login.timeout', 15)))
                ->withOptions([
                    'verify' => (bool) config('services.siop_login.verify_ssl', true),
                ])
                ->post($url, [
                    'alias' => $alias,
                    'password' => $password,
                ]);
        } catch (ConnectionException) {
            throw new MobileApiException(
                'No pudimos comunicarnos con SIOP. Intenta nuevamente.',
                503,
                'SIOP_LOGIN_UNAVAILABLE',
            );
        }

        if (! $response->successful()) {
            $this->throwForFailedResponse($response);
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio una respuesta de inicio de sesion no valida.',
                502,
                'SIOP_LOGIN_INVALID_RESPONSE',
            );
        }

        return $payload;
    }

    private function throwForFailedResponse(Response $response): never
    {
        $status = $response->status();
        $message = trim((string) $response->json('message'));

        if ($status === 401) {
            $normalizedMessage = strtolower($message);
            if (str_contains($normalizedMessage, 'token de acceso')
                || str_contains($normalizedMessage, 'token invalido')
                || str_contains($normalizedMessage, 'token inválido')) {
                throw new MobileApiException(
                    'El servicio de autenticacion SIOP requiere renovar su token de integracion.',
                    503,
                    'SIOP_LOGIN_TOKEN_INVALID',
                );
            }

            throw new MobileApiException(
                'Usuario o contrasena incorrectos.',
                401,
                'INVALID_CREDENTIALS',
            );
        }

        if ($status === 429) {
            throw new MobileApiException(
                'Se realizaron demasiados intentos. Espera un momento y vuelve a intentar.',
                429,
                'SIOP_LOGIN_RATE_LIMITED',
            );
        }

        if ($status === 422) {
            throw new MobileApiException(
                $message !== '' ? $message : 'SIOP no pudo validar las credenciales enviadas.',
                422,
                'SIOP_LOGIN_VALIDATION_ERROR',
            );
        }

        throw new MobileApiException(
            'El servicio de inicio de sesion SIOP no esta disponible en este momento.',
            503,
            'SIOP_LOGIN_FAILED',
        );
    }
}
