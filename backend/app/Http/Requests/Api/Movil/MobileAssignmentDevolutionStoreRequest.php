<?php

namespace App\Http\Requests\Api\Movil;

class MobileAssignmentDevolutionStoreRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'user_id' => ['required', 'integer', 'min:1'],
            'description' => ['required', 'string', 'min:3', 'max:300'],
            'delivery_attempt_photo' => ['required', 'file', 'image', 'max:16384'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $this->merge([
            'description' => trim((string) $this->input('description')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Completa el usuario del cartero, la descripcion y la foto de evidencia.';
    }
}
