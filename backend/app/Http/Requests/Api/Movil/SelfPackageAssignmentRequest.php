<?php

namespace App\Http\Requests\Api\Movil;

class SelfPackageAssignmentRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'codes' => ['required', 'array', 'min:1', 'max:100'],
            'codes.*' => ['required', 'string', 'max:80', 'distinct'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $codes = array_values(array_unique(array_filter(array_map(
            fn ($code): string => strtoupper(trim(preg_replace('/[^A-Z0-9]+/i', '', (string) $code) ?? '')),
            (array) $this->input('codes', []),
        ))));

        $this->merge(['codes' => $codes]);
    }

    protected function validationMessage(): string
    {
        return 'Selecciona al menos un codigo de paquete valido.';
    }
}
