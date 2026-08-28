<?php

namespace App\Http\Requests\Api\Movil;

class MobileInventoryAssignmentStoreRequest extends BaseMobileApiRequest
{
    public function rules(): array
    {
        return [
            'package_type' => ['required', 'string', 'in:ems,certi,contrato,ordi'],
            'package_id' => ['nullable', 'integer', 'min:1'],
            'package_ids' => ['nullable', 'array', 'min:1'],
            'package_ids.*' => ['integer', 'min:1'],
        ];
    }

    protected function prepareForValidation(): void
    {
        $rawPackageIds = $this->input('package_ids');
        $normalizedPackageIds = is_array($rawPackageIds)
            ? array_values(array_filter(array_map(static function ($value): int {
                return (int) $value;
            }, $rawPackageIds), static function (int $value): bool {
                return $value > 0;
            }))
            : [];

        $singlePackageId = (int) $this->input('package_id');
        if ($singlePackageId > 0 && $normalizedPackageIds === []) {
            $normalizedPackageIds = [$singlePackageId];
        }

        // Los tipos de paquete se manejan en minusculas en servicios y endpoints.
        $this->merge([
            'package_type' => trim(strtolower((string) $this->input('package_type'))),
            'package_id' => $singlePackageId > 0 ? $singlePackageId : null,
            'package_ids' => $normalizedPackageIds,
        ]);
    }

    public function withValidator($validator): void
    {
        $validator->after(function ($validator): void {
            $packageId = (int) $this->input('package_id');
            $packageIds = $this->input('package_ids');
            $hasPackageIds = is_array($packageIds) && count($packageIds) > 0;

            if ($packageId <= 0 && ! $hasPackageIds) {
                $validator->errors()->add('package_id', $this->validationMessage());
            }
        });
    }

    protected function validationMessage(): string
    {
        return 'Debes enviar un tipo de servicio y un paquete valido para asignar.';
    }
}
