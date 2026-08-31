<?php

namespace App\Http\Requests\Api\Movil;

class MobileAuthLoginRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'alias' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'max:120'],
        ];
    }

    protected function prepareForValidation(): void
    {
        // El alias se normaliza en minusculas; la clave se mantiene intacta.
        $this->merge([
            'alias' => strtolower(trim((string) $this->input('alias'))),
            'password' => (string) $this->input('password'),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar credenciales validas.';
    }
}
