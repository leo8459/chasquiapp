<?php

namespace App\Services\Gestion;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SiopGasolinaService
{
    public function create(array $data, UploadedFile $photo): array
    {
        $url = trim((string) config('services.siop_gasolinas.url'));
        $token = trim((string) config('services.siop_gasolinas.create_token'));
        $timeout = max(1, (int) config('services.siop_gasolinas.timeout', 20));
        $verifySsl = (bool) config('services.siop_gasolinas.verify_ssl', true);

        if ($url === '' || $token === '') {
            throw new MobileApiException(
                'El servicio para crear registros de gasolina no esta configurado.',
                503,
                'SIOP_GASOLINAS_CREATE_NOT_CONFIGURED',
            );
        }

        try {
            $response = Http::acceptJson()
                ->withToken($token)
                ->connectTimeout(min(5, $timeout))
                ->timeout(max(30, $timeout))
                ->withOptions(['verify' => $verifySsl])
                ->attach(
                    'invoice_photo',
                    $photo->getContent(),
                    $photo->getClientOriginalName(),
                    ['Content-Type' => $photo->getMimeType() ?: 'image/jpeg'],
                )
                ->post($url, $data)
                ->throw();
        } catch (RequestException $error) {
            $payload = $error->response->json();
            $message = is_array($payload) ? trim((string) ($payload['message'] ?? '')) : '';

            throw new MobileApiException(
                $message !== '' ? $message : 'SIOP rechazo el registro de gasolina.',
                $error->response->status(),
                'SIOP_GASOLINA_CREATE_REJECTED',
            );
        } catch (ConnectionException $error) {
            Log::warning('No se pudo crear el registro de gasolina SIOP.', [
                'exception' => $error::class,
                'message' => $error->getMessage(),
            ]);

            throw new MobileApiException(
                'No pudimos crear el registro de gasolina en este momento.',
                503,
                'SIOP_GASOLINA_CREATE_UNAVAILABLE',
            );
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'El registro fue enviado, pero SIOP devolvio una respuesta inesperada.',
                502,
                'SIOP_GASOLINA_CREATE_INVALID_RESPONSE',
            );
        }

        $raw = $payload['data'] ?? $payload['gasolina'] ?? null;

        return [
            'message' => trim((string) ($payload['message'] ?? 'Registro de gasolina creado correctamente.')),
            'gasolina' => is_array($raw) ? $this->normalizeItem($raw) : null,
        ];
    }

    public function list(int $page = 1, int $perPage = 20): array
    {
        $url = trim((string) config('services.siop_gasolinas.url'));
        $token = trim((string) config('services.siop_gasolinas.read_token'));
        $timeout = max(1, (int) config('services.siop_gasolinas.timeout', 20));
        $verifySsl = (bool) config('services.siop_gasolinas.verify_ssl', true);

        if ($url === '' || $token === '') {
            throw new MobileApiException(
                'El servicio de gasolina no esta configurado.',
                503,
                'SIOP_GASOLINAS_NOT_CONFIGURED',
            );
        }

        $query = ['page' => $page, 'per_page' => $perPage];

        try {
            $payload = $this->fetch($url, $token, $query, $timeout, $verifySsl);
        } catch (ConnectionException|RequestException $error) {
            if ($verifySsl) {
                try {
                    $payload = $this->fetch($url, $token, $query, $timeout, false);
                } catch (ConnectionException|RequestException $retryError) {
                    $error = $retryError;
                }
            }

            if (! isset($payload)) {
                Log::warning('No se pudo consultar gasolina SIOP.', [
                    'exception' => $error::class,
                    'message' => $error->getMessage(),
                    'page' => $page,
                ]);
                throw new MobileApiException(
                    'No pudimos consultar los registros de gasolina.',
                    503,
                    'SIOP_GASOLINAS_UNAVAILABLE',
                );
            }
        }

        $items = is_array($payload['data'] ?? null) ? $payload['data'] : [];

        return [
            'current_page' => (int) ($payload['current_page'] ?? $page),
            'last_page' => max(1, (int) ($payload['last_page'] ?? 1)),
            'per_page' => (int) ($payload['per_page'] ?? $perPage),
            'total' => (int) ($payload['total'] ?? count($items)),
            'data' => array_values(array_filter(array_map(
                fn (mixed $item): ?array => is_array($item) ? $this->normalizeItem($item) : null,
                $items,
            ))),
        ];
    }

    private function fetch(string $url, string $token, array $query, int $timeout, bool $verifySsl): array
    {
        $response = Http::acceptJson()
            ->withToken($token)
            ->connectTimeout(min(5, $timeout))
            ->timeout($timeout)
            ->retry(1, 250)
            ->withOptions(['verify' => $verifySsl])
            ->get($url, $query)
            ->throw();

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio una respuesta de gasolina que no pudimos leer.',
                502,
                'SIOP_GASOLINAS_INVALID_RESPONSE',
            );
        }

        return $payload;
    }

    private function normalizeItem(array $item): array
    {
        $driver = is_array($item['driver'] ?? null) ? $item['driver'] : [];
        $vehicle = is_array($item['vehicle'] ?? null) ? $item['vehicle'] : [];

        return [
            'id' => (int) ($item['id'] ?? 0),
            'station_name' => trim((string) ($item['station_name'] ?? $item['estacion'] ?? '')),
            'total_amount' => $item['total_amount'] ?? $item['monto_total'] ?? null,
            'date_time' => trim((string) ($item['date_time'] ?? $item['fecha_emision'] ?? '')),
            'invoice_number' => trim((string) ($item['invoice_number'] ?? $item['numero_factura'] ?? '')),
            'customer_name' => trim((string) ($item['customer_name'] ?? $item['nombre_cliente'] ?? '')),
            'vehicle_plate' => trim((string) ($item['vehicle_plate'] ?? $vehicle['placa'] ?? '')),
            'driver_name' => trim((string) ($item['driver_name'] ?? $driver['nombre'] ?? '')),
            'vehicle_id' => (int) ($item['vehicle_id'] ?? $vehicle['id'] ?? 0),
            'driver_id' => (int) ($item['driver_id'] ?? $item['drivers_id'] ?? $driver['id'] ?? 0),
            'liters' => $item['liters'] ?? $item['cantidad'] ?? null,
            'unit_price' => $item['unit_price'] ?? $item['precio_unitario'] ?? null,
            'estado' => trim((string) ($item['estado'] ?? '')),
            'invoice_photo_url' => $item['invoice_photo_url'] ?? null,
        ];
    }
}
