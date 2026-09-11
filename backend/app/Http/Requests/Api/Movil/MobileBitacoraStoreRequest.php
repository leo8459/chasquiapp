<?php

namespace App\Http\Requests\Api\Movil;

class MobileBitacoraStoreRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'vehicles_id' => ['required', 'integer', 'min:1'],
            'drivers_id' => ['required', 'integer', 'min:1'],
            'fecha' => ['required', 'date_format:Y-m-d', 'before_or_equal:today'],
            'kilometraje_salida' => ['required', 'numeric', 'gt:0'],
            'kilometraje_recorrido' => ['required', 'numeric', 'min:0'],
            'recorrido_inicio' => ['required', 'string', 'max:500'],
            'recorrido_destino' => ['required', 'string', 'max:500', 'different:recorrido_inicio'],
            'latitud_inicio' => ['required', 'numeric', 'between:-90,90'],
            'logitud_inicio' => ['required', 'numeric', 'between:-180,180'],
            'latitud_destino' => ['required', 'numeric', 'between:-90,90'],
            'logitud_destino' => ['required', 'numeric', 'between:-180,180'],
            'odometro_photo' => ['required', 'file', 'image', 'max:16384'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $this->merge([
            'recorrido_inicio' => trim((string) $this->input('recorrido_inicio')),
            'recorrido_destino' => trim((string) $this->input('recorrido_destino')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Completa todos los datos y adjunta la foto del odometro.';
    }
}
