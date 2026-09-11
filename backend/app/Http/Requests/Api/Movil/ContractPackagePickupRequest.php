<?php

namespace App\Http\Requests\Api\Movil;

class ContractPackagePickupRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'shipments' => ['required', 'array', 'min:1', 'max:100'],
            'shipments.*.code' => ['required', 'string', 'max:80', 'distinct:ignore_case'],
            'shipments.*.weight' => ['required', 'numeric', 'min:0.001', 'max:700'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $shipments = collect((array) $this->input('shipments', []))
            ->filter(fn ($shipment): bool => is_array($shipment))
            ->map(function (array $shipment): array {
                $code = strtoupper(trim(preg_replace(
                    '/[^A-Z0-9]+/i',
                    '',
                    (string) ($shipment['code'] ?? ''),
                ) ?? ''));
                $rawWeight = str_replace(',', '.', trim((string) ($shipment['weight'] ?? '')));

                return [
                    'code' => $code,
                    'weight' => is_numeric($rawWeight) ? (float) $rawWeight : $rawWeight,
                ];
            })
            ->values()
            ->all();

        $this->merge(['shipments' => $shipments]);
    }

    protected function validationMessage(): string
    {
        return 'Cada paquete debe tener un codigo valido y un peso entre 0,001 y 700,000 kg.';
    }
}
