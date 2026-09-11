<?php

namespace App\Http\Controllers\Api\Gestion;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileGasolinaStoreRequest;
use App\Services\Gestion\SiopGasolinaService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileGasolinaController extends Controller
{
    use ResolvesMobileAuthUser;

    public function index(Request $request, SiopGasolinaService $service): JsonResponse
    {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success($service->list(
            max(1, $request->integer('page', 1)),
            max(1, min(100, $request->integer('per_page', 20))),
        ));
    }

    public function store(
        MobileGasolinaStoreRequest $request,
        SiopGasolinaService $service,
    ): JsonResponse {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success(
            $service->create(
                $request->safe()->except('invoice_photo'),
                $request->file('invoice_photo'),
            ),
            201,
        );
    }
}
