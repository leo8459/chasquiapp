<?php

namespace App\Services\Seguimiento;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SiopTrackingEventsService
{
    private const DEFAULT_LIMIT = 30;

    public function findByCode(string $rawCode, ?string $table = null, int $limit = self::DEFAULT_LIMIT): array
    {
        $code = $this->normalizeCode($rawCode);
        if ($code === '') {
            throw new MobileApiException(
                'Debes enviar un codigo valido para consultar eventos.',
                422,
                'TRACKING_EVENTS_CODE_REQUIRED',
            );
        }

        $normalizedTable = $this->normalizeTable($table);
        $normalizedLimit = max(1, min(50, $limit));

        $payload = $this->requestEvents($code, $normalizedTable, $normalizedLimit);
        $normalized = $this->normalizePackageEvents(
            $payload['data'] ?? [],
            $code,
            $normalizedLimit,
        );
        $events = $normalized['events'];

        return [
            'filtro' => [
                'codigo' => $code,
                'tabla' => $normalized['table'] ?? $normalizedTable,
                'exacto' => $normalized['exact'],
                'limit' => $normalizedLimit,
            ],
            'total' => $normalized['total'],
            'data' => $events,
        ];
    }

    /**
     * Resolve the internal SIOP package identity required by the courier
     * assignment endpoint while keeping that implementation detail out of
     * the mobile client.
     *
     * @return array{id: int, code: string, type: string}|null
     */
    public function findPackageIdentityByCode(string $rawCode): ?array
    {
        $code = $this->normalizeCode($rawCode);
        if ($code === '') {
            return null;
        }

        $package = $this->findRawPackageByCode($code);
        if ($package === null) {
            return null;
        }

        $packageId = (int) ($package['id'] ?? 0);
        $packageType = $this->assignmentTypeForApiType(
            strtolower(trim((string) ($package['tipo'] ?? ''))),
        );
        if ($packageId <= 0 || $packageType === null) {
            return null;
        }

        return [
            'id' => $packageId,
            'code' => $code,
            'type' => $packageType,
        ];
    }

    /**
     * Return the package detail contract consumed by the mobile search view.
     * All fields come from the external SIOP API; no local database is used.
     */
    public function findPackageByCode(string $rawCode): array
    {
        $code = $this->normalizeCode($rawCode);
        if ($code === '') {
            return ['found' => false, 'code' => ''];
        }

        $package = $this->findRawPackageByCode($code);
        if ($package === null) {
            return ['found' => false, 'code' => $code];
        }

        $recipient = is_array($package['destinatario'] ?? null)
            ? $package['destinatario']
            : [];
        $state = is_array($package['estado'] ?? null)
            ? $package['estado']
            : [];
        $type = strtolower(trim((string) ($package['tipo'] ?? 'ems')));

        return [
            'found' => true,
            'code' => $code,
            'package_id' => (int) ($package['id'] ?? 0),
            'package_type' => match ($type) {
                'certificado' => 'certi',
                'ordinario' => 'ordi',
                // The current mobile domain has no separate solicitud category.
                'solicitud' => 'ems',
                default => $type,
            },
            'highlight_location' => trim((string) (
                $recipient['direccion']
                ?? $package['direccion_destinatario']
                ?? $package['direccion']
                ?? $package['zona']
                ?? ''
            )),
            'location_note' => '',
            'city' => trim((string) ($package['destino'] ?? $package['ciudad'] ?? '')),
            'province' => trim((string) ($package['provincia'] ?? '')),
            'recipient_name' => trim((string) (
                $recipient['nombre']
                ?? $package['nombre_destinatario']
                ?? (is_string($package['destinatario'] ?? null) ? $package['destinatario'] : '')
            )),
            'phone' => trim((string) (
                $recipient['telefono']
                ?? $package['telefono_destinatario']
                ?? $package['telefono']
                ?? ''
            )),
            'weight' => trim((string) ($package['peso'] ?? '')),
            'detail' => trim((string) ($package['contenido'] ?? $package['descripcion'] ?? strtoupper($type))),
            'state_name' => trim((string) ($state['nombre'] ?? $state['name'] ?? $package['estado'] ?? '')),
            'attempt_count' => (int) ($package['intento'] ?? 0),
            'assigned_courier_name' => trim((string) ($package['asignado_a'] ?? '')),
        ];
    }

    private function findRawPackageByCode(string $code): ?array
    {
        $payload = $this->requestEvents($code, null, 1);
        $packages = $payload['data'] ?? [];
        if (! is_array($packages)) {
            return null;
        }

        foreach ($packages as $package) {
            if (! is_array($package)) {
                continue;
            }

            if ($this->normalizeCode((string) ($package['codigo'] ?? '')) === $code) {
                return $package;
            }
        }

        return null;
    }

    private function requestEvents(string $code, ?string $table, int $limit): array
    {
        $url = trim((string) config('services.siop_tracking_events.url'));
        $token = trim((string) config('services.siop_tracking_events.token'));
        $timeout = max(1, (int) config('services.siop_tracking_events.timeout', 12));
        $verifySsl = (bool) config('services.siop_tracking_events.verify_ssl', true);

        if ($url === '' || $token === '') {
            throw new MobileApiException(
                'El servicio de eventos SIOP no esta configurado.',
                503,
                'SIOP_TRACKING_EVENTS_NOT_CONFIGURED',
            );
        }

        $query = [
            'codigo' => $code,
            'per_page' => min(50, $limit),
        ];
        if ($table !== null) {
            $query['tipo'] = $this->apiTypeForTable($table);
        }

        try {
            return $this->fetchEventsPayload($url, $token, $query, $timeout, $verifySsl);
        } catch (ConnectionException|RequestException $error) {
            if ($verifySsl) {
                try {
                    return $this->fetchEventsPayload($url, $token, $query, $timeout, false);
                } catch (ConnectionException|RequestException $retryError) {
                    $error = $retryError;
                }
            }

            Log::warning('No se pudo consultar eventos SIOP.', [
                'exception' => $error::class,
                'message' => $error->getMessage(),
                'codigo' => $code,
                'tabla' => $table,
                'verify_ssl' => $verifySsl,
            ]);

            throw new MobileApiException(
                'No pudimos consultar los eventos SIOP en este momento.',
                503,
                'SIOP_TRACKING_EVENTS_UNAVAILABLE',
            );
        }
    }

    /**
     * @param  array<string, int|string>  $query
     * @return array<string, mixed>
     *
     * @throws ConnectionException
     * @throws RequestException
     */
    private function fetchEventsPayload(string $url, string $token, array $query, int $timeout, bool $verifySsl): array
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
                'SIOP devolvio una respuesta que no pudimos leer.',
                502,
                'SIOP_TRACKING_EVENTS_INVALID_RESPONSE',
            );
        }

        return $payload;
    }

    private function normalizeEvents(mixed $rawEvents): array
    {
        if (! is_array($rawEvents)) {
            return [];
        }

        $events = [];
        foreach ($rawEvents as $rawEvent) {
            if (! is_array($rawEvent)) {
                continue;
            }

            $event = trim((string) ($rawEvent['evento'] ?? ''));
            $code = $this->normalizeCode((string) ($rawEvent['codigo'] ?? ''));
            if ($event === '' || $code === '') {
                continue;
            }

            $events[] = [
                'tabla' => trim((string) ($rawEvent['tabla'] ?? '')),
                'servicio' => trim((string) ($rawEvent['servicio'] ?? '')),
                'id' => (int) ($rawEvent['id'] ?? 0),
                'codigo' => $code,
                'evento_id' => (int) ($rawEvent['evento_id'] ?? 0),
                'evento' => $event,
                'detalle' => trim((string) ($rawEvent['detalle'] ?? '')),
                'user_id' => (int) ($rawEvent['user_id'] ?? 0),
                'usuario' => trim((string) ($rawEvent['usuario'] ?? '')),
                'created_at' => trim((string) ($rawEvent['created_at'] ?? '')),
                'foto' => trim((string) ($rawEvent['foto'] ?? '')),
            ];
        }

        return $events;
    }

    private function normalizePackageEvents(mixed $rawPackages, string $code, int $limit): array
    {
        if (! is_array($rawPackages)) {
            return [
                'events' => [],
                'total' => 0,
                'table' => null,
                'exact' => false,
            ];
        }

        // Compatibilidad con la respuesta plana utilizada por la API anterior.
        $first = $rawPackages[0] ?? null;
        if (is_array($first) && ! array_key_exists('eventos', $first)) {
            $events = array_values(array_filter(
                $this->normalizeEvents($rawPackages),
                fn (array $event): bool => $event['codigo'] === $code,
            ));

            return [
                'events' => array_slice($events, 0, $limit),
                'total' => count($events),
                'table' => $events[0]['tabla'] ?? null,
                'exact' => $events !== [],
            ];
        }

        $events = [];
        $table = null;
        $exact = false;

        foreach ($rawPackages as $rawPackage) {
            if (! is_array($rawPackage)) {
                continue;
            }

            $packageCode = $this->normalizeCode((string) ($rawPackage['codigo'] ?? ''));
            if ($packageCode !== $code) {
                continue;
            }

            $exact = true;
            $type = strtolower(trim((string) ($rawPackage['tipo'] ?? '')));
            $table ??= $this->tableForApiType($type);
            $service = $this->serviceLabelForApiType($type);
            $rawEvents = $rawPackage['eventos'] ?? [];
            if (! is_array($rawEvents)) {
                continue;
            }

            foreach ($rawEvents as $rawEvent) {
                if (! is_array($rawEvent)) {
                    continue;
                }

                $eventName = trim((string) ($rawEvent['nombre'] ?? $rawEvent['evento'] ?? ''));
                if ($eventName === '') {
                    continue;
                }

                $user = is_array($rawEvent['usuario'] ?? null) ? $rawEvent['usuario'] : [];
                $events[] = [
                    'tabla' => $table,
                    'servicio' => $service,
                    'id' => (int) ($rawEvent['id'] ?? 0),
                    'codigo' => $packageCode,
                    'evento_id' => (int) ($rawEvent['evento_id'] ?? 0),
                    'evento' => $eventName,
                    'detalle' => trim((string) ($rawEvent['detalle'] ?? '')),
                    'user_id' => (int) ($user['id'] ?? 0),
                    'usuario' => trim((string) ($user['nombre'] ?? '')),
                    'created_at' => trim((string) ($rawEvent['fecha'] ?? '')),
                    'foto' => '',
                ];
            }
        }

        return [
            'events' => array_slice($events, 0, $limit),
            'total' => count($events),
            'table' => $table,
            'exact' => $exact,
        ];
    }

    private function apiTypeForTable(string $table): string
    {
        return match ($table) {
            'eventos_certi' => 'certi',
            'eventos_contrato' => 'contrato',
            'eventos_ordi' => 'ordinario',
            default => 'ems',
        };
    }

    private function tableForApiType(string $type): string
    {
        return match ($type) {
            'certi' => 'eventos_certi',
            'contrato' => 'eventos_contrato',
            'ordinario' => 'eventos_ordi',
            'solicitud' => 'eventos_solicitud',
            default => 'eventos_ems',
        };
    }

    private function serviceLabelForApiType(string $type): string
    {
        return match ($type) {
            'certi' => 'Certificado',
            'contrato' => 'Contrato',
            'ordinario' => 'Ordinario',
            'solicitud' => 'Solicitud',
            default => 'EMS',
        };
    }

    private function assignmentTypeForApiType(string $type): ?string
    {
        return match ($type) {
            'ems' => 'EMS',
            'certi' => 'CERTI',
            'contrato' => 'CONTRATO',
            'ordinario', 'ordi' => 'ORDI',
            'solicitud' => 'SOLICITUD',
            default => null,
        };
    }

    private function normalizeCode(string $rawCode): string
    {
        $withoutSpaces = preg_replace('/[^A-Z0-9]+/i', '', $rawCode) ?? '';

        return strtoupper(trim($withoutSpaces));
    }

    private function normalizeTable(?string $table): ?string
    {
        $normalized = strtolower(trim((string) $table));
        if ($normalized === '') {
            return null;
        }

        return in_array($normalized, [
            'eventos_ems',
            'eventos_certi',
            'eventos_contrato',
            'eventos_ordi',
        ], true) ? $normalized : null;
    }
}
