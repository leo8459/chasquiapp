<?php

namespace App\Http\Requests\Api\Movil;

class MobileAssignmentStatusUpdateRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'user_id' => ['required', 'integer', 'min:1'],
            'status' => ['required', 'string', 'max:40'],
        ];
    }

    protected function prepareForValidation(): void
    {
        // El servicio decide si el estado textual equivale a ASIGNADO o CARTERO.
        $this->merge([
            'status' => trim((string) $this->input('status')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar un usuario y un estado valido para la asignacion.';
    }
}
