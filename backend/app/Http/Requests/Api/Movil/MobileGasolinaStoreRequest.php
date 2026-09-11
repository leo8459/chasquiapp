<?php

namespace App\Http\Requests\Api\Movil;

class MobileGasolinaStoreRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'vehicle_id' => ['required', 'integer', 'min:1'],
            'driver_id' => ['required', 'integer', 'min:1'],
            'numero_factura' => ['required', 'string', 'max:100'],
            'nombre_cliente' => ['required', 'string', 'max:255'],
            'fecha_emision' => ['required', 'date', 'before_or_equal:now'],
            'cantidad' => ['required', 'numeric', 'gt:0'],
            'precio_unitario' => ['required', 'numeric', 'gt:0'],
            'invoice_photo' => ['required', 'file', 'image', 'max:16384'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $this->merge([
            'numero_factura' => trim((string) $this->input('numero_factura')),
            'nombre_cliente' => trim((string) $this->input('nombre_cliente')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Completa todos los datos y adjunta la fotografía de la factura.';
    }
}
