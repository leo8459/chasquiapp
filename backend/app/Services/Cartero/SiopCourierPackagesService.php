<?php

namespace App\Services\Cartero;

use App\Exceptions\MobileApiException;
use App\Services\Autenticacion\MobileApiTokenService;
use App\Services\Seguimiento\SiopTrackingEventsService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;

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
            if ($error->status() >= 500 && $this->allCodesAreNowAssigned($mobileToken, $pendingCodes)) {
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
}
