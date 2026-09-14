<?php

namespace App\Http\Requests\Api\Movil;

use Illuminate\Foundation\Http\FormRequest;

class CourierLocationHeartbeatRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'accuracy' => ['nullable', 'numeric', 'min:0'],
            'altitude' => ['nullable', 'numeric'],
            'speed' => ['nullable', 'numeric', 'min:0'],
            'heading' => ['nullable', 'numeric', 'between:0,360'],
            'captured_at' => ['nullable', 'date'],
        ];
    }

    public function messages(): array
    {
        return [
            'latitude.required' => 'No se recibio la latitud del dispositivo.',
            'latitude.between' => 'La latitud recibida no es valida.',
            'longitude.required' => 'No se recibio la longitud del dispositivo.',
            'longitude.between' => 'La longitud recibida no es valida.',
        ];
    }
}
