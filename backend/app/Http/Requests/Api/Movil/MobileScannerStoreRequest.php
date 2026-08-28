<?php

namespace App\Http\Requests\Api\Movil;

class MobileScannerStoreRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'barcode_text' => ['required', 'string', 'max:80'],
            'nombre' => ['required', 'string', 'max:255'],
            'telefono' => ['nullable', 'string', 'max:40'],
            'peso' => ['nullable', 'numeric'],
            'ciudad' => ['nullable', 'string', 'max:120'],
            'zona' => ['nullable', 'string', 'max:255'],
            'aduana' => ['nullable', 'boolean'],
            'ventanilla_id' => ['required', 'integer', 'min:1'],
            'ventanilla_nombre' => ['nullable', 'string', 'max:255'],
            'tipo_documento' => ['nullable', 'string', 'max:50'],
            'observaciones' => ['nullable', 'string', 'max:255'],
            'created_at' => ['nullable', 'string', 'max:60'],
        ];
    }

    protected function prepareForValidation(): void
    {
        // El scanner puede traer espacios o simbolos; para BD se guarda codigo limpio.
        $this->merge([
            'barcode_text' => strtoupper(trim(preg_replace('/[^A-Z0-9]+/i', '', (string) $this->input('barcode_text')) ?? '')),
            'nombre' => trim((string) $this->input('nombre')),
            'telefono' => trim((string) $this->input('telefono')),
            'ciudad' => trim((string) $this->input('ciudad')),
            'zona' => trim((string) $this->input('zona')),
            'ventanilla_nombre' => trim((string) $this->input('ventanilla_nombre')),
            'tipo_documento' => trim((string) $this->input('tipo_documento')),
            'observaciones' => trim((string) $this->input('observaciones')),
            'created_at' => trim((string) $this->input('created_at')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar datos validos para registrar el paquete.';
    }
}
