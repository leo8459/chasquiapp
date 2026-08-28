<?php

namespace App\Http\Requests\Api\Movil;

class MobileAssignmentDeliveryStoreRequest extends BaseMobileApiRequest
{
    private const RECEIVED_BY_PATTERN =
        '/^([A-ZÁÉÍÓÚÑ][a-záéíóúñ]+(?:[-\s][A-ZÁÉÍÓÚÑ][a-záéíóúñ]+)*)$/u';

    private const RECEIVED_BY_VOWEL_PATTERN = '/[AEIOUÁÉÍÓÚaeiouáéíóú]/u';

    public function rules(): array
    {
        return [
            'user_id' => ['required', 'integer', 'min:1'],
            'received_by' => [
                'required',
                'string',
                'min:3',
                'max:120',
                'regex:'.self::RECEIVED_BY_PATTERN,
                function (string $attribute, mixed $value, \Closure $fail): void {
                    // Evita iniciales sueltas o textos sin forma de nombre real.
                    $parts = preg_split('/[\s-]+/u', (string) $value) ?: [];
                    foreach ($parts as $part) {
                        if ($part === '') {
                            continue;
                        }

                        if (mb_strlen($part, 'UTF-8') < 2) {
                            $fail('Cada nombre o apellido debe tener al menos 2 letras completas.');

                            return;
                        }

                        if (! preg_match(self::RECEIVED_BY_VOWEL_PATTERN, $part)) {
                            $fail('Revisa el nombre ingresado. No uses abreviaturas ni bloques de consonantes.');

                            return;
                        }
                    }
                },
            ],
            'delivery_photo' => ['required', 'file', 'image', 'max:16384'],
            'delivery_signature' => ['required', 'file', 'image', 'max:8192'],
        ];
    }

    protected function prepareForValidation(): void
    {
        // Normaliza el payload antes de aplicar reglas para evitar falsos errores.
        $this->merge([
            'received_by' => $this->normalizeReceivedBy((string) $this->input('received_by')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Completa quien recibio el paquete, el usuario del cartero, la foto del comprobante y la firma de entrega.';
    }

    private function normalizeReceivedBy(string $rawValue): string
    {
        // Convierte "juan   perez" o "juan - perez" en un nombre legible.
        $normalized = preg_replace('/\s*-\s*/u', '-', $rawValue) ?? '';
        $normalized = preg_replace('/\s+/u', ' ', $normalized) ?? '';
        $normalized = trim($normalized);
        if ($normalized === '') {
            return '';
        }

        $words = preg_split('/\s+/u', $normalized) ?: [];
        $normalizedWords = array_map(function (string $word): string {
            $parts = preg_split('/-/u', $word) ?: [];
            $normalizedParts = array_map(function (string $part): string {
                $lower = mb_strtolower(trim($part), 'UTF-8');
                if ($lower === '') {
                    return '';
                }

                return mb_strtoupper(mb_substr($lower, 0, 1, 'UTF-8'), 'UTF-8')
                    .mb_substr($lower, 1, null, 'UTF-8');
            }, $parts);

            return implode('-', array_values(array_filter($normalizedParts, static fn (string $part): bool => $part !== '')));
        }, $words);

        return implode(' ', array_values(array_filter($normalizedWords, static fn (string $word): bool => $word !== '')));
    }
}
