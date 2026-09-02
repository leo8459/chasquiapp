<?php

namespace App\Http\Requests\Api\Movil;

class SelfPackageDeliveryRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'code' => ['required', 'string', 'max:80'],
            'description' => ['nullable', 'string', 'max:1000'],
            'received_by' => ['required', 'string', 'min:3', 'max:120'],
            'delivered_at' => ['required', 'date'],
            'delivery_photo' => ['required', 'file', 'image', 'max:16384'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $this->merge([
            'code' => strtoupper(trim((string) $this->input('code'))),
            'description' => trim((string) $this->input('description')),
            'received_by' => trim((string) $this->input('received_by')),
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Revisa los datos de la entrega e intenta nuevamente.';
    }
}
