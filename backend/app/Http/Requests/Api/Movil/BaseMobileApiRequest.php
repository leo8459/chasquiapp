<?php

namespace App\Http\Requests\Api\Movil;

use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;

abstract class BaseMobileApiRequest extends FormRequest
{
    protected const PACKAGE_WEIGHT_REGEX = '/^(?:0|[1-9]\d{0,6})(?:\.\d{1,4})?$/';

    public function authorize(): bool
    {
        // La autorizacion fina se valida en middleware y servicios de dominio.
        return true;
    }

    protected function failedValidation(Validator $validator): void
    {
        // Todas las requests moviles devuelven el mismo formato JSON de error.
        throw new HttpResponseException(
            MobileApiResponse::validation(
                $this->validationMessage(),
                $validator->errors()->toArray(),
            ),
        );
    }

    protected function validationMessage(): string
    {
        return 'Revisa los datos enviados e intenta nuevamente.';
    }
}
