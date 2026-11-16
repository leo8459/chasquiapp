<?php

namespace App\Services\Gestion;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\RequestException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class SiopTransportInvoiceService
{
    public function create(array $data, UploadedFile $invoice): array
    {
        $url = trim((string) config('services.siop_facturas_transporte.url'));
        $token = trim((string) config('services.siop_facturas_transporte.token'));
        $timeout = max(1, (int) config('services.siop_facturas_transporte.timeout', 45));
        $verifySsl = (bool) config('services.siop_facturas_transporte.verify_ssl', true);

        if ($url === '' || $token === '') {
            throw new MobileApiException(
                'La integración de facturas de transporte con BoliPost no está configurada.',
                503,
                'BOLIPOST_TRANSPORT_INVOICE_NOT_CONFIGURED',
            );
        }

        try {
            $response = Http::acceptJson()
                ->withToken($token)
                ->connectTimeout(min(5, $timeout))
                ->timeout(max(60, $timeout))
                ->withOptions(['verify' => $verifySsl])
                ->attach(
                    'imagen_factura',
                    $invoice->getContent(),
                    $invoice->getClientOriginalName(),
                    ['Content-Type' => $invoice->getMimeType() ?: 'image/jpeg'],
                )
                ->post($url, $data)
                ->throw();
        } catch (RequestException $error) {
            $payload = $error->response->json();
            $message = is_array($payload)
                ? trim((string) ($payload['message'] ?? ''))
                : '';
            $status = $error->response->status();

            if (in_array($status, [401, 403], true)) {
                $message = 'BoliPost no autorizó la integración de facturas de transporte.';
                $status = 503;
            }

            throw new MobileApiException(
                $message !== '' ? $message : 'BoliPost rechazó los datos de la factura de transporte.',
                $status,
                'BOLIPOST_TRANSPORT_INVOICE_REJECTED',
            );
        } catch (ConnectionException $error) {
            Log::warning('No se pudo registrar la factura de transporte en BoliPost.', [
                'exception' => $error::class,
                'message' => $error->getMessage(),
            ]);

            throw new MobileApiException(
                'No pudimos comunicarnos con BoliPost para registrar la factura.',
                503,
                'BOLIPOST_TRANSPORT_INVOICE_UNAVAILABLE',
            );
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            throw new MobileApiException(
                'BoliPost registró la solicitud, pero devolvió una respuesta inesperada.',
                502,
                'BOLIPOST_TRANSPORT_INVOICE_INVALID_RESPONSE',
            );
        }

        return [
            'message' => trim((string) ($payload['message'] ?? 'Factura de transporte registrada correctamente.')),
            'factura_transporte' => is_array($payload['data'] ?? null) ? $payload['data'] : null,
        ];
    }
}
