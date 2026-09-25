<?php

namespace App\Services\Cartero;

use App\Exceptions\MobileApiException;
use App\Services\Autenticacion\MobileApiTokenService;
use App\Services\Seguimiento\SiopTrackingEventsService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

class SiopCourierPackagesService
{
    private const PAGE_SIZE = 100;

    private const MAX_PAGES = 100;

    public function __construct(
        private readonly MobileApiTokenService $mobileTokenService,
        private readonly SiopTrackingEventsService $trackingEventsService,
    ) {}

    public function assignedPackages(?string $mobileToken): array
    {
        $siopToken = $this->siopAccessToken($mobileToken);
        $url = $this->requiredConfig('assigned_url');
        $integrationToken = $this->requiredConfig('assigned_token');
        $records = [];

        for ($page = 1; $page <= self::MAX_PAGES; $page++) {
            $payload = $this->request(
                method: 'GET',
                url: $url,
                integrationToken: $integrationToken,
                siopToken: $siopToken,
                data: ['page' => $page, 'per_page' => self::PAGE_SIZE],
            );
            $pageRecords = $this->readRecords($payload);
            array_push($records, ...$pageRecords);

            if (! $this->hasNextPage($payload, $page, count($pageRecords))) {
                break;
            }
        }

        $assignments = [];
        foreach ($records as $record) {
            $normalized = $this->normalizeAssignedPackage($record);
            if ($normalized !== null) {
                $assignments[$normalized['code']] = $normalized;
            }
        }

        return [
            'total' => count($assignments),
            'assignments' => array_values($assignments),
        ];
    }

    public function assignPackages(?string $mobileToken, array $rawCodes): array
    {
        $codes = array_values(array_unique(array_filter(array_map(
            fn ($code): string => $this->normalizeCode((string) $code),
            $rawCodes,
        ))));
        if ($codes === []) {
            throw new MobileApiException(
                'Selecciona al menos un codigo de paquete.',
                422,
                'PACKAGE_CODES_REQUIRED',
            );
        }

        $currentlyAssigned = $this->assignedPackages($mobileToken);
        $assignedCodeSet = array_fill_keys(array_map(
            fn (array $assignment): string => $this->normalizeCode((string) ($assignment['code'] ?? '')),
            $currentlyAssigned['assignments'] ?? [],
        ), true);
        $pendingCodes = array_values(array_filter(
            $codes,
            fn (string $code): bool => ! isset($assignedCodeSet[$code]),
        ));

        if ($pendingCodes === []) {
            return [
                'assigned_count' => 0,
                'codes' => $codes,
                'message' => 'Los paquetes seleccionados ya estan asignados a tu cuenta.',
            ];
        }

        $items = [];
        $missingCodes = [];
        foreach ($pendingCodes as $code) {
            $package = $this->trackingEventsService->findPackageIdentityByCode($code);
            if ($package === null) {
                $missingCodes[] = $code;

                continue;
            }

            $items[] = [
                'id' => $package['id'],
                'tipo_paquete' => $package['type'],
            ];
        }

        if ($missingCodes !== []) {
            throw new MobileApiException(
                'No encontramos estos paquetes en SIOP: '.implode(', ', $missingCodes).'.',
                422,
                'SIOP_PACKAGES_NOT_FOUND',
            );
        }

        try {
            $payload = $this->request(
                method: 'POST',
                url: $this->requiredConfig('assign_url'),
                integrationToken: $this->requiredConfig('assign_token'),
                siopToken: $this->siopAccessToken($mobileToken),
                data: ['items' => $items],
            );
        } catch (MobileApiException $error) {
            // BOLIPOST can fail in post-assignment work (for example, an email)
            // after its database transaction has already committed. Confirm the
            // resulting state before telling the courier that the assignment
            // failed and risking a duplicate retry.
            $verifiedAsAssigned = $error->status() >= 409
                && $error->status() !== 401
                && $error->status() !== 403
                && $this->allCodesAreNowAssignedEventually($mobileToken, $pendingCodes);

            Log::warning('La API de asignacion SIOP devolvio un error.', [
                'status' => $error->status(),
                'error_code' => $error->errorCode(),
                'verified_as_assigned' => $verifiedAsAssigned,
                'package_count' => count($pendingCodes),
            ]);

            if ($verifiedAsAssigned) {
                return [
                    'assigned_count' => count($pendingCodes),
                    'codes' => $codes,
                    'message' => 'Paquetes asignados correctamente.',
                ];
            }

            throw $error;
        }

        return [
            'assigned_count' => (int) ($payload['asignados'] ?? $payload['assigned_count'] ?? count($pendingCodes)),
            'codes' => $codes,
            'message' => trim((string) ($payload['message'] ?? 'Paquetes asignados correctamente.')),
        ];
    }

    public function pickupContractPackages(array $rawShipments): array
    {
        $shipmentsByCode = [];
        foreach ($rawShipments as $rawShipment) {
            if (! is_array($rawShipment)) {
                continue;
            }

            $code = $this->normalizeCode((string) ($rawShipment['code'] ?? ''));
            $weight = round((float) ($rawShipment['weight'] ?? 0), 3);
            if ($code !== '' && $weight >= 0.001 && $weight <= 700) {
                $shipmentsByCode[$code] = $weight;
            }
        }
        if ($shipmentsByCode === []) {
            throw new MobileApiException(
                'Selecciona al menos un paquete con un peso valido.',
                422,
                'PACKAGE_SHIPMENTS_REQUIRED',
            );
        }
        $codes = array_keys($shipmentsByCode);
        $shipments = array_map(
            fn (string $code, float $weight): array => [
                'codigo' => $code,
                'peso' => $weight,
            ],
            $codes,
            array_values($shipmentsByCode),
        );

        try {
            $response = Http::acceptJson()
                ->asForm()
                ->withHeaders([
                    'X-API-Token' => $this->requiredConfig('contract_pickup_token'),
                ])
                ->connectTimeout(5)
                ->timeout(max(1, (int) config('services.siop_courier_packages.timeout', 20)))
                ->withOptions([
                    'verify' => (bool) config('services.siop_courier_packages.verify_ssl', true),
                ])
                ->post($this->requiredConfig('contract_pickup_url'), [
                    'envios' => $shipments,
                ]);
        } catch (ConnectionException) {
            throw new MobileApiException(
                'No pudimos comunicarnos con el servicio de recojo SIOP.',
                503,
                'SIOP_CONTRACT_PICKUP_UNAVAILABLE',
            );
        }

        if (! $response->successful()) {
            $this->throwForFailedResponse($response);
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio una respuesta de recojo no valida.',
                502,
                'SIOP_CONTRACT_PICKUP_INVALID_RESPONSE',
            );
        }

        $processedCodes = array_values(array_filter(array_map(
            fn ($code): string => $this->normalizeCode((string) $code),
            (array) ($payload['codigos'] ?? []),
        )));
        $unprocessedCodes = array_values(array_filter(array_map(
            fn ($code): string => $this->normalizeCode((string) $code),
            (array) ($payload['no_procesados'] ?? []),
        )));
        $pickedUpCount = (int) ($payload['actualizados'] ?? count($processedCodes));
        $message = trim((string) ($payload['message'] ?? ''));

        if ($pickedUpCount <= 0) {
            throw new MobileApiException(
                $message !== '' ? $message : 'No se pudo recoger ningun paquete.',
                422,
                'SIOP_CONTRACT_PICKUP_NOT_PROCESSED',
            );
        }

        return [
            'picked_up_count' => $pickedUpCount,
            'codes' => $processedCodes,
            'unprocessed_codes' => $unprocessedCodes,
            'message' => $message !== '' ? $message : 'Paquetes recogidos correctamente.',
        ];
    }

    public function deliverPackage(
        ?string $mobileToken,
        string $rawCode,
        string $description,
        string $receivedBy,
        Carbon $deliveredAt,
        UploadedFile $deliveryPhoto,
    ): array {
        $code = $this->normalizeCode($rawCode);
        if ($code === '') {
            throw new MobileApiException(
                'Debes seleccionar un paquete valido.',
                422,
                'PACKAGE_CODE_REQUIRED',
            );
        }

        $package = $this->trackingEventsService->findPackageIdentityByCode($code);
        if ($package === null) {
            throw new MobileApiException(
                "No encontramos el paquete {$code} en SIOP.",
                422,
                'SIOP_PACKAGE_NOT_FOUND',
            );
        }

        $effectiveDeliveredAt = $this->safeDeliveryMinute(
            $deliveredAt,
            (string) ($package['latest_event_at'] ?? ''),
        );

        $payload = $this->deliveryRequest(
            url: $this->requiredConfig('deliver_url'),
            integrationToken: $this->requiredConfig('deliver_token'),
            siopToken: $this->siopAccessToken($mobileToken),
            fields: [
                'id' => $package['id'],
                'tipo_paquete' => $package['type'],
                'descripcion' => trim($description),
                'recibido_por' => trim($receivedBy),
                // BoliPost usa el valor de un input HTML datetime-local.
                'fecha_entrega' => $effectiveDeliveredAt->format('Y-m-d\TH:i'),
            ],
            deliveryPhoto: $deliveryPhoto,
        );

        return [
            'delivered_count' => (int) ($payload['entregados'] ?? $payload['delivered_count'] ?? 1),
            'code' => $code,
            'message' => trim((string) ($payload['message'] ?? 'Paquete entregado correctamente.')),
        ];
    }

    private function safeDeliveryMinute(Carbon $requestedAt, string $rawLatestEventAt): Carbon
    {
        $timezone = (string) config('app.timezone', 'America/La_Paz');
        $effective = $requestedAt->copy()->setTimezone($timezone)->startOfMinute();
        if (trim($rawLatestEventAt) === '') {
            return $effective;
        }

        try {
            $latestEvent = Carbon::parse($rawLatestEventAt)->setTimezone($timezone);
        } catch (Throwable) {
            return $effective;
        }

        $earliestValidMinute = $latestEvent->copy()->startOfMinute();
        if ($latestEvent->second > 0 || $latestEvent->micro > 0) {
            $earliestValidMinute->addMinute();
        }

        return $effective->lessThan($earliestValidMinute)
            ? $earliestValidMinute
            : $effective;
    }

    private function deliveryRequest(
        string $url,
        string $integrationToken,
        string $siopToken,
        array $fields,
        UploadedFile $deliveryPhoto,
    ): array {
        try {
            $response = Http::acceptJson()
                ->withToken($siopToken)
                ->withHeaders(['X-API-Token' => $integrationToken])
                ->connectTimeout(5)
                ->timeout(max(1, (int) config('services.siop_courier_packages.deliver_timeout', 60)))
                ->withOptions([
                    'verify' => (bool) config('services.siop_courier_packages.verify_ssl', true),
                ])
                ->attach(
                    'foto',
                    $deliveryPhoto->get(),
                    $deliveryPhoto->getClientOriginalName(),
                    ['Content-Type' => $deliveryPhoto->getMimeType() ?: 'image/jpeg'],
                )
                ->post($url, $fields);
        } catch (ConnectionException) {
            Log::warning('No se pudo conectar con la API de entrega SIOP.');
            throw new MobileApiException(
                'No pudimos comunicarnos con el servicio de entrega SIOP.',
                503,
                'SIOP_DELIVERY_UNAVAILABLE',
            );
        }

        if (! $response->successful()) {
            Log::warning('La API de entrega SIOP rechazo la solicitud.', [
                'status' => $response->status(),
                'message' => trim((string) $response->json('message')),
                'error_fields' => array_keys((array) $response->json('errors', [])),
            ]);
            $this->throwForFailedResponse($response);
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio una respuesta de entrega no valida.',
                502,
                'SIOP_DELIVERY_INVALID_RESPONSE',
            );
        }

        return $payload;
    }

    private function request(
        string $method,
        string $url,
        string $integrationToken,
        string $siopToken,
        array $data,
    ): array {
        try {
            $request = Http::acceptJson()
                ->asJson()
                ->withToken($siopToken)
                ->withHeaders(['X-API-Token' => $integrationToken])
                ->connectTimeout(5)
                ->timeout(max(1, (int) config('services.siop_courier_packages.timeout', 20)))
                ->withOptions([
                    'verify' => (bool) config('services.siop_courier_packages.verify_ssl', true),
                ]);

            $response = $method === 'POST'
                ? $request->post($url, $data)
                : $request->get($url, $data);
        } catch (ConnectionException) {
            throw new MobileApiException(
                'No pudimos comunicarnos con el servicio de paquetes SIOP.',
                503,
                'SIOP_COURIER_PACKAGES_UNAVAILABLE',
            );
        }

        if (! $response->successful()) {
            $this->throwForFailedResponse($response);
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'SIOP devolvio una respuesta de paquetes no valida.',
                502,
                'SIOP_COURIER_PACKAGES_INVALID_RESPONSE',
            );
        }

        return $payload;
    }

    private function throwForFailedResponse(Response $response): never
    {
        $message = trim((string) $response->json('message'));
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
                'Tu cuenta SIOP necesita el rol cartero_ems o auxiliar urbano para usar esta funcion.',
                403,
                'SIOP_COURIER_PERMISSION_REQUIRED',
            );
        }

        if ($status === 422) {
            throw new MobileApiException(
                $message !== '' ? $message : 'Revisa los paquetes seleccionados.',
                422,
                'SIOP_PACKAGE_ASSIGNMENT_VALIDATION_ERROR',
            );
        }

        throw new MobileApiException(
            'No pudimos completar la operacion de paquetes en SIOP.',
            503,
            'SIOP_COURIER_PACKAGES_FAILED',
        );
    }

    private function siopAccessToken(?string $mobileToken): string
    {
        $payload = $this->mobileTokenService->getPayload($mobileToken);
        $token = trim((string) ($payload['siop_access_token'] ?? ''));
        if ($token === '') {
            throw new MobileApiException(
                'Tu sesion SIOP no esta disponible. Vuelve a iniciar sesion.',
                401,
                'SIOP_SESSION_REQUIRED',
            );
        }

        return $token;
    }

    private function requiredConfig(string $key): string
    {
        $value = trim((string) config("services.siop_courier_packages.{$key}"));
        if ($value === '') {
            throw new MobileApiException(
                'El servicio de paquetes SIOP no esta configurado.',
                503,
                'SIOP_COURIER_PACKAGES_NOT_CONFIGURED',
            );
        }

        return $value;
    }

    private function readRecords(array $payload): array
    {
        $records = $payload['data'] ?? $payload['paquetes'] ?? [];
        if (is_array($records) && isset($records['data']) && is_array($records['data'])) {
            $records = $records['data'];
        }

        return is_array($records) ? array_values($records) : [];
    }

    private function hasNextPage(array $payload, int $page, int $count): bool
    {
        $pagination = $payload['paginacion'] ?? $payload['meta'] ?? [];
        if (is_array($pagination)) {
            $lastPage = (int) ($pagination['ultima_pagina'] ?? $pagination['last_page'] ?? 0);
            if ($lastPage > 0) {
                return $page < $lastPage;
            }
        }

        return $count >= self::PAGE_SIZE;
    }

    private function normalizeAssignedPackage(mixed $rawRecord): ?array
    {
        if (! is_array($rawRecord)) {
            return null;
        }

        $package = is_array($rawRecord['paquete'] ?? null) ? $rawRecord['paquete'] : $rawRecord;
        $code = $this->normalizeCode((string) ($package['codigo'] ?? $rawRecord['codigo'] ?? ''));
        if ($code === '') {
            return null;
        }

        $state = $rawRecord['estado'] ?? $package['estado'] ?? '';
        if (is_array($state)) {
            $state = $state['nombre'] ?? $state['name'] ?? '';
        }

        $type = strtolower(trim((string) (
            $package['tipo_paquete']
            ?? $rawRecord['tipo_paquete']
            ?? $package['tipo']
            ?? $package['servicio']
            ?? 'ems'
        )));
        $recipient = is_array($rawRecord['destinatario'] ?? null)
            ? $rawRecord['destinatario']
            : (is_array($package['destinatario'] ?? null) ? $package['destinatario'] : []);
        $recipientName = is_string($rawRecord['destinatario'] ?? null)
            ? $rawRecord['destinatario']
            : ($recipient['nombre'] ?? $recipient['name'] ?? $package['nombre_destinatario'] ?? '');
        $recipientPhone = $rawRecord['telefono']
            ?? $rawRecord['telefono_destinatario']
            ?? $recipient['telefono']
            ?? $recipient['phone']
            ?? $package['telefono_destinatario']
            ?? '';
        $recipientAddress = $rawRecord['zona']
            ?? $rawRecord['direccion']
            ?? $rawRecord['direccion_destinatario']
            ?? $recipient['direccion']
            ?? $recipient['address']
            ?? $package['direccion_destinatario']
            ?? '';

        return [
            'assignment_id' => (int) ($rawRecord['id_asignacion'] ?? $rawRecord['asignacion_id'] ?? $rawRecord['id'] ?? $package['id'] ?? 0),
            'code' => $code,
            'package_type' => match ($type) {
                'certi', 'certificado' => 'certi',
                'contrato' => 'contrato',
                'ordi', 'ordinario' => 'ordi',
                'solicitud' => 'solicitud',
                default => 'ems',
            },
            'state_name' => trim((string) $state) ?: 'ASIGNADO',
            'created_at' => trim((string) ($rawRecord['fecha_asignacion'] ?? $rawRecord['created_at'] ?? $rawRecord['fecha'] ?? '')),
            'recipient_name' => trim((string) $recipientName),
            'recipient_phone' => trim((string) $recipientPhone),
            'recipient_address' => trim((string) $recipientAddress),
        ];
    }

    private function normalizeCode(string $rawCode): string
    {
        return strtoupper(trim(preg_replace('/[^A-Z0-9]+/i', '', $rawCode) ?? ''));
    }

    private function allCodesAreNowAssigned(?string $mobileToken, array $codes): bool
    {
        try {
            $assigned = $this->assignedPackages($mobileToken);
        } catch (MobileApiException) {
            return false;
        }

        $assignedCodes = array_fill_keys(array_map(
            fn (array $assignment): string => $this->normalizeCode((string) ($assignment['code'] ?? '')),
            $assigned['assignments'] ?? [],
        ), true);

        foreach ($codes as $code) {
            if (! isset($assignedCodes[$code])) {
                return false;
            }
        }

        return true;
    }

    private function allCodesAreNowAssignedEventually(?string $mobileToken, array $codes): bool
    {
        foreach ([0, 250000, 750000, 1500000] as $delayMicroseconds) {
            if ($delayMicroseconds > 0) {
                usleep($delayMicroseconds);
            }

            if ($this->allCodesAreNowAssigned($mobileToken, $codes)) {
                return true;
            }
        }

        return false;
    }
}
