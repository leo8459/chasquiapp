<?php

namespace App\Services\Gestion;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SiopMantenimientoService
{
    public function list(int $page = 1, int $perPage = 20): array
    {
        $payload = $this->get('', ['page' => $page, 'per_page' => $perPage]);
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

    public function options(): array
    {
        $vehicles = $this->get('/vehiculos');
        $types = $this->get('/tipos');

        return [
            'vehicles' => array_values(array_filter(array_map(
                fn (mixed $item): ?array => is_array($item) ? $this->normalizeVehicle($item) : null,
                is_array($vehicles['data'] ?? null) ? $vehicles['data'] : [],
            ))),
            'maintenance_types' => array_values(array_filter(array_map(
                fn (mixed $item): ?array => is_array($item) ? $this->normalizeType($item) : null,
                is_array($types['data'] ?? null) ? $types['data'] : [],
            ))),
        ];
    }

    public function create(array $data): array
    {
        [$url, $token, $timeout, $verifySsl] = $this->configuration();

        try {
            $response = Http::acceptJson()
                ->withToken($token)
                ->connectTimeout(30)
                ->timeout($timeout)
                ->withOptions(['verify' => $verifySsl])
                ->post($url, $data)
                ->throw();
        } catch (RequestException $error) {
            $payload = $error->response->json();
            $message = is_array($payload) ? trim((string) ($payload['message'] ?? '')) : '';
            throw new MobileApiException(
                $message !== '' ? $message : 'SIOP rechazo la solicitud de mantenimiento.',
                $error->response->status(),
                'SIOP_MANTENIMIENTO_CREATE_REJECTED',
            );
        } catch (ConnectionException $error) {
            Log::warning('No se pudo crear el mantenimiento SIOP.', ['message' => $error->getMessage()]);
            throw new MobileApiException(
                'No pudimos crear la solicitud de mantenimiento en este momento.',
                503,
                'SIOP_MANTENIMIENTO_CREATE_UNAVAILABLE',
            );
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException('SIOP devolvio una respuesta inesperada.', 502, 'SIOP_MANTENIMIENTO_INVALID_RESPONSE');
        }

        $raw = $payload['data'] ?? $payload['mantenimiento'] ?? null;

        return [
            'message' => trim((string) ($payload['message'] ?? 'Solicitud de mantenimiento creada correctamente.')),
            'mantenimiento' => is_array($raw) ? $this->normalizeItem($raw) : null,
        ];
    }

    private function get(string $suffix, array $query = []): array
    {
        [$url, $token, $timeout, $verifySsl] = $this->configuration();

        try {
            $response = Http::acceptJson()
                ->withToken($token)
                ->connectTimeout(30)
                ->timeout($timeout)
                ->retry(1, 250)
                ->withOptions(['verify' => $verifySsl])
                ->get($url.$suffix, $query)
                ->throw();
        } catch (ConnectionException|RequestException $error) {
            Log::warning('No se pudo consultar mantenimientos SIOP.', ['message' => $error->getMessage()]);
            throw new MobileApiException(
                'No pudimos consultar los mantenimientos en este momento.',
                503,
                'SIOP_MANTENIMIENTOS_UNAVAILABLE',
            );
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException('SIOP devolvio una respuesta que no pudimos leer.', 502, 'SIOP_MANTENIMIENTOS_INVALID_RESPONSE');
        }

        return $payload;
    }

    private function configuration(): array
    {
        $url = rtrim(trim((string) config('services.siop_mantenimientos.url')), '/');
        $token = trim((string) config('services.siop_mantenimientos.token'));
        $timeout = max(30, (int) config('services.siop_mantenimientos.timeout', 30));
        $verifySsl = (bool) config('services.siop_mantenimientos.verify_ssl', true);

        if ($url === '' || $token === '') {
            throw new MobileApiException('El servicio de mantenimientos no esta configurado.', 503, 'SIOP_MANTENIMIENTOS_NOT_CONFIGURED');
        }

        return [$url, $token, $timeout, $verifySsl];
    }

    private function normalizeItem(array $item): array
    {
        $vehicle = is_array($item['vehicle'] ?? null) ? $item['vehicle'] : [];
        $type = is_array($item['maintenance_type'] ?? null) ? $item['maintenance_type'] : [];

        return [
            'id' => (int) ($item['id'] ?? 0),
            'vehicle_id' => (int) ($item['vehicle_id'] ?? $vehicle['id'] ?? 0),
            'vehicle_plate' => trim((string) ($item['vehicle_plate'] ?? $item['placa'] ?? $vehicle['placa'] ?? '')),
            'vehicle_name' => trim((string) ($item['vehicle_name'] ?? $vehicle['vehicle_class'] ?? $vehicle['marca'] ?? '')),
            'maintenance_type_id' => (int) ($item['maintenance_type_id'] ?? $type['id'] ?? 0),
            'maintenance_type' => trim((string) (
                is_scalar($item['maintenance_type'] ?? null)
                    ? $item['maintenance_type']
                    : ($item['tipo_mantenimiento'] ?? $type['nombre'] ?? '')
            )),
            'scheduled_at' => trim((string) ($item['fecha_programada'] ?? $item['scheduled_at'] ?? '')),
            'status' => trim((string) ($item['estado'] ?? $item['status'] ?? '')),
            'description' => trim((string) ($item['descripcion'] ?? $item['observaciones'] ?? '')),
            'created_at' => trim((string) ($item['created_at'] ?? '')),
        ];
    }

    private function normalizeVehicle(array $item): array
    {
        return [
            'id' => (int) ($item['id'] ?? 0),
            'plate' => trim((string) ($item['placa'] ?? '')),
            'name' => trim((string) ($item['vehicle_class'] ?? $item['marca'] ?? '')),
            'available' => (bool) ($item['disponible_para_mantenimiento'] ?? true),
        ];
    }

    private function normalizeType(array $item): array
    {
        return [
            'id' => (int) ($item['id'] ?? 0),
            'name' => trim((string) ($item['nombre'] ?? '')),
            'category' => trim((string) ($item['categoria_label'] ?? $item['categoria'] ?? '')),
            'description' => trim((string) ($item['descripcion'] ?? '')),
        ];
    }
}
