<?php

namespace App\Http\Requests\Api\Movil;

use Illuminate\Validation\Rule;

class TrackingEventsRequest extends BaseMobileApiRequest
{
    private const ALLOWED_EVENT_TABLES = [
        'eventos_ems',
        'eventos_certi',
        'eventos_contrato',
        'eventos_ordi',
    ];

    public function rules(): array
    {
        return [
            'code' => ['required', 'string', 'max:80'],
            'table' => ['nullable', 'string', Rule::in(self::ALLOWED_EVENT_TABLES)],
            'limit' => ['nullable', 'integer', 'min:1', 'max:50'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $rawCode = preg_replace('/[^A-Z0-9]+/i', '', (string) $this->input('code')) ?? '';
        $rawTable = strtolower(trim((string) $this->input('table')));
        $limit = (int) $this->input('limit', 30);

        $this->merge([
            'code' => strtoupper(trim($rawCode)),
            'table' => $rawTable === '' ? null : $rawTable,
            'limit' => $limit > 0 ? $limit : 30,
        ]);
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar un codigo valido para consultar eventos.';
    }
}
