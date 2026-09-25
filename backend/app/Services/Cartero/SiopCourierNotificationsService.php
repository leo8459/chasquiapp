<?php

namespace App\Services\Cartero;

use App\Exceptions\MobileApiException;
use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SiopCourierNotificationsService
{
    public function __construct(
        private readonly MobileApiTokenService $mobileTokenService,
        private readonly SiopCourierPackagesService $courierPackagesService,
    ) {}

    public function pending(?string $mobileToken): array
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

        $url = trim((string) config('services.siop_courier_notifications.pending_url'));
        $integrationToken = trim((string) config('services.siop_courier_notifications.token'));
        if ($url === '' || $integrationToken === '') {
            throw new MobileApiException(
                'El servicio de notificaciones SIOP no esta configurado.',
                503,
                'SIOP_COURIER_NOTIFICATIONS_NOT_CONFIGURED',
            );
        }

        try {
            $response = Http::acceptJson()
                ->withToken($siopToken)
                ->withHeaders(['X-API-Token' => $integrationToken])
                ->connectTimeout(5)
                ->timeout(max(1, (int) config('services.siop_courier_notifications.timeout', 20)))
                ->withOptions([
                    'verify' => (bool) config('services.siop_courier_notifications.verify_ssl', true),
                ])
                ->get($url);
        } catch (ConnectionException) {
            throw new MobileApiException(
                'No pudimos consultar las notificaciones de BoliPost.',
                503,
                'SIOP_COURIER_NOTIFICATIONS_UNAVAILABLE',
            );
        }

        if (! $response->successful()) {
            $this->throwForFailedResponse($response);
        }

        $body = $response->json();
        if (! is_array($body)) {
            throw new MobileApiException(
                'BoliPost devolvio notificaciones en un formato no valido.',
                502,
                'SIOP_COURIER_NOTIFICATIONS_INVALID_RESPONSE',
            );
        }

        $records = $this->readRecords($body);
        Log::info('BoliPost pending courier notifications fetched.', [
            'pending_count' => count($records),
        ]);

        if ($records === []) {
            $assigned = $this->courierPackagesService->assignedPackages($mobileToken);
            $records = array_map(
                fn (array $assignment): array => [
                    'id' => 'assigned-'.($assignment['assignment_id'] ?? $assignment['code'] ?? ''),
                    'titulo' => 'Paquete asignado',
                    'mensaje' => 'Tienes asignado el paquete '.($assignment['code'] ?? '').'.',
                    'codigo_paquete' => $assignment['code'] ?? '',
                    'fecha' => $assignment['assigned_at'] ?? '',
                ],
                $assigned['assignments'] ?? [],
            );
            Log::info('Courier notification fallback loaded assigned packages.', [
                'assigned_count' => count($records),
            ]);
        }

        $notifications = [];
        foreach ($records as $index => $record) {
            $normalized = $this->normalize($record, $index);
            if ($normalized !== null) {
                $notifications[] = $normalized;
            }
        }

        return [
            'total' => count($notifications),
            'notifications' => $notifications,
        ];
    }

    private function readRecords(array $payload): array
    {
        if (array_is_list($payload)) {
            return array_values($payload);
        }

        $records = $payload['data']
            ?? $payload['notificaciones']
            ?? $payload['notificaciones_pendientes']
            ?? $payload['notifications']
            ?? [];
        if (is_array($records) && isset($records['data']) && is_array($records['data'])) {
            $records = $records['data'];
        }

        return is_array($records) ? array_values($records) : [];
    }

    private function normalize(mixed $raw, int $index): ?array
    {
        if (! is_array($raw)) {
            return null;
        }

        $package = is_array($raw['paquete'] ?? null) ? $raw['paquete'] : [];
        $code = trim((string) (
            $raw['codigo_paquete'] ?? $raw['codigo'] ?? $package['codigo'] ?? ''
        ));
        $title = trim((string) ($raw['titulo'] ?? $raw['title'] ?? 'Nuevo paquete asignado'));
        $message = trim((string) (
            $raw['mensaje'] ?? $raw['message'] ?? $raw['descripcion'] ?? ''
        ));
        if ($message === '') {
            $message = $code !== ''
                ? "El paquete {$code} fue asignado a tu cuenta."
                : 'Tienes una nueva asignacion pendiente.';
        }

        $id = trim((string) (
            $raw['id'] ?? $raw['notificacion_id'] ?? $raw['id_notificacion'] ?? ''
        ));
        if ($id === '') {
            $id = hash('sha256', json_encode([$code, $message, $raw['created_at'] ?? $raw['fecha'] ?? $index]));
        }

        return [
            'id' => $id,
            'title' => $title,
            'message' => $message,
            'package_code' => $code,
            'created_at' => trim((string) ($raw['created_at'] ?? $raw['fecha'] ?? $raw['fecha_creacion'] ?? '')),
        ];
    }

    private function throwForFailedResponse(Response $response): never
    {
        $status = $response->status();
        if ($status === 401) {
            throw new MobileApiException(
                'Tu sesion SIOP vencio. Vuelve a iniciar sesion.',
                401,
                'SIOP_SESSION_EXPIRED',
            );
        }
        if ($status === 403) {
            throw new MobileApiException(
                'Tu cuenta no tiene permiso para consultar notificaciones de cartero.',
                403,
                'SIOP_COURIER_NOTIFICATION_PERMISSION_REQUIRED',
            );
        }

        throw new MobileApiException(
            'No pudimos consultar las notificaciones de BoliPost.',
            503,
            'SIOP_COURIER_NOTIFICATIONS_FAILED',
        );
    }
}
