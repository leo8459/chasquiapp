<?php

namespace App\Http\Requests\Api\Movil;

class MobileTransportInvoiceStoreRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'cod_especial' => ['required', 'string', 'max:50'],
            'tipo_transporte' => ['required', 'in:aereo,terrestre'],
            'transportadora' => ['required_if:tipo_transporte,terrestre', 'nullable', 'string', 'max:255'],
            'provincia' => ['nullable', 'string', 'max:255'],
            'factura' => ['required', 'string', 'max:255'],
            'precio_total' => ['required', 'numeric', 'min:0'],
            'peso' => ['required', 'numeric', 'min:0', 'max:150'],
            'imagen_factura' => ['required', 'file', 'mimes:jpg,jpeg,png,webp,pdf', 'max:10240'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $this->merge([
            'cod_especial' => strtoupper(trim((string) $this->input('cod_especial'))),
            'transportadora' => strtoupper(trim((string) $this->input('transportadora'))),
            'provincia' => strtoupper(trim((string) $this->input('provincia'))),
            'factura' => trim((string) $this->input('factura')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Completa los datos de transporte y factura, y adjunta el comprobante.';
    }
}
