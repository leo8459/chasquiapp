<?php

namespace App\Services\Cartero;

use App\Exceptions\MobileApiException;
use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SiopCourierLocationService
{
    public function __construct(
        private readonly MobileApiTokenService $mobileTokenService,
    ) {}

    public function publish(?string $mobileToken, array $location): array
    {
        $payload = $this->mobileTokenService->getPayload($mobileToken);
        $siopToken = trim((string) ($payload['siop_access_token'] ?? ''));
        if ($siopToken === '') {
            throw new MobileApiException(
                'Tu sesion SIOP no esta disponible. Vuelve a iniciar sesion.',
                401,
                'SIOP_SESSION_REQUIRED',
            );
        }

        $data = array_filter([
            'latitude' => (float) $location['latitude'],
            'longitude' => (float) $location['longitude'],
            'accuracy' => isset($location['accuracy']) ? (float) $location['accuracy'] : null,
            'altitude' => isset($location['altitude']) ? (float) $location['altitude'] : null,
            'speed' => isset($location['speed']) ? (float) $location['speed'] : null,
            'heading' => isset($location['heading']) ? (float) $location['heading'] : null,
            'captured_at' => $location['captured_at'] ?? null,
        ], static fn (mixed $value): bool => $value !== null && $value !== '');

        return $this->request('POST', $siopToken, $data);
    }

    public function latest(): array
    {
        return $this->request('GET', $this->integrationToken());
    }

    private function request(string $method, string $bearerToken, array $data = []): array
    {
        try {
            $request = Http::acceptJson()
                ->asJson()
                ->withToken($bearerToken)
                ->withHeaders(['X-API-Token' => $this->integrationToken()])
                ->connectTimeout(30)
                ->timeout(max(30, (int) config('services.siop_courier_location.timeout', 30)))
                ->withOptions([
                    'verify' => (bool) config('services.siop_courier_location.verify_ssl', true),
                ]);

            $response = $method === 'POST'
                ? $request->post($this->url(), $data)
                : $request->get($this->url());
        } catch (ConnectionException) {
            throw new MobileApiException(
                'No pudimos comunicarnos con el servicio de ubicacion SIOP.',
                503,
                'SIOP_COURIER_LOCATION_UNAVAILABLE',
            );
        }

        if (! $response->successful()) {
            $this->throwForFailedResponse($response);
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio la ubicacion en un formato no valido.',
                502,
                'SIOP_COURIER_LOCATION_INVALID_RESPONSE',
            );
        }

        return $payload;
    }

    private function throwForFailedResponse(Response $response): never
    {
        $status = $response->status();
        $message = trim((string) $response->json('message'));

        Log::warning('La API de ubicacion SIOP rechazo el heartbeat.', [
            'status' => $status,
            'message' => $message,
        ]);

        if ($status === 401) {
            throw new MobileApiException(
                'Tu sesion SIOP vencio. Vuelve a iniciar sesion.',
                401,
                'SIOP_SESSION_EXPIRED',
            );
        }
        if ($status === 403) {
            throw new MobileApiException(
                'Tu cuenta no tiene permiso para reportar su ubicacion.',
                403,
                'SIOP_COURIER_LOCATION_PERMISSION_REQUIRED',
            );
        }
        if ($status === 422) {
            throw new MobileApiException(
                $message !== '' ? $message : 'La ubicacion enviada no es valida.',
                422,
                'SIOP_COURIER_LOCATION_VALIDATION_ERROR',
            );
        }

        throw new MobileApiException(
            'No pudimos actualizar la ubicacion en SIOP.',
            503,
            'SIOP_COURIER_LOCATION_FAILED',
        );
    }

    private function url(): string
    {
        $url = trim((string) config('services.siop_courier_location.url'));
        if ($url === '') {
            throw new MobileApiException(
                'El servicio de ubicacion SIOP no esta configurado.',
                503,
                'SIOP_COURIER_LOCATION_NOT_CONFIGURED',
            );
        }

        return $url;
    }

    private function integrationToken(): string
    {
        $token = trim((string) config('services.siop_courier_location.token'));
        if ($token === '') {
            throw new MobileApiException(
                'El servicio de ubicacion SIOP no esta configurado.',
                503,
                'SIOP_COURIER_LOCATION_NOT_CONFIGURED',
            );
        }

        return $token;
    }
}
