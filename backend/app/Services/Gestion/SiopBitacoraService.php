<?php

namespace App\Services\Gestion;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SiopBitacoraService
{
    public function vehicles(): array
    {
        return $this->catalog('vehiculos');
    }

    public function drivers(): array
    {
        return $this->catalog('conductores');
    }

    public function create(array $data, UploadedFile $photo): array
    {
        $url = trim((string) config('services.siop_bitacoras.url'));
        $token = trim((string) config('services.siop_bitacoras.create_token'));
        $timeout = max(30, (int) config('services.siop_bitacoras.timeout', 30));
        $verifySsl = (bool) config('services.siop_bitacoras.verify_ssl', true);

        if ($url === '' || $token === '') {
            throw new MobileApiException(
                'El servicio para crear bitacoras SIOP no esta configurado.',
                503,
                'SIOP_BITACORAS_CREATE_NOT_CONFIGURED',
            );
        }

        try {
            $response = Http::acceptJson()
                ->withToken($token)
                ->connectTimeout(30)
                ->timeout($timeout)
                ->withOptions(['verify' => $verifySsl])
                ->attach(
                    'odometro_photo',
                    $photo->getContent(),
                    $photo->getClientOriginalName(),
                    ['Content-Type' => $photo->getMimeType() ?: 'image/jpeg'],
                )
                ->post($url, $data)
                ->throw();
        } catch (RequestException $error) {
            $payload = $error->response->json();
            $message = is_array($payload)
                ? trim((string) ($payload['message'] ?? ''))
                : '';

            throw new MobileApiException(
                $message !== '' ? $message : 'SIOP rechazo los datos de la bitacora.',
                $error->response->status(),
                'SIOP_BITACORA_CREATE_REJECTED',
            );
        } catch (ConnectionException $error) {
            Log::warning('No se pudo crear la bitacora SIOP.', [
                'exception' => $error::class,
                'message' => $error->getMessage(),
            ]);

            throw new MobileApiException(
                'No pudimos crear la bitacora en este momento.',
                503,
                'SIOP_BITACORA_CREATE_UNAVAILABLE',
            );
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'La bitacora fue enviada, pero SIOP devolvio una respuesta inesperada.',
                502,
                'SIOP_BITACORA_CREATE_INVALID_RESPONSE',
            );
        }

        $rawBitacora = $payload['data'] ?? $payload['bitacora'] ?? null;

        return [
            'message' => trim((string) ($payload['message'] ?? 'Bitacora creada correctamente.')),
            'bitacora' => is_array($rawBitacora) ? $this->normalizeItem($rawBitacora) : null,
        ];
    }

    public function list(int $page = 1, int $perPage = 20): array
    {
        $url = trim((string) config('services.siop_bitacoras.url'));
        $token = trim((string) config('services.siop_bitacoras.read_token'));
        $timeout = max(30, (int) config('services.siop_bitacoras.timeout', 30));
        $verifySsl = (bool) config('services.siop_bitacoras.verify_ssl', true);

        if ($url === '' || $token === '') {
            throw new MobileApiException(
                'El servicio de bitacoras SIOP no esta configurado.',
                503,
                'SIOP_BITACORAS_NOT_CONFIGURED',
            );
        }

        $query = [
            'page' => max(1, $page),
            'per_page' => max(1, min(100, $perPage)),
        ];

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
                Log::warning('No se pudo consultar las bitacoras SIOP.', [
                    'exception' => $error::class,
                    'message' => $error->getMessage(),
                    'page' => $query['page'],
                ]);

                throw new MobileApiException(
                    'No pudimos consultar las bitacoras en este momento.',
                    503,
                    'SIOP_BITACORAS_UNAVAILABLE',
                );
            }
        }

        $items = is_array($payload['data'] ?? null) ? $payload['data'] : [];

        return [
            'current_page' => (int) ($payload['current_page'] ?? $query['page']),
            'last_page' => max(1, (int) ($payload['last_page'] ?? 1)),
            'per_page' => (int) ($payload['per_page'] ?? $query['per_page']),
            'total' => (int) ($payload['total'] ?? count($items)),
            'from' => isset($payload['from']) ? (int) $payload['from'] : null,
            'to' => isset($payload['to']) ? (int) $payload['to'] : null,
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
            ->connectTimeout(30)
            ->timeout($timeout)
            ->retry(1, 250)
            ->withOptions(['verify' => $verifySsl])
            ->get($url, $query)
            ->throw();

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio una respuesta de bitacoras que no pudimos leer.',
                502,
                'SIOP_BITACORAS_INVALID_RESPONSE',
            );
        }

        return $payload;
    }

    private function catalog(string $catalog): array
    {
        $baseUrl = rtrim(trim((string) config('services.siop_bitacoras.url')), '/');
        $token = trim((string) config('services.siop_bitacoras.create_token'));
        $timeout = max(30, (int) config('services.siop_bitacoras.timeout', 30));
        $verifySsl = (bool) config('services.siop_bitacoras.verify_ssl', true);

        if ($baseUrl === '' || $token === '') {
            throw new MobileApiException(
                'El servicio de catalogos de bitacoras SIOP no esta configurado.',
                503,
                'SIOP_BITACORA_CATALOG_NOT_CONFIGURED',
            );
        }

        try {
            $payload = $this->fetchCatalog($baseUrl.'/'.$catalog, $token, $timeout, $verifySsl);
        } catch (ConnectionException|RequestException $error) {
            if ($verifySsl) {
                try {
                    $payload = $this->fetchCatalog($baseUrl.'/'.$catalog, $token, $timeout, false);
                } catch (ConnectionException|RequestException $retryError) {
                    $error = $retryError;
                }
            }

            if (isset($payload)) {
                $items = is_array($payload['data'] ?? null) ? array_values($payload['data']) : [];

                return [
                    'count' => (int) ($payload['count'] ?? count($items)),
                    'data' => $items,
                ];
            }

            Log::warning('No se pudo consultar un catalogo de bitacoras SIOP.', [
                'exception' => $error::class,
                'message' => $error->getMessage(),
                'catalog' => $catalog,
            ]);

            throw new MobileApiException(
                'No pudimos consultar los datos para crear la bitacora.',
                $error instanceof RequestException ? $error->response->status() : 503,
                'SIOP_BITACORA_CATALOG_UNAVAILABLE',
            );
        }

        $items = is_array($payload['data'] ?? null) ? array_values($payload['data']) : [];

        return [
            'count' => (int) ($payload['count'] ?? count($items)),
            'data' => $items,
        ];
    }

    private function fetchCatalog(string $url, string $token, int $timeout, bool $verifySsl): array
    {
        $response = Http::acceptJson()
            ->withToken($token)
            ->connectTimeout(30)
            ->timeout($timeout)
            ->retry(1, 250)
            ->withOptions(['verify' => $verifySsl])
            ->get($url)
            ->throw();

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio un catalogo que no pudimos leer.',
                502,
                'SIOP_BITACORA_CATALOG_INVALID_RESPONSE',
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
            'fecha' => trim((string) ($item['fecha'] ?? '')),
            'kilometraje_salida' => $item['kilometraje_salida'] ?? null,
            'kilometraje_llegada' => $item['kilometraje_llegada'] ?? null,
            'kilometraje_recorrido' => $item['kilometraje_recorrido'] ?? null,
            'recorrido_inicio' => trim((string) ($item['recorrido_inicio'] ?? '')),
            'recorrido_destino' => trim((string) ($item['recorrido_destino'] ?? '')),
            'abastecimiento_combustible' => (bool) ($item['abastecimiento_combustible'] ?? false),
            'activo' => (bool) ($item['activo'] ?? false),
            'cantidad_paquetes' => isset($item['cantidad_paquetes']) ? (int) $item['cantidad_paquetes'] : null,
            'session_reference' => trim((string) ($item['session_reference'] ?? '')),
            'driver' => [
                'id' => (int) ($driver['id'] ?? 0),
                'nombre' => trim((string) ($driver['nombre'] ?? '')),
                'telefono' => trim((string) ($driver['telefono'] ?? '')),
                'email' => trim((string) ($driver['email'] ?? '')),
            ],
            'vehicle' => [
                'id' => (int) ($vehicle['id'] ?? 0),
                'placa' => trim((string) ($vehicle['placa'] ?? '')),
                'marca' => trim((string) ($vehicle['marca'] ?? '')),
                'modelo' => trim((string) ($vehicle['modelo'] ?? '')),
                'color' => trim((string) ($vehicle['color'] ?? '')),
                'anio' => isset($vehicle['anio']) ? (int) $vehicle['anio'] : null,
            ],
        ];
    }
}
