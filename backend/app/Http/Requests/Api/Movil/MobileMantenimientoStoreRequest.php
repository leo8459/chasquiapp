<?php

namespace App\Http\Requests\Api\Movil;

class MobileMantenimientoStoreRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'vehicle_id' => ['required', 'integer', 'min:1'],
            'maintenance_type_id' => ['required', 'integer', 'min:1'],
            'fecha_programada' => ['required', 'date'],
        ];
    }

    protected function validationMessage(): string
    {
        return 'Selecciona el vehiculo, el tipo de mantenimiento y la fecha programada.';
    }
}
