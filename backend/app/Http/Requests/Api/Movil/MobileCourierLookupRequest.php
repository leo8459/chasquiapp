<?php

namespace App\Http\Requests\Api\Movil;

class MobileCourierLookupRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'ci' => ['required', 'string', 'max:20'],
        ];
    }

    protected function prepareForValidation(): void
    {
        // CI operativo: solo letras y numeros, sin espacios ni guiones.
        $normalizedCi = preg_replace('/[^A-Z0-9]/i', '', (string) $this->input('ci')) ?? '';

        $this->merge([
            'ci' => strtoupper(trim($normalizedCi)),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar un CI valido.';
    }
}
