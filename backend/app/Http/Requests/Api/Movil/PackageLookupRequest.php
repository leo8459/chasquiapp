<?php

namespace App\Http\Requests\Api\Movil;

class PackageLookupRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'code' => ['required', 'string', 'max:80'],
        ];
    }

    protected function prepareForValidation(): void
    {
        // El tracking busca por codigo normalizado, sin separadores ni espacios.
        $rawCode = preg_replace('/[^A-Z0-9]+/i', '', (string) $this->input('code')) ?? '';

        $this->merge([
            'code' => strtoupper(trim($rawCode)),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar un codigo valido.';
    }
}
