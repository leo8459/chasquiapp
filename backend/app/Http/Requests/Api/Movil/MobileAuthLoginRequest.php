<?php

namespace App\Http\Requests\Api\Movil;

class MobileAuthLoginRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'email' => ['required', 'string', 'email', 'max:255'],
            'password' => ['required', 'string', 'max:120'],
        ];
    }

    protected function prepareForValidation(): void
    {
        // El email se compara en minusculas; la clave se mantiene intacta.
        $this->merge([
            'email' => strtolower(trim((string) $this->input('email'))),
            'password' => (string) $this->input('password'),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar credenciales validas.';
    }
}
