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
        $events = $this->normalizeEvents($payload['data'] ?? []);

        return [
            'filtro' => [
                'codigo' => $code,
                'tabla' => $normalizedTable,
                'exacto' => (bool) ($payload['filtro']['exacto'] ?? true),
                'limit' => $normalizedLimit,
            ],
            'total' => (int) ($payload['total'] ?? count($events)),
            'data' => $events,
        ];
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
            'limit' => $limit,
        ];
        if ($table !== null) {
            $query['tabla'] = $table;
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
                'user_id' => (int) ($rawEvent['user_id'] ?? 0),
                'usuario' => trim((string) ($rawEvent['usuario'] ?? '')),
                'created_at' => trim((string) ($rawEvent['created_at'] ?? '')),
                'foto' => trim((string) ($rawEvent['foto'] ?? '')),
            ];
        }

        return $events;
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
